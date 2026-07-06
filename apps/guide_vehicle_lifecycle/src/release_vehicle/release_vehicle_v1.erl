%%% @doc Command `release_vehicle_v1`. Service done — free the bay and put
%%% the vehicle back on the market (cruising).
-module(release_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_released_at/1]).

-record(release_vehicle_v1, {
    vehicle_id  :: binary() | undefined,
    plate       :: binary() | undefined,
    released_at :: binary() | undefined
}).

-opaque t() :: #release_vehicle_v1{}.
-export_type([t/0]).

command_type() -> release_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #release_vehicle_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, P, undefined),
        released_at = maps:get(released_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #release_vehicle_v1{
        vehicle_id  = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        released_at = maps:get(<<"released_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #release_vehicle_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, M, undefined),
        released_at = maps:get(released_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#release_vehicle_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#release_vehicle_v1{} = C) ->
    #{command_type => <<"release_vehicle">>,
      vehicle_id   => C#release_vehicle_v1.vehicle_id,
      plate   => C#release_vehicle_v1.plate,
      released_at  => C#release_vehicle_v1.released_at}.

-spec stream_id(t()) -> binary().
stream_id(#release_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#release_vehicle_v1{vehicle_id = V})   -> V.
get_released_at(#release_vehicle_v1{released_at = V}) -> V.
