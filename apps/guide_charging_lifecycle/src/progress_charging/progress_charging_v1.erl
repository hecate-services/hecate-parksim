%%% @doc Command `progress_charging_v1`. A per-SoC-milestone tick while the
%%% vehicle charges (e.g. 40% -> 60% -> 80%). This is the density: one dense
%%% stream per session, unlike the sparse ride milestones.
-module(progress_charging_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_vehicle_id/1, get_soc_pct/1,
         get_energy_kwh_delta/1, get_energy_kwh_total/1, get_progressed_at/1]).

-record(progress_charging_v1, {
    session_id       :: binary() | undefined,
    vehicle_id       :: binary() | undefined,
    soc_pct          :: number() | undefined,
    energy_kwh_delta :: number() | undefined,
    energy_kwh_total :: number() | undefined,
    progressed_at    :: binary() | undefined
}).

-opaque t() :: #progress_charging_v1{}.
-export_type([t/0]).

command_type() -> progress_charging_v1.

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
    #progress_charging_v1{
        session_id       = Id,
        vehicle_id       = G(vehicle_id, undefined),
        soc_pct          = G(soc_pct, undefined),
        energy_kwh_delta = G(energy_kwh_delta, undefined),
        energy_kwh_total = G(energy_kwh_total, undefined),
        progressed_at    = G(progressed_at, undefined)
    }.

-spec validate(t()) -> ok | {error, term()}.
validate(#progress_charging_v1{session_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#progress_charging_v1{} = C) ->
    #{command_type     => <<"progress_charging">>,
      session_id       => C#progress_charging_v1.session_id,
      vehicle_id       => C#progress_charging_v1.vehicle_id,
      soc_pct          => C#progress_charging_v1.soc_pct,
      energy_kwh_delta => C#progress_charging_v1.energy_kwh_delta,
      energy_kwh_total => C#progress_charging_v1.energy_kwh_total,
      progressed_at    => C#progress_charging_v1.progressed_at}.

-spec stream_id(t()) -> binary().
stream_id(#progress_charging_v1{session_id = Id}) -> charging_aggregate:stream_id(Id).

get_session_id(#progress_charging_v1{session_id = V})             -> V.
get_vehicle_id(#progress_charging_v1{vehicle_id = V})             -> V.
get_soc_pct(#progress_charging_v1{soc_pct = V})                   -> V.
get_energy_kwh_delta(#progress_charging_v1{energy_kwh_delta = V}) -> V.
get_energy_kwh_total(#progress_charging_v1{energy_kwh_total = V}) -> V.
get_progressed_at(#progress_charging_v1{progressed_at = V})       -> V.
