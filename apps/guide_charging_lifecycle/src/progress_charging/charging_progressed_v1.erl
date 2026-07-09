%%% @doc Event `charging_progressed_v1`. One SoC milestone crossed during a
%%% session — the dense signal that makes charging a real high-frequency stream.
-module(charging_progressed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_vehicle_id/1, get_soc_pct/1,
         get_energy_kwh_delta/1, get_energy_kwh_total/1, get_progressed_at/1]).

-record(charging_progressed_v1, {
    session_id       :: binary() | undefined,
    vehicle_id       :: binary() | undefined,
    soc_pct          :: number() | undefined,
    energy_kwh_delta :: number() | undefined,
    energy_kwh_total :: number() | undefined,
    progressed_at    :: binary() | undefined
}).

-opaque t() :: #charging_progressed_v1{}.
-export_type([t/0]).

event_type() -> charging_progressed_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{session_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)}.

from(G, Id) ->
    #charging_progressed_v1{
        session_id       = Id,
        vehicle_id       = G(vehicle_id, undefined),
        soc_pct          = G(soc_pct, undefined),
        energy_kwh_delta = G(energy_kwh_delta, undefined),
        energy_kwh_total = G(energy_kwh_total, undefined),
        progressed_at    = G(progressed_at, undefined)
    }.

-spec to_map(t()) -> map().
to_map(#charging_progressed_v1{} = E) ->
    #{event_type       => <<"charging_progressed">>,
      session_id       => E#charging_progressed_v1.session_id,
      vehicle_id       => E#charging_progressed_v1.vehicle_id,
      soc_pct          => E#charging_progressed_v1.soc_pct,
      energy_kwh_delta => E#charging_progressed_v1.energy_kwh_delta,
      energy_kwh_total => E#charging_progressed_v1.energy_kwh_total,
      progressed_at    => E#charging_progressed_v1.progressed_at}.

get_session_id(#charging_progressed_v1{session_id = V})             -> V.
get_vehicle_id(#charging_progressed_v1{vehicle_id = V})             -> V.
get_soc_pct(#charging_progressed_v1{soc_pct = V})                   -> V.
get_energy_kwh_delta(#charging_progressed_v1{energy_kwh_delta = V}) -> V.
get_energy_kwh_total(#charging_progressed_v1{energy_kwh_total = V}) -> V.
get_progressed_at(#charging_progressed_v1{progressed_at = V})       -> V.
