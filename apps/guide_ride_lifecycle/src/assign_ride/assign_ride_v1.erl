%%% @doc Command `assign_ride_v1`. A cab has been assigned to a waiting ride.
-module(assign_ride_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_ride_id/1, get_vehicle_id/1, get_assigned_at/1]).

-record(assign_ride_v1, {
    ride_id     :: binary() | undefined,
    vehicle_id  :: binary() | undefined,
    assigned_at :: binary() | undefined
}).

-opaque t() :: #assign_ride_v1{}.
-export_type([t/0]).

command_type() -> assign_ride_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{ride_id := Id} = P) ->
    {ok, #assign_ride_v1{ride_id = Id,
                         vehicle_id = maps:get(vehicle_id, P, undefined),
                         assigned_at = maps:get(assigned_at, P, undefined)}};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #assign_ride_v1{ride_id = Id,
                         vehicle_id = maps:get(<<"vehicle_id">>, M, undefined),
                         assigned_at = maps:get(<<"assigned_at">>, M, undefined)}};
from_map(#{ride_id := Id} = M) ->
    {ok, #assign_ride_v1{ride_id = Id,
                         vehicle_id = maps:get(vehicle_id, M, undefined),
                         assigned_at = maps:get(assigned_at, M, undefined)}};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#assign_ride_v1{ride_id = undefined})    -> {error, missing_aggregate_id};
validate(#assign_ride_v1{vehicle_id = undefined}) -> {error, missing_vehicle_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#assign_ride_v1{} = C) ->
    #{command_type => <<"assign_ride">>,
      ride_id      => C#assign_ride_v1.ride_id,
      vehicle_id   => C#assign_ride_v1.vehicle_id,
      assigned_at  => C#assign_ride_v1.assigned_at}.

-spec stream_id(t()) -> binary().
stream_id(#assign_ride_v1{ride_id = Id}) -> <<"ride-", Id/binary>>.

get_ride_id(#assign_ride_v1{ride_id = V})         -> V.
get_vehicle_id(#assign_ride_v1{vehicle_id = V})   -> V.
get_assigned_at(#assign_ride_v1{assigned_at = V}) -> V.
