%%% @doc Event `ride_completed_v1`. Dropped off, fare collected; ride done.
-module(ride_completed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_company_id/1, get_vehicle_id/1, get_fare_cents/1, get_tip_cents/1, get_rating/1, get_completed_at/1]).

-record(ride_completed_v1, {
    ride_id      :: binary() | undefined,
    company_id      :: binary() | undefined,
    vehicle_id   :: binary() | undefined,
    plate       :: binary() | undefined,
    fare_cents   :: non_neg_integer() | undefined,
    tip_cents    :: non_neg_integer() | undefined,
    rating       :: 1..5 | undefined,
    completed_at :: binary() | undefined
}).

-opaque t() :: #ride_completed_v1{}.
-export_type([t/0]).

event_type() -> ride_completed_v1.

-spec new(map()) -> {ok, t()}.
new(#{ride_id := Id} = P) ->
    {ok, #ride_completed_v1{
        ride_id      = Id,
        vehicle_id   = maps:get(vehicle_id, P, undefined),
        plate   = maps:get(plate, P, undefined),
        fare_cents   = maps:get(fare_cents, P, 0),
        tip_cents    = maps:get(tip_cents, P, 0),
        rating       = maps:get(rating, P, undefined),
        completed_at = maps:get(completed_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #ride_completed_v1{
        ride_id      = Id,
        vehicle_id   = maps:get(<<"vehicle_id">>, M, undefined),
        plate   = maps:get(<<"plate">>, M, undefined),
        fare_cents   = maps:get(<<"fare_cents">>, M, 0),
        tip_cents    = maps:get(<<"tip_cents">>, M, 0),
        rating       = maps:get(<<"rating">>, M, undefined),
        completed_at = maps:get(<<"completed_at">>, M, undefined)
    }};
from_map(#{ride_id := Id} = M) ->
    {ok, #ride_completed_v1{
        ride_id      = Id,
        vehicle_id   = maps:get(vehicle_id, M, undefined),
        plate   = maps:get(plate, M, undefined),
        fare_cents   = maps:get(fare_cents, M, 0),
        tip_cents    = maps:get(tip_cents, M, 0),
        rating       = maps:get(rating, M, undefined),
        completed_at = maps:get(completed_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#ride_completed_v1{} = E) ->
    #{event_type   => <<"ride_completed">>,
      ride_id      => E#ride_completed_v1.ride_id,
      company_id   => E#ride_completed_v1.company_id,
      vehicle_id   => E#ride_completed_v1.vehicle_id,
      plate   => E#ride_completed_v1.plate,
      fare_cents   => E#ride_completed_v1.fare_cents,
      tip_cents    => E#ride_completed_v1.tip_cents,
      rating       => E#ride_completed_v1.rating,
      completed_at => E#ride_completed_v1.completed_at}.

get_ride_id(#ride_completed_v1{ride_id = V})           -> V.
get_company_id(#ride_completed_v1{company_id = V}) -> V.
get_vehicle_id(#ride_completed_v1{vehicle_id = V})     -> V.
get_fare_cents(#ride_completed_v1{fare_cents = V})     -> V.
get_tip_cents(#ride_completed_v1{tip_cents = V})       -> V.
get_rating(#ride_completed_v1{rating = V})             -> V.
get_completed_at(#ride_completed_v1{completed_at = V}) -> V.
