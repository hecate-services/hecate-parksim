%%% @doc State module for the charging-session aggregate.
%%%
%%% Owns the state record, event folding, and serialisation. The lifecycle
%%% phase is a STATE MACHINE: `set_phase/2' clears every phase bit and sets
%%% exactly one. Legal transitions are enforced by each handler's preconditions,
%%% not here — folding is unconditional and deterministic. `energy_settled'
%%% adds a flag without changing the phase (a completed session stays completed).
-module(charging_state).
-behaviour(evoq_state).

-include("charging_state.hrl").
-include("charging_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([
    session_id/1, vehicle_id/1, company_id/1, status_flags/1,
    battery_pct/1, target_pct/1, tariff_cents_per_kwh/1, energy_kwh/1,
    has_status/2, is_requested/1, is_charging/1, is_completed/1,
    is_settled/1, is_pristine/1
]).

-type state() :: #charging_state{}.
-export_type([state/0]).

-spec new(binary()) -> state().
new(AggregateId) ->
    #charging_state{session_id = AggregateId}.

-spec apply_event(state(), map()) -> state().
apply_event(S, #{event_type := <<"charge_requested">>} = Ev) ->
    (set_phase(S, ?CHARGE_REQUESTED))#charging_state{
        vehicle_id           = g(vehicle_id, Ev, S#charging_state.vehicle_id),
        company_id           = g(company_id, Ev, S#charging_state.company_id),
        plate                = g(plate, Ev, S#charging_state.plate),
        battery_pct_before   = g(battery_pct_before, Ev, S#charging_state.battery_pct_before),
        battery_pct          = g(battery_pct_before, Ev, S#charging_state.battery_pct),
        target_pct           = g(target_pct, Ev, S#charging_state.target_pct),
        tariff_cents_per_kwh = g(tariff_cents_per_kwh, Ev, S#charging_state.tariff_cents_per_kwh),
        requested_at         = g(requested_at, Ev, S#charging_state.requested_at),
        last_event_at        = g(requested_at, Ev, S#charging_state.last_event_at)
    };
apply_event(S, #{event_type := <<"charging_started">>} = Ev) ->
    (set_phase(S, ?CHARGING))#charging_state{
        charger_id           = g(charger_id, Ev, S#charging_state.charger_id),
        battery_pct_before   = g(battery_pct_before, Ev, S#charging_state.battery_pct_before),
        tariff_cents_per_kwh = g(tariff_cents_per_kwh, Ev, S#charging_state.tariff_cents_per_kwh),
        started_at           = g(started_at, Ev, S#charging_state.started_at),
        last_event_at        = g(started_at, Ev, S#charging_state.last_event_at)
    };
apply_event(S, #{event_type := <<"charging_progressed">>} = Ev) ->
    %% Stays in the CHARGING phase; SoC climbs and energy accumulates.
    S#charging_state{
        battery_pct   = g(soc_pct, Ev, S#charging_state.battery_pct),
        energy_kwh    = g(energy_kwh_total, Ev, S#charging_state.energy_kwh),
        last_event_at = g(progressed_at, Ev, S#charging_state.last_event_at)
    };
apply_event(S, #{event_type := <<"charging_completed">>} = Ev) ->
    (set_phase(S, ?CHARGE_COMPLETED))#charging_state{
        battery_pct   = g(final_soc_pct, Ev, S#charging_state.battery_pct),
        energy_kwh    = g(energy_kwh, Ev, S#charging_state.energy_kwh),
        completed_at  = g(completed_at, Ev, S#charging_state.completed_at),
        last_event_at = g(completed_at, Ev, S#charging_state.last_event_at)
    };
apply_event(S, #{event_type := <<"energy_settled">>} = Ev) ->
    %% Additive: keeps the completed phase, records the cost.
    S#charging_state{
        status_flags  = evoq_bit_flags:set(S#charging_state.status_flags, ?ENERGY_SETTLED),
        cost_cents    = g(cost_cents, Ev, S#charging_state.cost_cents),
        off_peak      = g(off_peak, Ev, S#charging_state.off_peak),
        settled_at    = g(settled_at, Ev, S#charging_state.settled_at),
        last_event_at = g(settled_at, Ev, S#charging_state.last_event_at)
    };
apply_event(S, _UnknownEvent) ->
    S.

-spec to_map(state()) -> map().
to_map(#charging_state{} = S) ->
    #{session_id           => S#charging_state.session_id,
      vehicle_id           => S#charging_state.vehicle_id,
      company_id           => S#charging_state.company_id,
      plate                => S#charging_state.plate,
      status_flags         => S#charging_state.status_flags,
      charger_id           => S#charging_state.charger_id,
      battery_pct_before   => S#charging_state.battery_pct_before,
      battery_pct          => S#charging_state.battery_pct,
      target_pct           => S#charging_state.target_pct,
      tariff_cents_per_kwh => S#charging_state.tariff_cents_per_kwh,
      energy_kwh           => S#charging_state.energy_kwh,
      cost_cents           => S#charging_state.cost_cents,
      off_peak             => S#charging_state.off_peak,
      requested_at         => S#charging_state.requested_at,
      started_at           => S#charging_state.started_at,
      completed_at         => S#charging_state.completed_at,
      settled_at           => S#charging_state.settled_at,
      last_event_at        => S#charging_state.last_event_at}.

%%--------------------------------------------------------------------
%% Phase machine

-spec set_phase(state(), non_neg_integer()) -> state().
set_phase(#charging_state{status_flags = F} = S, Phase) ->
    Cleared = evoq_bit_flags:unset_all(F, ?CHARGE_ALL_PHASES),
    S#charging_state{status_flags = evoq_bit_flags:set(Cleared, Phase)}.

%%--------------------------------------------------------------------
%% Accessors

session_id(#charging_state{session_id = V})                     -> V.
vehicle_id(#charging_state{vehicle_id = V})                     -> V.
company_id(#charging_state{company_id = V})                     -> V.
status_flags(#charging_state{status_flags = V})                 -> V.
battery_pct(#charging_state{battery_pct = V})                   -> V.
target_pct(#charging_state{target_pct = V})                     -> V.
tariff_cents_per_kwh(#charging_state{tariff_cents_per_kwh = V}) -> V.
energy_kwh(#charging_state{energy_kwh = V})                     -> V.

has_status(#charging_state{status_flags = F}, Flag) ->
    F band Flag =/= 0.

is_requested(S) -> has_status(S, ?CHARGE_REQUESTED).
is_charging(S)  -> has_status(S, ?CHARGING).
is_completed(S) -> has_status(S, ?CHARGE_COMPLETED).
is_settled(S)   -> has_status(S, ?ENERGY_SETTLED).

is_pristine(#charging_state{status_flags = 0}) -> true;
is_pristine(#charging_state{})                 -> false.

%%--------------------------------------------------------------------
g(K, M, Default) -> maps:get(K, M, Default).
