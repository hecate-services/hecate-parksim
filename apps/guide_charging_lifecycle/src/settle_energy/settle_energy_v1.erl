%%% @doc Command `settle_energy_v1`. Books the finished session's energy cost
%%% (kWh x tariff) to the operator ledger. Tariff/energy default from the
%%% session state when the caller omits them.
-module(settle_energy_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_vehicle_id/1, get_company_id/1,
         get_energy_kwh/1, get_tariff_cents_per_kwh/1, get_settled_at/1]).

-record(settle_energy_v1, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,
    energy_kwh           :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,
    settled_at           :: binary() | undefined
}).

-opaque t() :: #settle_energy_v1{}.
-export_type([t/0]).

command_type() -> settle_energy_v1.

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
    #settle_energy_v1{
        session_id           = Id,
        vehicle_id           = G(vehicle_id, undefined),
        company_id           = G(company_id, undefined),
        energy_kwh           = G(energy_kwh, undefined),
        tariff_cents_per_kwh = G(tariff_cents_per_kwh, undefined),
        settled_at           = G(settled_at, undefined)
    }.

-spec validate(t()) -> ok | {error, term()}.
validate(#settle_energy_v1{session_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#settle_energy_v1{} = C) ->
    #{command_type         => <<"settle_energy">>,
      session_id           => C#settle_energy_v1.session_id,
      vehicle_id           => C#settle_energy_v1.vehicle_id,
      company_id           => C#settle_energy_v1.company_id,
      energy_kwh           => C#settle_energy_v1.energy_kwh,
      tariff_cents_per_kwh => C#settle_energy_v1.tariff_cents_per_kwh,
      settled_at           => C#settle_energy_v1.settled_at}.

-spec stream_id(t()) -> binary().
stream_id(#settle_energy_v1{session_id = Id}) -> charging_aggregate:stream_id(Id).

get_session_id(#settle_energy_v1{session_id = V})                     -> V.
get_vehicle_id(#settle_energy_v1{vehicle_id = V})                     -> V.
get_company_id(#settle_energy_v1{company_id = V})                     -> V.
get_energy_kwh(#settle_energy_v1{energy_kwh = V})                     -> V.
get_tariff_cents_per_kwh(#settle_energy_v1{tariff_cents_per_kwh = V}) -> V.
get_settled_at(#settle_energy_v1{settled_at = V})                     -> V.
