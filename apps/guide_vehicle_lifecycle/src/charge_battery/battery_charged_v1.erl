%%% @doc Event `battery_charged_v1`. A docked vehicle's battery was topped
%%% up. `battery_pct` is the restored level (default 100). The natural
%%% complement to `battery_depleted_v1`.
-module(battery_charged_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_battery_pct/1, get_battery_pct_before/1, get_energy_kwh/1, get_charging_cents/1, get_charged_at/1]).

-record(battery_charged_v1, {
    vehicle_id  :: binary() | undefined,
    charge_cycle       :: non_neg_integer() | undefined,
    battery_soh_pct       :: number() | undefined,
    plate       :: binary() | undefined,
    company_id  :: binary() | undefined,
    battery_pct :: number() | undefined,
    battery_pct_before :: number() | undefined,
    energy_kwh :: number() | undefined,
    charging_cents :: non_neg_integer() | undefined,
    charged_at  :: binary() | undefined
}).

-opaque t() :: #battery_charged_v1{}.
-export_type([t/0]).

event_type() -> battery_charged_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #battery_charged_v1{
        vehicle_id  = Id,
        charge_cycle       = maps:get(charge_cycle, P, undefined),
        battery_soh_pct       = maps:get(battery_soh_pct, P, undefined),
        plate       = maps:get(plate, P, undefined),
        company_id  = maps:get(company_id, P, undefined),
        battery_pct = maps:get(battery_pct, P, undefined),
        battery_pct_before = maps:get(battery_pct_before, P, undefined),
        energy_kwh = maps:get(energy_kwh, P, undefined),
        charging_cents = maps:get(charging_cents, P, undefined),
        charged_at  = maps:get(charged_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #battery_charged_v1{
        vehicle_id  = Id,
        charge_cycle       = maps:get(<<"charge_cycle">>, M, undefined),
        battery_soh_pct       = maps:get(<<"battery_soh_pct">>, M, undefined),
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id  = maps:get(<<"company_id">>, M, undefined),
        battery_pct = maps:get(<<"battery_pct">>, M, undefined),
        battery_pct_before = maps:get(<<"battery_pct_before">>, M, undefined),
        energy_kwh = maps:get(<<"energy_kwh">>, M, undefined),
        charging_cents = maps:get(<<"charging_cents">>, M, undefined),
        charged_at  = maps:get(<<"charged_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #battery_charged_v1{
        vehicle_id  = Id,
        charge_cycle       = maps:get(charge_cycle, M, undefined),
        battery_soh_pct       = maps:get(battery_soh_pct, M, undefined),
        plate       = maps:get(plate, M, undefined),
        company_id  = maps:get(company_id, M, undefined),
        battery_pct = maps:get(battery_pct, M, undefined),
        battery_pct_before = maps:get(battery_pct_before, M, undefined),
        energy_kwh = maps:get(energy_kwh, M, undefined),
        charging_cents = maps:get(charging_cents, M, undefined),
        charged_at  = maps:get(charged_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#battery_charged_v1{} = E) ->
    #{event_type  => <<"battery_charged">>,
      vehicle_id  => E#battery_charged_v1.vehicle_id,
      charge_cycle  => E#battery_charged_v1.charge_cycle,
      battery_soh_pct  => E#battery_charged_v1.battery_soh_pct,
      plate  => E#battery_charged_v1.plate,
      company_id  => E#battery_charged_v1.company_id,
      battery_pct => E#battery_charged_v1.battery_pct,
      battery_pct_before => E#battery_charged_v1.battery_pct_before,
      energy_kwh => E#battery_charged_v1.energy_kwh,
      charging_cents => E#battery_charged_v1.charging_cents,
      charged_at  => E#battery_charged_v1.charged_at}.

get_vehicle_id(#battery_charged_v1{vehicle_id = V})   -> V.
get_company_id(#battery_charged_v1{company_id = V})   -> V.
get_battery_pct(#battery_charged_v1{battery_pct = V}) -> V.
get_battery_pct_before(#battery_charged_v1{battery_pct_before = V}) -> V.
get_energy_kwh(#battery_charged_v1{energy_kwh = V}) -> V.
get_charging_cents(#battery_charged_v1{charging_cents = V}) -> V.
get_charged_at(#battery_charged_v1{charged_at = V})   -> V.
