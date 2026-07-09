%%% @doc Event `charge_requested_v1`. A vehicle's SoC dropped below threshold and
%%% a charging session was requested; the charging dossier is born.
-module(charge_requested_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_vehicle_id/1, get_company_id/1, get_plate/1,
         get_battery_pct_before/1, get_target_pct/1,
         get_tariff_cents_per_kwh/1, get_requested_at/1]).

-record(charge_requested_v1, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,
    plate                :: binary() | undefined,
    battery_pct_before   :: number() | undefined,
    target_pct           :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,
    requested_at         :: binary() | undefined
}).

-opaque t() :: #charge_requested_v1{}.
-export_type([t/0]).

event_type() -> charge_requested_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{session_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)}.

from(G, Id) ->
    #charge_requested_v1{
        session_id           = Id,
        vehicle_id           = G(vehicle_id, undefined),
        company_id           = G(company_id, undefined),
        plate                = G(plate, undefined),
        battery_pct_before   = G(battery_pct_before, undefined),
        target_pct           = G(target_pct, 100),
        tariff_cents_per_kwh = G(tariff_cents_per_kwh, undefined),
        requested_at         = G(requested_at, undefined)
    }.

-spec to_map(t()) -> map().
to_map(#charge_requested_v1{} = E) ->
    #{event_type           => <<"charge_requested">>,
      session_id           => E#charge_requested_v1.session_id,
      vehicle_id           => E#charge_requested_v1.vehicle_id,
      company_id           => E#charge_requested_v1.company_id,
      plate                => E#charge_requested_v1.plate,
      battery_pct_before   => E#charge_requested_v1.battery_pct_before,
      target_pct           => E#charge_requested_v1.target_pct,
      tariff_cents_per_kwh => E#charge_requested_v1.tariff_cents_per_kwh,
      requested_at         => E#charge_requested_v1.requested_at}.

get_session_id(#charge_requested_v1{session_id = V})                     -> V.
get_vehicle_id(#charge_requested_v1{vehicle_id = V})                     -> V.
get_company_id(#charge_requested_v1{company_id = V})                     -> V.
get_plate(#charge_requested_v1{plate = V})                               -> V.
get_battery_pct_before(#charge_requested_v1{battery_pct_before = V})     -> V.
get_target_pct(#charge_requested_v1{target_pct = V})                     -> V.
get_tariff_cents_per_kwh(#charge_requested_v1{tariff_cents_per_kwh = V}) -> V.
get_requested_at(#charge_requested_v1{requested_at = V})                 -> V.
