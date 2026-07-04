%%% @doc Event `fare_collected_v1`. The fare for a completed trip was
%%% banked. Rides alongside `passenger_dropped_off_v1` (no phase change of
%%% its own) — the revenue half of a drop-off.
-module(fare_collected_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_ride_id/1,
         get_trip_id/1, get_fare_cents/1, get_tip_cents/1, get_surge_multiplier/1, get_payment_method/1, get_collected_at/1]).

-record(fare_collected_v1, {
    vehicle_id   :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id   :: binary() | undefined,
    ride_id      :: binary() | undefined,
    trip_id      :: binary() | undefined,
    fare_cents :: non_neg_integer() | undefined,
    tip_cents      :: non_neg_integer() | undefined,
    surge_multiplier :: number() | undefined,
    payment_method :: binary() | undefined,
    collected_at :: binary() | undefined
}).

-opaque t() :: #fare_collected_v1{}.
-export_type([t/0]).

event_type() -> fare_collected_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #fare_collected_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, P, undefined),
        company_id   = maps:get(company_id, P, undefined),
        ride_id      = maps:get(ride_id, P, undefined),
        trip_id      = maps:get(trip_id, P, undefined),
        fare_cents = maps:get(fare_cents, P, 0),
        tip_cents      = maps:get(tip_cents, P, 0),
        surge_multiplier = maps:get(surge_multiplier, P, undefined),
        payment_method = maps:get(payment_method, P, undefined),
        collected_at = maps:get(collected_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #fare_collected_v1{
        vehicle_id   = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id   = maps:get(<<"company_id">>, M, undefined),
        ride_id      = maps:get(<<"ride_id">>, M, undefined),
        trip_id      = maps:get(<<"trip_id">>, M, undefined),
        fare_cents = maps:get(<<"fare_cents">>, M, 0),
        tip_cents      = maps:get(<<"tip_cents">>, M, 0),
        surge_multiplier = maps:get(<<"surge_multiplier">>, M, undefined),
        payment_method = maps:get(<<"payment_method">>, M, undefined),
        collected_at = maps:get(<<"collected_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #fare_collected_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, M, undefined),
        company_id   = maps:get(company_id, M, undefined),
        ride_id      = maps:get(ride_id, M, undefined),
        trip_id      = maps:get(trip_id, M, undefined),
        fare_cents = maps:get(fare_cents, M, 0),
        tip_cents      = maps:get(tip_cents, M, 0),
        surge_multiplier = maps:get(surge_multiplier, M, undefined),
        payment_method = maps:get(payment_method, M, undefined),
        collected_at = maps:get(collected_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#fare_collected_v1{} = E) ->
    #{event_type   => <<"fare_collected">>,
      vehicle_id   => E#fare_collected_v1.vehicle_id,
      plate   => E#fare_collected_v1.plate,
      company_id   => E#fare_collected_v1.company_id,
      ride_id      => E#fare_collected_v1.ride_id,
      trip_id      => E#fare_collected_v1.trip_id,
      fare_cents => E#fare_collected_v1.fare_cents,
      tip_cents      => E#fare_collected_v1.tip_cents,
      surge_multiplier => E#fare_collected_v1.surge_multiplier,
      payment_method => E#fare_collected_v1.payment_method,
      collected_at => E#fare_collected_v1.collected_at}.

get_vehicle_id(#fare_collected_v1{vehicle_id = V})     -> V.
get_company_id(#fare_collected_v1{company_id = V})     -> V.
get_ride_id(#fare_collected_v1{ride_id = V})           -> V.
get_trip_id(#fare_collected_v1{trip_id = V})           -> V.
get_fare_cents(#fare_collected_v1{fare_cents = V}) -> V.
get_tip_cents(#fare_collected_v1{tip_cents = V})           -> V.
get_surge_multiplier(#fare_collected_v1{surge_multiplier = V}) -> V.
get_payment_method(#fare_collected_v1{payment_method = V}) -> V.
get_collected_at(#fare_collected_v1{collected_at = V}) -> V.
