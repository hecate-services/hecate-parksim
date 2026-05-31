%%% @doc Command `dispatch_vehicle_v1`. Assign an available vehicle a fare
%%% (pickup -> dropoff). The vehicle heads to the pickup point.
-module(dispatch_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_trip_id/1, get_pickup_x/1, get_pickup_y/1,
         get_dropoff_x/1, get_dropoff_y/1, get_dispatched_at/1]).

-record(dispatch_vehicle_v1, {
    vehicle_id    :: binary() | undefined,
    trip_id       :: binary() | undefined,
    pickup_x    :: number() | undefined,
    pickup_y    :: number() | undefined,
    dropoff_x   :: number() | undefined,
    dropoff_y   :: number() | undefined,
    dispatched_at :: binary() | undefined
}).

-opaque t() :: #dispatch_vehicle_v1{}.
-export_type([t/0]).

command_type() -> dispatch_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #dispatch_vehicle_v1{
        vehicle_id    = Id,
        trip_id       = maps:get(trip_id, P, undefined),
        pickup_x    = maps:get(pickup_x, P, undefined),
        pickup_y    = maps:get(pickup_y, P, undefined),
        dropoff_x   = maps:get(dropoff_x, P, undefined),
        dropoff_y   = maps:get(dropoff_y, P, undefined),
        dispatched_at = maps:get(dispatched_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #dispatch_vehicle_v1{
        vehicle_id    = Id,
        trip_id       = maps:get(<<"trip_id">>, M, undefined),
        pickup_x    = maps:get(<<"pickup_x">>, M, undefined),
        pickup_y    = maps:get(<<"pickup_y">>, M, undefined),
        dropoff_x   = maps:get(<<"dropoff_x">>, M, undefined),
        dropoff_y   = maps:get(<<"dropoff_y">>, M, undefined),
        dispatched_at = maps:get(<<"dispatched_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #dispatch_vehicle_v1{
        vehicle_id    = Id,
        trip_id       = maps:get(trip_id, M, undefined),
        pickup_x    = maps:get(pickup_x, M, undefined),
        pickup_y    = maps:get(pickup_y, M, undefined),
        dropoff_x   = maps:get(dropoff_x, M, undefined),
        dropoff_y   = maps:get(dropoff_y, M, undefined),
        dispatched_at = maps:get(dispatched_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#dispatch_vehicle_v1{vehicle_id = undefined})  -> {error, missing_aggregate_id};
validate(#dispatch_vehicle_v1{trip_id = undefined})     -> {error, missing_trip_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#dispatch_vehicle_v1{} = C) ->
    #{command_type  => <<"dispatch_vehicle">>,
      vehicle_id    => C#dispatch_vehicle_v1.vehicle_id,
      trip_id       => C#dispatch_vehicle_v1.trip_id,
      pickup_x    => C#dispatch_vehicle_v1.pickup_x,
      pickup_y    => C#dispatch_vehicle_v1.pickup_y,
      dropoff_x   => C#dispatch_vehicle_v1.dropoff_x,
      dropoff_y   => C#dispatch_vehicle_v1.dropoff_y,
      dispatched_at => C#dispatch_vehicle_v1.dispatched_at}.

-spec stream_id(t()) -> binary().
stream_id(#dispatch_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#dispatch_vehicle_v1{vehicle_id = V})       -> V.
get_trip_id(#dispatch_vehicle_v1{trip_id = V})             -> V.
get_pickup_x(#dispatch_vehicle_v1{pickup_x = V})       -> V.
get_pickup_y(#dispatch_vehicle_v1{pickup_y = V})       -> V.
get_dropoff_x(#dispatch_vehicle_v1{dropoff_x = V})     -> V.
get_dropoff_y(#dispatch_vehicle_v1{dropoff_y = V})     -> V.
get_dispatched_at(#dispatch_vehicle_v1{dispatched_at = V}) -> V.
