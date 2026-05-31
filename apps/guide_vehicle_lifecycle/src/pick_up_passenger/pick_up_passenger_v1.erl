%%% @doc Command `pick_up_passenger_v1`. The vehicle reached the pickup
%%% point and the passenger boarded — the trip (and meter) begins.
-module(pick_up_passenger_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_x/1, get_y/1, get_picked_up_at/1]).

-record(pick_up_passenger_v1, {
    vehicle_id   :: binary() | undefined,
    x          :: number() | undefined,
    y          :: number() | undefined,
    picked_up_at :: binary() | undefined
}).

-opaque t() :: #pick_up_passenger_v1{}.
-export_type([t/0]).

command_type() -> pick_up_passenger_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #pick_up_passenger_v1{
        vehicle_id   = Id,
        x          = maps:get(x, P, undefined),
        y          = maps:get(y, P, undefined),
        picked_up_at = maps:get(picked_up_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #pick_up_passenger_v1{
        vehicle_id   = Id,
        x          = maps:get(<<"x">>, M, undefined),
        y          = maps:get(<<"y">>, M, undefined),
        picked_up_at = maps:get(<<"picked_up_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #pick_up_passenger_v1{
        vehicle_id   = Id,
        x          = maps:get(x, M, undefined),
        y          = maps:get(y, M, undefined),
        picked_up_at = maps:get(picked_up_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#pick_up_passenger_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#pick_up_passenger_v1{} = C) ->
    #{command_type => <<"pick_up_passenger">>,
      vehicle_id   => C#pick_up_passenger_v1.vehicle_id,
      x          => C#pick_up_passenger_v1.x,
      y          => C#pick_up_passenger_v1.y,
      picked_up_at => C#pick_up_passenger_v1.picked_up_at}.

-spec stream_id(t()) -> binary().
stream_id(#pick_up_passenger_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#pick_up_passenger_v1{vehicle_id = V})     -> V.
get_x(#pick_up_passenger_v1{x = V})                   -> V.
get_y(#pick_up_passenger_v1{y = V})                   -> V.
get_picked_up_at(#pick_up_passenger_v1{picked_up_at = V}) -> V.
