%%% @doc State module for the vehicle (robotaxi) aggregate.
%%%
%%% Owns the state record, event folding, and serialisation. The
%%% aggregate delegates here for `init/1` (via `new/1`) and
%%% `apply_event/2`.
%%%
%%% The operating phase is a STATE MACHINE: `set_phase/2` clears every
%%% phase bit and sets exactly one. Legal transitions are enforced by
%%% each handler's preconditions (the `is_*`/`can_*` helpers), not here —
%%% folding is unconditional and deterministic.
-module(vehicle_state).
-behaviour(evoq_state).

-include("vehicle_state.hrl").
-include("vehicle_status.hrl").

-export([new/1, apply_event/2, to_map/1]).

-export([
    vehicle_id/1, plate/1, company_id/1, status_flags/1, battery_pct/1,
    x/1, y/1, ride_id/1, trip_id/1, facility_id/1, bay_id/1, service_kind/1,
    trips_completed/1, fares_cents/1,
    has_status/2, is_commissioned/1, is_cruising/1, is_dispatched/1,
    is_on_trip/1, is_returning/1, is_docked/1, is_servicing/1, is_depleted/1,
    is_pristine/1, is_available/1
]).

-type state() :: #vehicle_state{}.
-export_type([state/0]).

%% @doc Initial empty state for a new aggregate instance.
-spec new(binary()) -> state().
new(AggregateId) ->
    #vehicle_state{vehicle_id = AggregateId}.

%% @doc Fold an event into state. Pure and deterministic.
-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"vehicle_commissioned">>} = Ev) ->
    (set_phase(S, ?VEH_COMMISSIONED))#vehicle_state{
        plate           = g(plate, Ev, S#vehicle_state.plate),
        company_id      = g(company_id, Ev, S#vehicle_state.company_id),
        battery_pct     = g(battery_pct, Ev, S#vehicle_state.battery_pct),
        x             = g(x, Ev, S#vehicle_state.x),
        y             = g(y, Ev, S#vehicle_state.y),
        commissioned_at = g(commissioned_at, Ev, S#vehicle_state.commissioned_at),
        last_event_at   = g(commissioned_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"vehicle_dispatched">>} = Ev) ->
    (set_phase(S, ?VEH_DISPATCHED))#vehicle_state{
        ride_id       = g(ride_id, Ev, S#vehicle_state.ride_id),
        trip_id       = g(trip_id, Ev, S#vehicle_state.trip_id),
        pickup_x    = g(pickup_x, Ev, S#vehicle_state.pickup_x),
        pickup_y    = g(pickup_y, Ev, S#vehicle_state.pickup_y),
        dropoff_x   = g(dropoff_x, Ev, S#vehicle_state.dropoff_x),
        dropoff_y   = g(dropoff_y, Ev, S#vehicle_state.dropoff_y),
        last_event_at = g(dispatched_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"passenger_picked_up">>} = Ev) ->
    (set_phase(S, ?VEH_ON_TRIP))#vehicle_state{
        x           = g(x, Ev, S#vehicle_state.x),
        y           = g(y, Ev, S#vehicle_state.y),
        last_event_at = g(picked_up_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"passenger_dropped_off">>} = Ev) ->
    %% Trip complete -> back to the revenue pool. Clear the trip slots.
    (set_phase(S, ?VEH_CRUISING))#vehicle_state{
        x             = g(x, Ev, S#vehicle_state.x),
        y             = g(y, Ev, S#vehicle_state.y),
        ride_id         = undefined,
        trip_id         = undefined,
        pickup_x      = undefined,
        pickup_y      = undefined,
        dropoff_x     = undefined,
        dropoff_y     = undefined,
        trips_completed = S#vehicle_state.trips_completed + 1,
        last_event_at   = g(dropped_off_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"fare_collected">>} = Ev) ->
    %% No phase change — rides alongside the drop-off. Just bank the fare.
    S#vehicle_state{
        fares_cents   = S#vehicle_state.fares_cents + g(fare_cents, Ev, 0),
        last_event_at = g(collected_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"vehicle_returning">>} = Ev) ->
    (set_phase(S, ?VEH_RETURNING))#vehicle_state{
        facility_id   = g(facility_id, Ev, S#vehicle_state.facility_id),
        last_event_at = g(returning_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"vehicle_docked_at_facility">>} = Ev) ->
    (set_phase(S, ?VEH_DOCKED))#vehicle_state{
        facility_id   = g(facility_id, Ev, S#vehicle_state.facility_id),
        bay_id        = g(bay_id, Ev, S#vehicle_state.bay_id),
        x           = g(x, Ev, S#vehicle_state.x),
        y           = g(y, Ev, S#vehicle_state.y),
        last_event_at = g(docked_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"battery_charged">>} = Ev) ->
    %% A charge tops the battery back up. Its own event now (split out of
    %% vehicle_serviced); still occupies the SERVICING phase at a facility.
    (set_phase(S, ?VEH_SERVICING))#vehicle_state{
        service_kind  = <<"charge">>,
        battery_pct   = g(battery_pct, Ev, 100),
        last_event_at = g(charged_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"vehicle_cleaned">>} = Ev) ->
    (set_phase(S, ?VEH_SERVICING))#vehicle_state{
        service_kind  = <<"clean">>,
        last_event_at = g(cleaned_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"vehicle_maintained">>} = Ev) ->
    (set_phase(S, ?VEH_SERVICING))#vehicle_state{
        service_kind  = <<"maintain">>,
        last_event_at = g(maintained_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"vehicle_released">>} = Ev) ->
    %% Bay freed, back to cruising.
    (set_phase(S, ?VEH_CRUISING))#vehicle_state{
        facility_id   = undefined,
        bay_id        = undefined,
        service_kind  = undefined,
        last_event_at = g(released_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"tow_requested">>} = Ev) ->
    S#vehicle_state{last_event_at = g(requested_at, Ev, S#vehicle_state.last_event_at)};
apply_event(S, #{event_type := <<"tow_truck_dispatched">>} = Ev) ->
    S#vehicle_state{last_event_at = g(dispatched_at, Ev, S#vehicle_state.last_event_at)};
apply_event(S, #{event_type := <<"vehicle_towed">>} = Ev) ->
    (set_phase(S, ?VEH_RETURNING))#vehicle_state{
        facility_id   = g(destination_facility_id, Ev, S#vehicle_state.facility_id),
        x             = g(from_x, Ev, S#vehicle_state.x),
        y             = g(from_y, Ev, S#vehicle_state.y),
        last_event_at = g(towed_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, #{event_type := <<"battery_depleted">>} = Ev) ->
    (set_phase(S, ?VEH_DEPLETED))#vehicle_state{
        battery_pct   = 0,
        x           = g(x, Ev, S#vehicle_state.x),
        y           = g(y, Ev, S#vehicle_state.y),
        last_event_at = g(depleted_at, Ev, S#vehicle_state.last_event_at)
    };
apply_event(S, _UnknownEvent) ->
    S.

%% @doc Serialise the state for diagnostics / inspection.
-spec to_map(state()) -> map().
to_map(#vehicle_state{} = S) ->
    #{vehicle_id      => S#vehicle_state.vehicle_id,
      company_id      => S#vehicle_state.company_id,
      status_flags    => S#vehicle_state.status_flags,
      battery_pct     => S#vehicle_state.battery_pct,
      x             => S#vehicle_state.x,
      y             => S#vehicle_state.y,
      ride_id         => S#vehicle_state.ride_id,
      trip_id         => S#vehicle_state.trip_id,
      pickup_x      => S#vehicle_state.pickup_x,
      pickup_y      => S#vehicle_state.pickup_y,
      dropoff_x     => S#vehicle_state.dropoff_x,
      dropoff_y     => S#vehicle_state.dropoff_y,
      facility_id     => S#vehicle_state.facility_id,
      bay_id          => S#vehicle_state.bay_id,
      service_kind    => S#vehicle_state.service_kind,
      trips_completed => S#vehicle_state.trips_completed,
      fares_cents     => S#vehicle_state.fares_cents,
      commissioned_at => S#vehicle_state.commissioned_at,
      last_event_at   => S#vehicle_state.last_event_at}.

%%--------------------------------------------------------------------
%% Phase machine

%% Clear every phase bit, then set exactly one. The vehicle is always in
%% exactly one operating phase.
-spec set_phase(state(), non_neg_integer()) -> state().
set_phase(#vehicle_state{status_flags = F} = S, Phase) ->
    Cleared = evoq_bit_flags:unset_all(F, ?VEH_ALL_PHASES),
    S#vehicle_state{status_flags = evoq_bit_flags:set(Cleared, Phase)}.

%%--------------------------------------------------------------------
%% Accessors

vehicle_id(#vehicle_state{vehicle_id = V})           -> V.
company_id(#vehicle_state{company_id = V})           -> V.
plate(#vehicle_state{plate = V})                     -> V.
status_flags(#vehicle_state{status_flags = V})       -> V.
battery_pct(#vehicle_state{battery_pct = V})         -> V.
x(#vehicle_state{x = V})                         -> V.
y(#vehicle_state{y = V})                         -> V.
ride_id(#vehicle_state{ride_id = V})                 -> V.
trip_id(#vehicle_state{trip_id = V})                 -> V.
facility_id(#vehicle_state{facility_id = V})         -> V.
bay_id(#vehicle_state{bay_id = V})                   -> V.
service_kind(#vehicle_state{service_kind = V})       -> V.
trips_completed(#vehicle_state{trips_completed = V}) -> V.
fares_cents(#vehicle_state{fares_cents = V})         -> V.

has_status(#vehicle_state{status_flags = F}, Flag) ->
    F band Flag =/= 0.

is_commissioned(S) -> has_status(S, ?VEH_COMMISSIONED).
is_cruising(S)     -> has_status(S, ?VEH_CRUISING).
is_dispatched(S)   -> has_status(S, ?VEH_DISPATCHED).
is_on_trip(S)      -> has_status(S, ?VEH_ON_TRIP).
is_returning(S)    -> has_status(S, ?VEH_RETURNING).
is_docked(S)       -> has_status(S, ?VEH_DOCKED).
is_servicing(S)    -> has_status(S, ?VEH_SERVICING).
is_depleted(S)     -> has_status(S, ?VEH_DEPLETED).

%% Never folded any event yet — no phase bit set.
is_pristine(#vehicle_state{status_flags = 0}) -> true;
is_pristine(#vehicle_state{})                 -> false.

%% Available to take a fare: freshly commissioned or idling/cruising.
is_available(S) -> is_commissioned(S) orelse is_cruising(S).

%%--------------------------------------------------------------------
%% Helpers

g(K, M, Default) -> maps:get(K, M, Default).
