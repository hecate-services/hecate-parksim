%%% @doc Event `fare_collected_v1`. The fare for a completed trip was
%%% banked. Rides alongside `passenger_dropped_off_v1` (no phase change of
%%% its own) — the revenue half of a drop-off.
-module(fare_collected_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_ride_id/1,
         get_trip_id/1, get_amount_cents/1, get_collected_at/1]).

-record(fare_collected_v1, {
    vehicle_id   :: binary() | undefined,
    company_id   :: binary() | undefined,
    ride_id      :: binary() | undefined,
    trip_id      :: binary() | undefined,
    amount_cents :: non_neg_integer() | undefined,
    collected_at :: binary() | undefined
}).

-opaque t() :: #fare_collected_v1{}.
-export_type([t/0]).

event_type() -> fare_collected_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #fare_collected_v1{
        vehicle_id   = Id,
        company_id   = maps:get(company_id, P, undefined),
        ride_id      = maps:get(ride_id, P, undefined),
        trip_id      = maps:get(trip_id, P, undefined),
        amount_cents = maps:get(amount_cents, P, 0),
        collected_at = maps:get(collected_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #fare_collected_v1{
        vehicle_id   = Id,
        company_id   = maps:get(<<"company_id">>, M, undefined),
        ride_id      = maps:get(<<"ride_id">>, M, undefined),
        trip_id      = maps:get(<<"trip_id">>, M, undefined),
        amount_cents = maps:get(<<"amount_cents">>, M, 0),
        collected_at = maps:get(<<"collected_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #fare_collected_v1{
        vehicle_id   = Id,
        company_id   = maps:get(company_id, M, undefined),
        ride_id      = maps:get(ride_id, M, undefined),
        trip_id      = maps:get(trip_id, M, undefined),
        amount_cents = maps:get(amount_cents, M, 0),
        collected_at = maps:get(collected_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#fare_collected_v1{} = E) ->
    #{event_type   => <<"fare_collected">>,
      vehicle_id   => E#fare_collected_v1.vehicle_id,
      company_id   => E#fare_collected_v1.company_id,
      ride_id      => E#fare_collected_v1.ride_id,
      trip_id      => E#fare_collected_v1.trip_id,
      amount_cents => E#fare_collected_v1.amount_cents,
      collected_at => E#fare_collected_v1.collected_at}.

get_vehicle_id(#fare_collected_v1{vehicle_id = V})     -> V.
get_company_id(#fare_collected_v1{company_id = V})     -> V.
get_ride_id(#fare_collected_v1{ride_id = V})           -> V.
get_trip_id(#fare_collected_v1{trip_id = V})           -> V.
get_amount_cents(#fare_collected_v1{amount_cents = V}) -> V.
get_collected_at(#fare_collected_v1{collected_at = V}) -> V.
