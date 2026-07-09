%%% @doc Event `charging_started_v1`. The vehicle is plugged in and drawing
%%% power; the tariff stamped here (grid price at plug-in) prices the session.
-module(charging_started_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_vehicle_id/1, get_company_id/1, get_charger_id/1,
         get_battery_pct_before/1, get_tariff_cents_per_kwh/1, get_started_at/1]).

-record(charging_started_v1, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,
    charger_id           :: binary() | undefined,
    battery_pct_before   :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,
    started_at           :: binary() | undefined
}).

-opaque t() :: #charging_started_v1{}.
-export_type([t/0]).

event_type() -> charging_started_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{session_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)}.

from(G, Id) ->
    #charging_started_v1{
        session_id           = Id,
        vehicle_id           = G(vehicle_id, undefined),
        company_id           = G(company_id, undefined),
        charger_id           = G(charger_id, undefined),
        battery_pct_before   = G(battery_pct_before, undefined),
        tariff_cents_per_kwh = G(tariff_cents_per_kwh, undefined),
        started_at           = G(started_at, undefined)
    }.

-spec to_map(t()) -> map().
to_map(#charging_started_v1{} = E) ->
    #{event_type           => <<"charging_started">>,
      session_id           => E#charging_started_v1.session_id,
      vehicle_id           => E#charging_started_v1.vehicle_id,
      company_id           => E#charging_started_v1.company_id,
      charger_id           => E#charging_started_v1.charger_id,
      battery_pct_before   => E#charging_started_v1.battery_pct_before,
      tariff_cents_per_kwh => E#charging_started_v1.tariff_cents_per_kwh,
      started_at           => E#charging_started_v1.started_at}.

get_session_id(#charging_started_v1{session_id = V})                     -> V.
get_vehicle_id(#charging_started_v1{vehicle_id = V})                     -> V.
get_company_id(#charging_started_v1{company_id = V})                     -> V.
get_charger_id(#charging_started_v1{charger_id = V})                     -> V.
get_battery_pct_before(#charging_started_v1{battery_pct_before = V})     -> V.
get_tariff_cents_per_kwh(#charging_started_v1{tariff_cents_per_kwh = V}) -> V.
get_started_at(#charging_started_v1{started_at = V})                     -> V.
