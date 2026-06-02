%%% @doc Command `start_ride_v1`. Passenger picked up; the trip begins.
-module(start_ride_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_ride_id/1, get_started_at/1]).

-record(start_ride_v1, {
    ride_id    :: binary() | undefined,
    started_at :: binary() | undefined
}).

-opaque t() :: #start_ride_v1{}.
-export_type([t/0]).

command_type() -> start_ride_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{ride_id := Id} = P) ->
    {ok, #start_ride_v1{ride_id = Id, started_at = maps:get(started_at, P, undefined)}};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #start_ride_v1{ride_id = Id, started_at = maps:get(<<"started_at">>, M, undefined)}};
from_map(#{ride_id := Id} = M) ->
    {ok, #start_ride_v1{ride_id = Id, started_at = maps:get(started_at, M, undefined)}};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#start_ride_v1{ride_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#start_ride_v1{} = C) ->
    #{command_type => <<"start_ride">>,
      ride_id      => C#start_ride_v1.ride_id,
      started_at   => C#start_ride_v1.started_at}.

-spec stream_id(t()) -> binary().
stream_id(#start_ride_v1{ride_id = Id}) -> <<"ride-", Id/binary>>.

get_ride_id(#start_ride_v1{ride_id = V})       -> V.
get_started_at(#start_ride_v1{started_at = V}) -> V.
