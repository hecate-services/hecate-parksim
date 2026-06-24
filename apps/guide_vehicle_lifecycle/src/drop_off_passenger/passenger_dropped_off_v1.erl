%%% @doc Event `passenger_dropped_off_v1`. Trip complete; the vehicle
%%% returns to the cruising pool.
-module(passenger_dropped_off_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_ride_id/1,
         get_x/1, get_y/1, get_dropped_off_at/1]).

-record(passenger_dropped_off_v1, {
    vehicle_id     :: binary() | undefined,
    company_id     :: binary() | undefined,
    ride_id        :: binary() | undefined,
    x            :: number() | undefined,
    y            :: number() | undefined,
    dropped_off_at :: binary() | undefined
}).

-opaque t() :: #passenger_dropped_off_v1{}.
-export_type([t/0]).

event_type() -> passenger_dropped_off_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #passenger_dropped_off_v1{
        vehicle_id     = Id,
        company_id     = maps:get(company_id, P, undefined),
        ride_id        = maps:get(ride_id, P, undefined),
        x            = maps:get(x, P, undefined),
        y            = maps:get(y, P, undefined),
        dropped_off_at = maps:get(dropped_off_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #passenger_dropped_off_v1{
        vehicle_id     = Id,
        company_id     = maps:get(<<"company_id">>, M, undefined),
        ride_id        = maps:get(<<"ride_id">>, M, undefined),
        x            = maps:get(<<"x">>, M, undefined),
        y            = maps:get(<<"y">>, M, undefined),
        dropped_off_at = maps:get(<<"dropped_off_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #passenger_dropped_off_v1{
        vehicle_id     = Id,
        company_id     = maps:get(company_id, M, undefined),
        ride_id        = maps:get(ride_id, M, undefined),
        x            = maps:get(x, M, undefined),
        y            = maps:get(y, M, undefined),
        dropped_off_at = maps:get(dropped_off_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#passenger_dropped_off_v1{} = E) ->
    #{event_type     => <<"passenger_dropped_off">>,
      vehicle_id     => E#passenger_dropped_off_v1.vehicle_id,
      company_id     => E#passenger_dropped_off_v1.company_id,
      ride_id        => E#passenger_dropped_off_v1.ride_id,
      x            => E#passenger_dropped_off_v1.x,
      y            => E#passenger_dropped_off_v1.y,
      dropped_off_at => E#passenger_dropped_off_v1.dropped_off_at}.

get_vehicle_id(#passenger_dropped_off_v1{vehicle_id = V})         -> V.
get_company_id(#passenger_dropped_off_v1{company_id = V})         -> V.
get_ride_id(#passenger_dropped_off_v1{ride_id = V})               -> V.
get_x(#passenger_dropped_off_v1{x = V})                       -> V.
get_y(#passenger_dropped_off_v1{y = V})                       -> V.
get_dropped_off_at(#passenger_dropped_off_v1{dropped_off_at = V}) -> V.
