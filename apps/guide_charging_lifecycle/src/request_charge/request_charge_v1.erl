%%% @doc Command `request_charge_v1`. Birth slip — a vehicle's SoC dropped below
%%% the charge threshold and a charging session is asked for. Carries the tariff
%%% snapshot (grid price) that the scheduler acted on, so the whole session is
%%% attributable to a price signal.
-module(request_charge_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_vehicle_id/1, get_company_id/1, get_plate/1,
         get_battery_pct_before/1, get_target_pct/1,
         get_tariff_cents_per_kwh/1, get_requested_at/1]).

-record(request_charge_v1, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,
    plate                :: binary() | undefined,
    battery_pct_before   :: number() | undefined,
    target_pct           :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,
    requested_at         :: binary() | undefined
}).

-opaque t() :: #request_charge_v1{}.
-export_type([t/0]).

command_type() -> request_charge_v1.

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
    #request_charge_v1{
        session_id           = Id,
        vehicle_id           = G(vehicle_id, undefined),
        company_id           = G(company_id, undefined),
        plate                = G(plate, undefined),
        battery_pct_before   = G(battery_pct_before, undefined),
        target_pct           = G(target_pct, 100),
        tariff_cents_per_kwh = G(tariff_cents_per_kwh, undefined),
        requested_at         = G(requested_at, undefined)
    }.

-spec validate(t()) -> ok | {error, term()}.
validate(#request_charge_v1{session_id = undefined}) -> {error, missing_aggregate_id};
validate(#request_charge_v1{vehicle_id = undefined}) -> {error, missing_vehicle_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#request_charge_v1{} = C) ->
    #{command_type         => <<"request_charge">>,
      session_id           => C#request_charge_v1.session_id,
      vehicle_id           => C#request_charge_v1.vehicle_id,
      company_id           => C#request_charge_v1.company_id,
      plate                => C#request_charge_v1.plate,
      battery_pct_before   => C#request_charge_v1.battery_pct_before,
      target_pct           => C#request_charge_v1.target_pct,
      tariff_cents_per_kwh => C#request_charge_v1.tariff_cents_per_kwh,
      requested_at         => C#request_charge_v1.requested_at}.

-spec stream_id(t()) -> binary().
stream_id(#request_charge_v1{session_id = Id}) -> charging_aggregate:stream_id(Id).

get_session_id(#request_charge_v1{session_id = V})                     -> V.
get_vehicle_id(#request_charge_v1{vehicle_id = V})                     -> V.
get_company_id(#request_charge_v1{company_id = V})                     -> V.
get_plate(#request_charge_v1{plate = V})                               -> V.
get_battery_pct_before(#request_charge_v1{battery_pct_before = V})     -> V.
get_target_pct(#request_charge_v1{target_pct = V})                     -> V.
get_tariff_cents_per_kwh(#request_charge_v1{tariff_cents_per_kwh = V}) -> V.
get_requested_at(#request_charge_v1{requested_at = V})                 -> V.
