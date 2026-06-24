%%% @doc Event `ride_started_v1`. Passenger aboard, en route to dropoff.
-module(ride_started_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_vehicle_id/1, get_started_at/1]).

-record(ride_started_v1, {
    ride_id    :: binary() | undefined,
    vehicle_id :: binary() | undefined,
    started_at :: binary() | undefined
}).

-opaque t() :: #ride_started_v1{}.
-export_type([t/0]).

event_type() -> ride_started_v1.

-spec new(map()) -> {ok, t()}.
new(#{ride_id := Id} = P) ->
    {ok, #ride_started_v1{
        ride_id    = Id,
        vehicle_id = maps:get(vehicle_id, P, undefined),
        started_at = maps:get(started_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #ride_started_v1{
        ride_id    = Id,
        vehicle_id = maps:get(<<"vehicle_id">>, M, undefined),
        started_at = maps:get(<<"started_at">>, M, undefined)
    }};
from_map(#{ride_id := Id} = M) ->
    {ok, #ride_started_v1{
        ride_id    = Id,
        vehicle_id = maps:get(vehicle_id, M, undefined),
        started_at = maps:get(started_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#ride_started_v1{} = E) ->
    #{event_type => <<"ride_started">>,
      ride_id    => E#ride_started_v1.ride_id,
      vehicle_id => E#ride_started_v1.vehicle_id,
      started_at => E#ride_started_v1.started_at}.

get_ride_id(#ride_started_v1{ride_id = V})       -> V.
get_vehicle_id(#ride_started_v1{vehicle_id = V}) -> V.
get_started_at(#ride_started_v1{started_at = V}) -> V.
