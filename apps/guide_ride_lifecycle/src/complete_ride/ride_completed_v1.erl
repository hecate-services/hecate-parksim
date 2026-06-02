%%% @doc Event `ride_completed_v1`. Dropped off, fare collected; ride done.
-module(ride_completed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_fare_cents/1, get_completed_at/1]).

-record(ride_completed_v1, {
    ride_id      :: binary() | undefined,
    fare_cents   :: non_neg_integer() | undefined,
    completed_at :: binary() | undefined
}).

-opaque t() :: #ride_completed_v1{}.
-export_type([t/0]).

event_type() -> ride_completed_v1.

-spec new(map()) -> {ok, t()}.
new(#{ride_id := Id} = P) ->
    {ok, #ride_completed_v1{ride_id = Id,
                            fare_cents = maps:get(fare_cents, P, 0),
                            completed_at = maps:get(completed_at, P, undefined)}}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #ride_completed_v1{ride_id = Id,
                            fare_cents = maps:get(<<"fare_cents">>, M, 0),
                            completed_at = maps:get(<<"completed_at">>, M, undefined)}};
from_map(#{ride_id := Id} = M) ->
    {ok, #ride_completed_v1{ride_id = Id,
                            fare_cents = maps:get(fare_cents, M, 0),
                            completed_at = maps:get(completed_at, M, undefined)}}.

-spec to_map(t()) -> map().
to_map(#ride_completed_v1{} = E) ->
    #{event_type   => <<"ride_completed">>,
      ride_id      => E#ride_completed_v1.ride_id,
      fare_cents   => E#ride_completed_v1.fare_cents,
      completed_at => E#ride_completed_v1.completed_at}.

get_ride_id(#ride_completed_v1{ride_id = V})           -> V.
get_fare_cents(#ride_completed_v1{fare_cents = V})     -> V.
get_completed_at(#ride_completed_v1{completed_at = V}) -> V.
