%%% @doc State module for the ride aggregate.
%%%
%%% Owns the state record, event folding, and serialisation. The aggregate
%%% delegates here for `new/1' and `apply_event/2'. The lifecycle phase is a
%%% STATE MACHINE: `set_phase/2' clears every phase bit and sets exactly one.
%%% Legal transitions are enforced by each handler's preconditions, not here —
%%% folding is unconditional and deterministic.
-module(ride_state).
-behaviour(evoq_state).

-include("ride_state.hrl").
-include("ride_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([
    ride_id/1, company_id/1, status_flags/1, party_size/1,
    fare_estimate_cents/1, fare_cents/1, vehicle_id/1,
    has_status/2, is_requested/1, is_assigned/1, is_started/1,
    is_completed/1, is_expired/1, is_pristine/1, is_active/1
]).

-type state() :: #ride_state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(AggregateId) ->
    #ride_state{ride_id = AggregateId}.

-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"ride_requested">>} = Ev) ->
    (set_phase(S, ?RIDE_REQUESTED))#ride_state{
        company_id          = g(company_id, Ev, S#ride_state.company_id),
        pickup_x            = g(pickup_x, Ev, S#ride_state.pickup_x),
        pickup_y            = g(pickup_y, Ev, S#ride_state.pickup_y),
        dropoff_x           = g(dropoff_x, Ev, S#ride_state.dropoff_x),
        dropoff_y           = g(dropoff_y, Ev, S#ride_state.dropoff_y),
        party_size          = g(party_size, Ev, S#ride_state.party_size),
        fare_estimate_cents = g(fare_estimate_cents, Ev, S#ride_state.fare_estimate_cents),
        requested_at        = g(requested_at, Ev, S#ride_state.requested_at),
        last_event_at       = g(requested_at, Ev, S#ride_state.last_event_at)
    };
apply_event(S, #{event_type := <<"ride_assigned">>} = Ev) ->
    (set_phase(S, ?RIDE_ASSIGNED))#ride_state{
        vehicle_id    = g(vehicle_id, Ev, S#ride_state.vehicle_id),
        last_event_at = g(assigned_at, Ev, S#ride_state.last_event_at)
    };
apply_event(S, #{event_type := <<"ride_started">>} = Ev) ->
    (set_phase(S, ?RIDE_STARTED))#ride_state{
        last_event_at = g(started_at, Ev, S#ride_state.last_event_at)
    };
apply_event(S, #{event_type := <<"ride_completed">>} = Ev) ->
    (set_phase(S, ?RIDE_COMPLETED))#ride_state{
        fare_cents    = g(fare_cents, Ev, S#ride_state.fare_cents),
        last_event_at = g(completed_at, Ev, S#ride_state.last_event_at)
    };
apply_event(S, #{event_type := <<"ride_expired">>} = Ev) ->
    (set_phase(S, ?RIDE_EXPIRED))#ride_state{
        last_event_at = g(expired_at, Ev, S#ride_state.last_event_at)
    };
apply_event(S, _UnknownEvent) ->
    S.

-spec to_map(state()) -> map().
to_map(#ride_state{} = S) ->
    #{ride_id             => S#ride_state.ride_id,
      company_id          => S#ride_state.company_id,
      status_flags        => S#ride_state.status_flags,
      pickup_x            => S#ride_state.pickup_x,
      pickup_y            => S#ride_state.pickup_y,
      dropoff_x           => S#ride_state.dropoff_x,
      dropoff_y           => S#ride_state.dropoff_y,
      party_size          => S#ride_state.party_size,
      fare_estimate_cents => S#ride_state.fare_estimate_cents,
      fare_cents          => S#ride_state.fare_cents,
      vehicle_id          => S#ride_state.vehicle_id,
      requested_at        => S#ride_state.requested_at,
      last_event_at       => S#ride_state.last_event_at}.

%%--------------------------------------------------------------------
%% Phase machine

-spec set_phase(state(), non_neg_integer()) -> state().
set_phase(#ride_state{status_flags = F} = S, Phase) ->
    Cleared = evoq_bit_flags:unset_all(F, ?RIDE_ALL_PHASES),
    S#ride_state{status_flags = evoq_bit_flags:set(Cleared, Phase)}.

%%--------------------------------------------------------------------
%% Accessors

ride_id(#ride_state{ride_id = V})                         -> V.
company_id(#ride_state{company_id = V})                   -> V.
status_flags(#ride_state{status_flags = V})               -> V.
party_size(#ride_state{party_size = V})                   -> V.
fare_estimate_cents(#ride_state{fare_estimate_cents = V}) -> V.
fare_cents(#ride_state{fare_cents = V})                   -> V.
vehicle_id(#ride_state{vehicle_id = V})                   -> V.

has_status(#ride_state{status_flags = F}, Flag) ->
    F band Flag =/= 0.

is_requested(S) -> has_status(S, ?RIDE_REQUESTED).
is_assigned(S)  -> has_status(S, ?RIDE_ASSIGNED).
is_started(S)   -> has_status(S, ?RIDE_STARTED).
is_completed(S) -> has_status(S, ?RIDE_COMPLETED).
is_expired(S)   -> has_status(S, ?RIDE_EXPIRED).

%% Never folded any event yet — no phase bit set.
is_pristine(#ride_state{status_flags = 0}) -> true;
is_pristine(#ride_state{})                 -> false.

%% In flight: requested, assigned, or started (not yet completed/expired).
is_active(S) ->
    is_requested(S) orelse is_assigned(S) orelse is_started(S).

%%--------------------------------------------------------------------
g(K, M, Default) -> maps:get(K, M, Default).
