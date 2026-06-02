%%% @doc Command `complete_ride_v1`. Passenger dropped off; fare collected.
-module(complete_ride_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_ride_id/1, get_fare_cents/1, get_completed_at/1]).

-record(complete_ride_v1, {
    ride_id      :: binary() | undefined,
    fare_cents   :: non_neg_integer() | undefined,
    completed_at :: binary() | undefined
}).

-opaque t() :: #complete_ride_v1{}.
-export_type([t/0]).

command_type() -> complete_ride_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{ride_id := Id} = P) ->
    {ok, #complete_ride_v1{ride_id = Id,
                           fare_cents = maps:get(fare_cents, P, 0),
                           completed_at = maps:get(completed_at, P, undefined)}};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #complete_ride_v1{ride_id = Id,
                           fare_cents = maps:get(<<"fare_cents">>, M, 0),
                           completed_at = maps:get(<<"completed_at">>, M, undefined)}};
from_map(#{ride_id := Id} = M) ->
    {ok, #complete_ride_v1{ride_id = Id,
                           fare_cents = maps:get(fare_cents, M, 0),
                           completed_at = maps:get(completed_at, M, undefined)}};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#complete_ride_v1{ride_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#complete_ride_v1{} = C) ->
    #{command_type => <<"complete_ride">>,
      ride_id      => C#complete_ride_v1.ride_id,
      fare_cents   => C#complete_ride_v1.fare_cents,
      completed_at => C#complete_ride_v1.completed_at}.

-spec stream_id(t()) -> binary().
stream_id(#complete_ride_v1{ride_id = Id}) -> <<"ride-", Id/binary>>.

get_ride_id(#complete_ride_v1{ride_id = V})           -> V.
get_fare_cents(#complete_ride_v1{fare_cents = V})     -> V.
get_completed_at(#complete_ride_v1{completed_at = V}) -> V.
