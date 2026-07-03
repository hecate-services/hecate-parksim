%%% @doc Event `vehicle_released_v1`. Bay freed; the vehicle is back on the
%%% market (cruising).
-module(vehicle_released_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_facility_id/1, get_bay_id/1, get_released_at/1]).

-record(vehicle_released_v1, {
    vehicle_id  :: binary() | undefined,
    company_id  :: binary() | undefined,
    facility_id :: binary() | undefined,
    bay_id      :: binary() | undefined,
    released_at :: binary() | undefined
}).

-opaque t() :: #vehicle_released_v1{}.
-export_type([t/0]).

event_type() -> vehicle_released_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_released_v1{
        vehicle_id  = Id,
        company_id  = maps:get(company_id, P, undefined),
        facility_id = maps:get(facility_id, P, undefined),
        bay_id      = maps:get(bay_id, P, undefined),
        released_at = maps:get(released_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_released_v1{
        vehicle_id  = Id,
        company_id  = maps:get(<<"company_id">>, M, undefined),
        facility_id = maps:get(<<"facility_id">>, M, undefined),
        bay_id      = maps:get(<<"bay_id">>, M, undefined),
        released_at = maps:get(<<"released_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_released_v1{
        vehicle_id  = Id,
        company_id  = maps:get(company_id, M, undefined),
        facility_id = maps:get(facility_id, M, undefined),
        bay_id      = maps:get(bay_id, M, undefined),
        released_at = maps:get(released_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_released_v1{} = E) ->
    #{event_type   => <<"vehicle_released">>,
      vehicle_id   => E#vehicle_released_v1.vehicle_id,
      company_id   => E#vehicle_released_v1.company_id,
      facility_id  => E#vehicle_released_v1.facility_id,
      bay_id       => E#vehicle_released_v1.bay_id,
      released_at  => E#vehicle_released_v1.released_at}.

get_vehicle_id(#vehicle_released_v1{vehicle_id = V})   -> V.
get_company_id(#vehicle_released_v1{company_id = V})   -> V.
get_facility_id(#vehicle_released_v1{facility_id = V}) -> V.
get_bay_id(#vehicle_released_v1{bay_id = V})           -> V.
get_released_at(#vehicle_released_v1{released_at = V}) -> V.
