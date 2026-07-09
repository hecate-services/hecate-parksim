%%% @doc Command `complete_charging_v1`. Target SoC reached / unplugged. Carries
%%% the final SoC, total energy drawn, and the battery wear this cycle inflicted
%%% (charge_cycle + battery_soh_pct — the asset ages visibly).
-module(complete_charging_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_vehicle_id/1, get_final_soc_pct/1,
         get_energy_kwh/1, get_charge_cycle/1, get_battery_soh_pct/1,
         get_completed_at/1]).

-record(complete_charging_v1, {
    session_id      :: binary() | undefined,
    vehicle_id      :: binary() | undefined,
    final_soc_pct   :: number() | undefined,
    energy_kwh      :: number() | undefined,
    charge_cycle    :: non_neg_integer() | undefined,
    battery_soh_pct :: number() | undefined,
    completed_at    :: binary() | undefined
}).

-opaque t() :: #complete_charging_v1{}.
-export_type([t/0]).

command_type() -> complete_charging_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{session_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"session_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{session_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)};
from_map(_) ->
    {error, missing_aggregate_id}.

from(G, Id) ->
    #complete_charging_v1{
        session_id      = Id,
        vehicle_id      = G(vehicle_id, undefined),
        final_soc_pct   = G(final_soc_pct, 100),
        energy_kwh      = G(energy_kwh, undefined),
        charge_cycle    = G(charge_cycle, undefined),
        battery_soh_pct = G(battery_soh_pct, undefined),
        completed_at    = G(completed_at, undefined)
    }.

-spec validate(t()) -> ok | {error, term()}.
validate(#complete_charging_v1{session_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#complete_charging_v1{} = C) ->
    #{command_type    => <<"complete_charging">>,
      session_id      => C#complete_charging_v1.session_id,
      vehicle_id      => C#complete_charging_v1.vehicle_id,
      final_soc_pct   => C#complete_charging_v1.final_soc_pct,
      energy_kwh      => C#complete_charging_v1.energy_kwh,
      charge_cycle    => C#complete_charging_v1.charge_cycle,
      battery_soh_pct => C#complete_charging_v1.battery_soh_pct,
      completed_at    => C#complete_charging_v1.completed_at}.

-spec stream_id(t()) -> binary().
stream_id(#complete_charging_v1{session_id = Id}) -> charging_aggregate:stream_id(Id).

get_session_id(#complete_charging_v1{session_id = V})           -> V.
get_vehicle_id(#complete_charging_v1{vehicle_id = V})           -> V.
get_final_soc_pct(#complete_charging_v1{final_soc_pct = V})     -> V.
get_energy_kwh(#complete_charging_v1{energy_kwh = V})           -> V.
get_charge_cycle(#complete_charging_v1{charge_cycle = V})       -> V.
get_battery_soh_pct(#complete_charging_v1{battery_soh_pct = V}) -> V.
get_completed_at(#complete_charging_v1{completed_at = V})       -> V.
