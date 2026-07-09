%%% @doc Command `start_charging_v1`. The vehicle is plugged in at a charger;
%%% the operative tariff (grid price at plug-in) is stamped on the session.
-module(start_charging_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_vehicle_id/1, get_company_id/1, get_charger_id/1,
         get_battery_pct_before/1, get_tariff_cents_per_kwh/1, get_started_at/1]).

-record(start_charging_v1, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,
    charger_id           :: binary() | undefined,
    battery_pct_before   :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,
    started_at           :: binary() | undefined
}).

-opaque t() :: #start_charging_v1{}.
-export_type([t/0]).

command_type() -> start_charging_v1.

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
    #start_charging_v1{
        session_id           = Id,
        vehicle_id           = G(vehicle_id, undefined),
        company_id           = G(company_id, undefined),
        charger_id           = G(charger_id, undefined),
        battery_pct_before   = G(battery_pct_before, undefined),
        tariff_cents_per_kwh = G(tariff_cents_per_kwh, undefined),
        started_at           = G(started_at, undefined)
    }.

-spec validate(t()) -> ok | {error, term()}.
validate(#start_charging_v1{session_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#start_charging_v1{} = C) ->
    #{command_type         => <<"start_charging">>,
      session_id           => C#start_charging_v1.session_id,
      vehicle_id           => C#start_charging_v1.vehicle_id,
      company_id           => C#start_charging_v1.company_id,
      charger_id           => C#start_charging_v1.charger_id,
      battery_pct_before   => C#start_charging_v1.battery_pct_before,
      tariff_cents_per_kwh => C#start_charging_v1.tariff_cents_per_kwh,
      started_at           => C#start_charging_v1.started_at}.

-spec stream_id(t()) -> binary().
stream_id(#start_charging_v1{session_id = Id}) -> charging_aggregate:stream_id(Id).

get_session_id(#start_charging_v1{session_id = V})                     -> V.
get_vehicle_id(#start_charging_v1{vehicle_id = V})                     -> V.
get_company_id(#start_charging_v1{company_id = V})                     -> V.
get_charger_id(#start_charging_v1{charger_id = V})                     -> V.
get_battery_pct_before(#start_charging_v1{battery_pct_before = V})     -> V.
get_tariff_cents_per_kwh(#start_charging_v1{tariff_cents_per_kwh = V}) -> V.
get_started_at(#start_charging_v1{started_at = V})                     -> V.
