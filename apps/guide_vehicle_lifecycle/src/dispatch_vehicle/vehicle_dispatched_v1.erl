%%% @doc Event `vehicle_dispatched_v1`. The vehicle was assigned a fare and
%%% is heading to the pickup point.
-module(vehicle_dispatched_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_trip_id/1, get_pickup_x/1, get_pickup_y/1,
         get_dropoff_x/1, get_dropoff_y/1, get_dispatched_at/1]).

-record(vehicle_dispatched_v1, {
    vehicle_id    :: binary() | undefined,
    trip_id       :: binary() | undefined,
    pickup_x    :: number() | undefined,
    pickup_y    :: number() | undefined,
    dropoff_x   :: number() | undefined,
    dropoff_y   :: number() | undefined,
    dispatched_at :: binary() | undefined
}).

-opaque t() :: #vehicle_dispatched_v1{}.
-export_type([t/0]).

event_type() -> vehicle_dispatched_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_dispatched_v1{
        vehicle_id    = Id,
        trip_id       = maps:get(trip_id, P, undefined),
        pickup_x    = maps:get(pickup_x, P, undefined),
        pickup_y    = maps:get(pickup_y, P, undefined),
        dropoff_x   = maps:get(dropoff_x, P, undefined),
        dropoff_y   = maps:get(dropoff_y, P, undefined),
        dispatched_at = maps:get(dispatched_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_dispatched_v1{
        vehicle_id    = Id,
        trip_id       = maps:get(<<"trip_id">>, M, undefined),
        pickup_x    = maps:get(<<"pickup_x">>, M, undefined),
        pickup_y    = maps:get(<<"pickup_y">>, M, undefined),
        dropoff_x   = maps:get(<<"dropoff_x">>, M, undefined),
        dropoff_y   = maps:get(<<"dropoff_y">>, M, undefined),
        dispatched_at = maps:get(<<"dispatched_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_dispatched_v1{
        vehicle_id    = Id,
        trip_id       = maps:get(trip_id, M, undefined),
        pickup_x    = maps:get(pickup_x, M, undefined),
        pickup_y    = maps:get(pickup_y, M, undefined),
        dropoff_x   = maps:get(dropoff_x, M, undefined),
        dropoff_y   = maps:get(dropoff_y, M, undefined),
        dispatched_at = maps:get(dispatched_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_dispatched_v1{} = E) ->
    #{event_type    => <<"vehicle_dispatched">>,
      vehicle_id    => E#vehicle_dispatched_v1.vehicle_id,
      trip_id       => E#vehicle_dispatched_v1.trip_id,
      pickup_x    => E#vehicle_dispatched_v1.pickup_x,
      pickup_y    => E#vehicle_dispatched_v1.pickup_y,
      dropoff_x   => E#vehicle_dispatched_v1.dropoff_x,
      dropoff_y   => E#vehicle_dispatched_v1.dropoff_y,
      dispatched_at => E#vehicle_dispatched_v1.dispatched_at}.

get_vehicle_id(#vehicle_dispatched_v1{vehicle_id = V})       -> V.
get_trip_id(#vehicle_dispatched_v1{trip_id = V})             -> V.
get_pickup_x(#vehicle_dispatched_v1{pickup_x = V})       -> V.
get_pickup_y(#vehicle_dispatched_v1{pickup_y = V})       -> V.
get_dropoff_x(#vehicle_dispatched_v1{dropoff_x = V})     -> V.
get_dropoff_y(#vehicle_dispatched_v1{dropoff_y = V})     -> V.
get_dispatched_at(#vehicle_dispatched_v1{dispatched_at = V}) -> V.
