%%% @doc State module for the parking_session aggregate.
%%%
%%% Owns the state record, event folding, and serialisation. The
%%% aggregate delegates here for `init/1` (via `new/1`) and
%%% `apply_event/2`.
-module(parking_session_state).
-behaviour(evoq_state).

-include("parking_session_state.hrl").
-include("parking_session_status.hrl").

-export([new/1, apply_event/2, to_map/1]).

-export([
    session_id/1, lot_id/1, status_flags/1, plate/1, card_id/1, permit_ref/1,
    entered_at/1, bay_id/1, docked_at/1, undocked_at/1,
    paid_at/1, fee_cents/1, archived_at/1, archive_reason/1,
    has_status/2, is_initiated/1, is_docked/1, is_undocked/1,
    is_paid/1, is_permit_covered/1, is_settled/1, is_archived/1
]).

-type state() :: #parking_session_state{}.
-export_type([state/0]).

%% @doc Initial empty state for a new aggregate instance.
-spec new(binary()) -> state().
new(AggregateId) ->
    #parking_session_state{session_id = AggregateId}.

%% @doc Fold an event into state. Pure and deterministic.
-spec apply_event(state(), map()) -> state().
apply_event(#parking_session_state{status_flags = F} = S,
            #{event_type := <<"parking_session_initiated">>} = Ev) ->
    S#parking_session_state{
        status_flags = evoq_bit_flags:set(F, ?SESSION_INITIATED),
        lot_id     = maps:get(lot_id,     Ev, S#parking_session_state.lot_id),
        plate      = maps:get(plate,      Ev, S#parking_session_state.plate),
        card_id    = maps:get(card_id,    Ev, S#parking_session_state.card_id),
        permit_ref = maps:get(permit_ref, Ev, S#parking_session_state.permit_ref),
        entered_at = maps:get(entered_at, Ev, S#parking_session_state.entered_at)
    };
apply_event(#parking_session_state{status_flags = F} = S,
            #{event_type := <<"vehicle_docked">>} = Ev) ->
    S#parking_session_state{
        status_flags = evoq_bit_flags:set(F, ?SESSION_DOCKED),
        bay_id    = maps:get(bay_id,    Ev, S#parking_session_state.bay_id),
        docked_at = maps:get(docked_at, Ev, S#parking_session_state.docked_at)
    };
apply_event(#parking_session_state{status_flags = F} = S,
            #{event_type := <<"vehicle_undocked">>} = Ev) ->
    S#parking_session_state{
        status_flags = evoq_bit_flags:set(F, ?SESSION_UNDOCKED),
        undocked_at  = maps:get(undocked_at, Ev, S#parking_session_state.undocked_at)
    };
apply_event(#parking_session_state{status_flags = F} = S,
            #{event_type := <<"payment_captured">>} = Ev) ->
    S#parking_session_state{
        status_flags = evoq_bit_flags:set(F, ?SESSION_PAID),
        paid_at      = maps:get(paid_at,      Ev, S#parking_session_state.paid_at),
        fee_cents = maps:get(fee_cents, Ev, S#parking_session_state.fee_cents)
    };
apply_event(#parking_session_state{status_flags = F} = S,
            #{event_type := <<"parking_session_archived">>} = Ev) ->
    S#parking_session_state{
        status_flags   = evoq_bit_flags:set(F, ?SESSION_ARCHIVED),
        archived_at    = maps:get(archived_at, Ev, S#parking_session_state.archived_at),
        archive_reason = maps:get(reason,      Ev, S#parking_session_state.archive_reason)
    };
apply_event(S, _UnknownEvent) ->
    S.

%% @doc Serialise the state for diagnostics / inspection.
-spec to_map(state()) -> map().
to_map(#parking_session_state{} = S) ->
    #{session_id     => S#parking_session_state.session_id,
      lot_id         => S#parking_session_state.lot_id,
      status_flags   => S#parking_session_state.status_flags,
      plate          => S#parking_session_state.plate,
      card_id        => S#parking_session_state.card_id,
      permit_ref     => S#parking_session_state.permit_ref,
      entered_at     => S#parking_session_state.entered_at,
      bay_id         => S#parking_session_state.bay_id,
      docked_at      => S#parking_session_state.docked_at,
      undocked_at    => S#parking_session_state.undocked_at,
      paid_at        => S#parking_session_state.paid_at,
      fee_cents   => S#parking_session_state.fee_cents,
      archived_at    => S#parking_session_state.archived_at,
      archive_reason => S#parking_session_state.archive_reason}.

%%--------------------------------------------------------------------
%% Accessors

session_id(#parking_session_state{session_id = V})         -> V.
lot_id(#parking_session_state{lot_id = V})                 -> V.
status_flags(#parking_session_state{status_flags = V})     -> V.
plate(#parking_session_state{plate = V})                   -> V.
card_id(#parking_session_state{card_id = V})               -> V.
permit_ref(#parking_session_state{permit_ref = V})         -> V.
entered_at(#parking_session_state{entered_at = V})         -> V.
bay_id(#parking_session_state{bay_id = V})                 -> V.
docked_at(#parking_session_state{docked_at = V})           -> V.
undocked_at(#parking_session_state{undocked_at = V})       -> V.
paid_at(#parking_session_state{paid_at = V})               -> V.
fee_cents(#parking_session_state{fee_cents = V})     -> V.
archived_at(#parking_session_state{archived_at = V})       -> V.
archive_reason(#parking_session_state{archive_reason = V}) -> V.

has_status(#parking_session_state{status_flags = F}, Flag) ->
    F band Flag =/= 0.

is_initiated(S) -> has_status(S, ?SESSION_INITIATED).
is_docked(S)    -> has_status(S, ?SESSION_DOCKED).
is_undocked(S)  -> has_status(S, ?SESSION_UNDOCKED).
is_paid(S)      -> has_status(S, ?SESSION_PAID).
is_archived(S)  -> has_status(S, ?SESSION_ARCHIVED).

%% Covered by a permit (settled for the whole visit at entry).
is_permit_covered(#parking_session_state{permit_ref = undefined}) -> false;
is_permit_covered(#parking_session_state{permit_ref = <<>>})      -> false;
is_permit_covered(#parking_session_state{permit_ref = _})         -> true.

%% A session is settled when it has been paid (ticket) OR is covered by
%% a permit (permit holders are pre-paid for the permit's validity).
is_settled(S) -> is_paid(S) orelse is_permit_covered(S).
