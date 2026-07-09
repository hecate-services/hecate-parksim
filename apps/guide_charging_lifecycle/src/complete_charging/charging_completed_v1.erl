%%% @doc Event `charging_completed_v1`. The session finished — final SoC, total
%%% energy, and the battery wear (cycle + SoH) this charge cost the asset.
-module(charging_completed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_vehicle_id/1, get_final_soc_pct/1,
         get_energy_kwh/1, get_charge_cycle/1, get_battery_soh_pct/1,
         get_completed_at/1]).

-record(charging_completed_v1, {
    session_id      :: binary() | undefined,
    vehicle_id      :: binary() | undefined,
    final_soc_pct   :: number() | undefined,
    energy_kwh      :: number() | undefined,
    charge_cycle    :: non_neg_integer() | undefined,
    battery_soh_pct :: number() | undefined,
    completed_at    :: binary() | undefined
}).

-opaque t() :: #charging_completed_v1{}.
-export_type([t/0]).

event_type() -> charging_completed_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{session_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)}.

from(G, Id) ->
    #charging_completed_v1{
        session_id      = Id,
        vehicle_id      = G(vehicle_id, undefined),
        final_soc_pct   = G(final_soc_pct, 100),
        energy_kwh      = G(energy_kwh, undefined),
        charge_cycle    = G(charge_cycle, undefined),
        battery_soh_pct = G(battery_soh_pct, undefined),
        completed_at    = G(completed_at, undefined)
    }.

-spec to_map(t()) -> map().
to_map(#charging_completed_v1{} = E) ->
    #{event_type      => <<"charging_completed">>,
      session_id      => E#charging_completed_v1.session_id,
      vehicle_id      => E#charging_completed_v1.vehicle_id,
      final_soc_pct   => E#charging_completed_v1.final_soc_pct,
      energy_kwh      => E#charging_completed_v1.energy_kwh,
      charge_cycle    => E#charging_completed_v1.charge_cycle,
      battery_soh_pct => E#charging_completed_v1.battery_soh_pct,
      completed_at    => E#charging_completed_v1.completed_at}.

get_session_id(#charging_completed_v1{session_id = V})           -> V.
get_vehicle_id(#charging_completed_v1{vehicle_id = V})           -> V.
get_final_soc_pct(#charging_completed_v1{final_soc_pct = V})     -> V.
get_energy_kwh(#charging_completed_v1{energy_kwh = V})           -> V.
get_charge_cycle(#charging_completed_v1{charge_cycle = V})       -> V.
get_battery_soh_pct(#charging_completed_v1{battery_soh_pct = V}) -> V.
get_completed_at(#charging_completed_v1{completed_at = V})       -> V.
