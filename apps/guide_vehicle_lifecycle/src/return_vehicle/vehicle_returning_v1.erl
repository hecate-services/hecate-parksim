%%% @doc Event `vehicle_returning_v1`. The vehicle left the revenue pool
%%% and is heading to a facility for charging/service.
-module(vehicle_returning_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_facility_id/1, get_returning_at/1]).

-record(vehicle_returning_v1, {
    vehicle_id   :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id   :: binary() | undefined,
    facility_id  :: binary() | undefined,
    returning_at :: binary() | undefined
}).

-opaque t() :: #vehicle_returning_v1{}.
-export_type([t/0]).

event_type() -> vehicle_returning_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_returning_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, P, undefined),
        company_id   = maps:get(company_id, P, undefined),
        facility_id  = maps:get(facility_id, P, undefined),
        returning_at = maps:get(returning_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_returning_v1{
        vehicle_id   = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id   = maps:get(<<"company_id">>, M, undefined),
        facility_id  = maps:get(<<"facility_id">>, M, undefined),
        returning_at = maps:get(<<"returning_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_returning_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, M, undefined),
        company_id   = maps:get(company_id, M, undefined),
        facility_id  = maps:get(facility_id, M, undefined),
        returning_at = maps:get(returning_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_returning_v1{} = E) ->
    #{event_type   => <<"vehicle_returning">>,
      vehicle_id   => E#vehicle_returning_v1.vehicle_id,
      plate   => E#vehicle_returning_v1.plate,
      company_id   => E#vehicle_returning_v1.company_id,
      facility_id  => E#vehicle_returning_v1.facility_id,
      returning_at => E#vehicle_returning_v1.returning_at}.

get_vehicle_id(#vehicle_returning_v1{vehicle_id = V})     -> V.
get_company_id(#vehicle_returning_v1{company_id = V})     -> V.
get_facility_id(#vehicle_returning_v1{facility_id = V})   -> V.
get_returning_at(#vehicle_returning_v1{returning_at = V}) -> V.
