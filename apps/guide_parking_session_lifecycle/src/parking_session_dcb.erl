%%% @doc DCB (Dynamic Consistency Boundary) enforcement for vehicle parking.
%%%
%%% Enforces the invariant: a vehicle (identified by plate) can only have
%%% one active parking session at a time — it cannot be in two lots at once.
%%%
%%% Uses two DCB event types written to the `_dcb` pseudo-stream:
%%%
%%%   vehicle_entered_lot  — claimed when a session is initiated
%%%   vehicle_exited_lot   — released when a session is archived
%%%
%%% Both carry the tag `plate:<plate>`. The conditional-append primitive
%%% (`append_if_no_tag_matches`) makes the claim atomic and conflict-safe:
%%% a concurrent entry for the same plate races to the same DCB position,
%%% one wins, the other gets `{error, {context_changed, _}}` and retries —
%%% at which point it observes the plate is already parked and refuses.
%%%
%%% Context-read strategy:
%%%   SeqCutoff = max seq of `vehicle_exited_lot` events for this plate
%%%   ConflictFilter = {and_, [{event_type, "vehicle_entered_lot"},
%%%                             {any_of, ["plate:<plate>"]}]}
%%%
%%% Meaning: "append only if no 'entered' event for this plate exists
%%% above the last 'exited' event." If the vehicle is currently parked
%%% (entered > exited), the filter finds the entered event and rejects.
-module(parking_session_dcb).

-include_lib("reckon_gater/include/reckon_gater_types.hrl").

-export([claim_entry/4, release_entry/4]).

-define(ENTERED, <<"vehicle_entered_lot">>).
-define(EXITED,  <<"vehicle_exited_lot">>).
-define(MAX_RETRIES, 5).

%%====================================================================
%% Public API
%%====================================================================

%% @doc Attempt to claim a parking slot for the vehicle identified by Plate.
%% Returns `ok` on success or `{error, already_parked}` if the plate
%% currently has an active session.
-spec claim_entry(atom(), binary(), binary(), binary()) ->
    ok | {error, already_parked} | {error, term()}.
claim_entry(StoreId, Plate, LotId, SessionId) ->
    PlateTag = plate_tag(Plate),
    do_claim(StoreId, Plate, LotId, SessionId, PlateTag, ?MAX_RETRIES).

%% @doc Release the parking slot for the vehicle. Called after a session
%% is archived. Always appends — no conflict possible on exit. Carries the
%% `lot_id' so the exit is symmetric with the entry (same identity).
-spec release_entry(atom(), binary(), binary(), binary()) -> ok | {error, term()}.
release_entry(StoreId, Plate, LotId, SessionId) ->
    PlateTag = plate_tag(Plate),
    Event = exited_event(Plate, LotId, SessionId, PlateTag),
    %% {any_of, []} matches nothing — always appends (unconditional).
    case reckon_gater_api:append_if_no_tag_matches(StoreId, {any_of, []}, -1, [Event]) of
        {ok, _}         -> ok;
        {error, _} = Err -> Err
    end.

%%====================================================================
%% Internal
%%====================================================================

do_claim(_, _, _, _, _, 0) ->
    {error, dcb_contention_exhausted};
do_claim(StoreId, Plate, LotId, SessionId, PlateTag, Retries) ->
    {LastExitSeq, IsParked} = read_plate_state(StoreId, PlateTag),
    case IsParked of
        true ->
            {error, already_parked};
        false ->
            Event = entered_event(Plate, LotId, SessionId, PlateTag),
            Filter = {and_, [{event_type, ?ENTERED}, {any_of, [PlateTag]}]},
            case reckon_gater_api:append_if_no_tag_matches(StoreId, Filter, LastExitSeq, [Event]) of
                {ok, _} ->
                    ok;
                {error, {context_changed, _}} ->
                    do_claim(StoreId, Plate, LotId, SessionId, PlateTag, Retries - 1);
                {error, _} = Err ->
                    Err
            end
    end.

%% Read all DCB events tagged with this plate and determine current state.
%% Returns {LastExitSeq, IsParked}:
%%   LastExitSeq = max DCB seq of vehicle_exited_lot events, or -1 if none
%%   IsParked    = true when the highest-seq event is vehicle_entered_lot
read_plate_state(StoreId, PlateTag) ->
    %% Plates are drawn from a reused pool, so a plate's DCB history grows two
    %% events per visit and is unbounded. read_by_tags has no backward/cursor
    %% read, so a small batch truncates to the OLDEST events and mis-reads the
    %% current park state (→ perpetually-failing conditional claims). Read a
    %% wide window so the latest entry/exit is always in view. The real fix
    %% (compaction / a lot-membership read model) is tracked in
    %% DESIGN_PARKSIM_ENTITY_MODEL.md.
    case reckon_gater_api:read_by_tags(StoreId, [PlateTag], #{batch_size => 100000}) of
        {ok, Events} ->
            DcbEvents = [E || #event{stream_id = <<"_dcb">>} = E <- Events],
            EnteredSeqs = [E#event.version || #event{event_type = ?ENTERED} = E <- DcbEvents],
            ExitedSeqs  = [E#event.version || #event{event_type = ?EXITED}  = E <- DcbEvents],
            LastExitSeq    = max_or_default(ExitedSeqs, -1),
            LastEnteredSeq = max_or_default(EnteredSeqs, -1),
            {LastExitSeq, LastEnteredSeq > LastExitSeq};
        {error, _} ->
            %% Fail open: can't determine state → allow entry
            {-1, false}
    end.

entered_event(Plate, LotId, SessionId, PlateTag) ->
    #{
        event_type => ?ENTERED,
        data       => #{plate => Plate, lot_id => LotId, session_id => SessionId},
        metadata   => #{},
        tags       => [PlateTag]
    }.

exited_event(Plate, LotId, SessionId, PlateTag) ->
    #{
        event_type => ?EXITED,
        data       => #{plate => Plate, lot_id => LotId, session_id => SessionId},
        metadata   => #{},
        tags       => [PlateTag]
    }.

plate_tag(Plate) -> <<"plate:", Plate/binary>>.

max_or_default([], Default) -> Default;
max_or_default(List, _)     -> lists:max(List).
