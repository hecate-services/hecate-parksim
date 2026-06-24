%%% @doc Event `vehicle_serviced_v1`. A service (charge|clean|maintain) was
%%% performed on the docked vehicle. For a charge, `battery_pct` is the
%%% restored level.
-module(vehicle_serviced_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1,
         get_service_kind/1, get_battery_pct/1, get_serviced_at/1]).

-record(vehicle_serviced_v1, {
    vehicle_id   :: binary() | undefined,
    company_id   :: binary() | undefined,
    service_kind :: binary() | undefined,
    battery_pct  :: number() | undefined,
    serviced_at  :: binary() | undefined
}).

-opaque t() :: #vehicle_serviced_v1{}.
-export_type([t/0]).

event_type() -> vehicle_serviced_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_serviced_v1{
        vehicle_id   = Id,
        company_id   = maps:get(company_id, P, undefined),
        service_kind = maps:get(service_kind, P, undefined),
        battery_pct  = maps:get(battery_pct, P, undefined),
        serviced_at  = maps:get(serviced_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_serviced_v1{
        vehicle_id   = Id,
        company_id   = maps:get(<<"company_id">>, M, undefined),
        service_kind = maps:get(<<"service_kind">>, M, undefined),
        battery_pct  = maps:get(<<"battery_pct">>, M, undefined),
        serviced_at  = maps:get(<<"serviced_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_serviced_v1{
        vehicle_id   = Id,
        company_id   = maps:get(company_id, M, undefined),
        service_kind = maps:get(service_kind, M, undefined),
        battery_pct  = maps:get(battery_pct, M, undefined),
        serviced_at  = maps:get(serviced_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_serviced_v1{} = E) ->
    #{event_type   => <<"vehicle_serviced">>,
      vehicle_id   => E#vehicle_serviced_v1.vehicle_id,
      company_id   => E#vehicle_serviced_v1.company_id,
      service_kind => E#vehicle_serviced_v1.service_kind,
      battery_pct  => E#vehicle_serviced_v1.battery_pct,
      serviced_at  => E#vehicle_serviced_v1.serviced_at}.

get_vehicle_id(#vehicle_serviced_v1{vehicle_id = V})     -> V.
get_company_id(#vehicle_serviced_v1{company_id = V})     -> V.
get_service_kind(#vehicle_serviced_v1{service_kind = V}) -> V.
get_battery_pct(#vehicle_serviced_v1{battery_pct = V})   -> V.
get_serviced_at(#vehicle_serviced_v1{serviced_at = V})   -> V.
