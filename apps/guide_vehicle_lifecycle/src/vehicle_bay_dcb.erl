%%% @doc DCB (Dynamic Consistency Boundary) enforcement for facility bay occupancy.
%%%
%%% Enforces the invariant: a bay can only have one vehicle docked at a time.
%%%
%%% Uses two DCB event types written to the `_dcb` pseudo-stream:
%%%
%%%   vehicle_docked_in_bay  — claimed when a vehicle docks
%%%   vehicle_left_bay       — released when a vehicle departs
%%%
%%% Both carry the tag `bay:<facility_id>:<bay_id>`. The conditional-append
%%% primitive makes the claim atomic and conflict-safe: two vehicles racing
%%% to the same bay both write to the same DCB position; one wins, the
%%% other gets `{error, {context_changed, _}}` and retries — at which point
%%% it observes the bay is occupied and refuses.
%%%
%%% Context-read strategy:
%%%   SeqCutoff = max seq of `vehicle_left_bay` events for this bay
%%%   ConflictFilter = {and_, [{event_type, "vehicle_docked_in_bay"},
%%%                             {any_of, ["bay:<fac>:<bay>"]}]}
%%%
%%% Meaning: "append only if no 'docked' event for this bay exists
%%% above the last 'left' event."
-module(vehicle_bay_dcb).

-include_lib("reckon_gater/include/reckon_gater_types.hrl").

-export([claim_bay/5, release_bay/5]).

-define(DOCKED, <<"vehicle_docked_in_bay">>).
-define(LEFT,   <<"vehicle_left_bay">>).
-define(MAX_RETRIES, 5).

%%====================================================================
%% Public API
%%====================================================================

%% @doc Attempt to claim a bay for VehicleId. Returns `ok` on success
%% or `{error, bay_already_occupied}` if the bay is currently taken.
-spec claim_bay(atom(), binary(), binary(), binary(), binary()) ->
    ok | {error, bay_already_occupied} | {error, term()}.
claim_bay(StoreId, FacilityId, BayId, VehicleId, Plate) ->
    Tag = bay_tag(FacilityId, BayId),
    do_claim(StoreId, FacilityId, BayId, VehicleId, Plate, Tag, ?MAX_RETRIES).

%% @doc Release the bay claim. Called after a vehicle departs.
%% Always appends — no conflict possible on exit.
-spec release_bay(atom(), binary(), binary(), binary(), binary()) ->
    ok | {error, term()}.
release_bay(StoreId, FacilityId, BayId, VehicleId, Plate) ->
    Tag   = bay_tag(FacilityId, BayId),
    Event = left_event(FacilityId, BayId, VehicleId, Plate, Tag),
    %% {any_of, []} matches nothing — always appends (unconditional).
    case reckon_gater_api:append_if_no_tag_matches(StoreId, {any_of, []}, -1, [Event]) of
        {ok, _}          -> ok;
        {error, _} = Err -> Err
    end.

%%====================================================================
%% Internal
%%====================================================================

do_claim(_, _, _, _, _, _, 0) ->
    {error, dcb_contention_exhausted};
do_claim(StoreId, FacilityId, BayId, VehicleId, Plate, Tag, Retries) ->
    {LastLeftSeq, IsOccupied} = read_bay_state(StoreId, Tag),
    case IsOccupied of
        true ->
            {error, bay_already_occupied};
        false ->
            Event  = docked_event(FacilityId, BayId, VehicleId, Plate, Tag),
            Filter = {and_, [{event_type, ?DOCKED}, {any_of, [Tag]}]},
            case reckon_gater_api:append_if_no_tag_matches(StoreId, Filter, LastLeftSeq, [Event]) of
                {ok, _} ->
                    ok;
                {error, {context_changed, _}} ->
                    do_claim(StoreId, FacilityId, BayId, VehicleId, Plate, Tag, Retries - 1);
                {error, _} = Err ->
                    Err
            end
    end.

%% Read all DCB events tagged for this bay and determine current occupancy.
%% Returns {LastLeftSeq, IsOccupied}:
%%   LastLeftSeq = max DCB seq of vehicle_left_bay events, or -1 if none
%%   IsOccupied  = true when the highest-seq event is vehicle_docked_in_bay
read_bay_state(StoreId, Tag) ->
    case reckon_gater_api:read_by_tags(StoreId, [Tag], #{batch_size => 200}) of
        {ok, Events} ->
            DcbEvents  = [E || #event{stream_id = <<"_dcb">>} = E <- Events],
            DockedSeqs = [E#event.version || #event{event_type = ?DOCKED} = E <- DcbEvents],
            LeftSeqs   = [E#event.version || #event{event_type = ?LEFT}   = E <- DcbEvents],
            LastLeftSeq   = max_or_default(LeftSeqs, -1),
            LastDockedSeq = max_or_default(DockedSeqs, -1),
            {LastLeftSeq, LastDockedSeq > LastLeftSeq};
        {error, _} ->
            %% Fail open: can't determine state → allow dock
            {-1, false}
    end.

docked_event(FacilityId, BayId, VehicleId, Plate, Tag) ->
    #{
        event_type => ?DOCKED,
        data       => #{facility_id => FacilityId, bay_id => BayId,
                        vehicle_id  => VehicleId, plate => Plate},
        metadata   => #{},
        %% Bay tag drives the occupancy DCB; plate + vehicle tags let you trace
        %% a single robotaxi's dock/leave history (pairs with left_event).
        tags       => [Tag, <<"plate:", Plate/binary>>,
                       <<"vehicle:", VehicleId/binary>>]
    }.

left_event(FacilityId, BayId, VehicleId, Plate, Tag) ->
    #{
        event_type => ?LEFT,
        %% Carry the plate (the robotaxi's real-world identity) and the
        %% vehicle id so a bay's dock/leave pair ties to the vehicle, not just
        %% the bay.
        data       => #{facility_id => FacilityId, bay_id => BayId,
                        vehicle_id  => VehicleId, plate => Plate},
        metadata   => #{},
        tags       => [Tag, <<"plate:", Plate/binary>>,
                       <<"vehicle:", VehicleId/binary>>]
    }.

bay_tag(FacilityId, BayId) -> <<"bay:", FacilityId/binary, ":", BayId/binary>>.

max_or_default([], Default) -> Default;
max_or_default(List, _)     -> lists:max(List).
