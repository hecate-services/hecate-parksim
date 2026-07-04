%%% @doc Event `passenger_picked_up_v1`. Passenger aboard; the trip and
%%% fare meter are running.
-module(passenger_picked_up_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_ride_id/1,
         get_x/1, get_y/1, get_picked_up_at/1]).

-record(passenger_picked_up_v1, {
    vehicle_id   :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id   :: binary() | undefined,
    ride_id      :: binary() | undefined,
    x          :: number() | undefined,
    y          :: number() | undefined,
    picked_up_at :: binary() | undefined
}).

-opaque t() :: #passenger_picked_up_v1{}.
-export_type([t/0]).

event_type() -> passenger_picked_up_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #passenger_picked_up_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, P, undefined),
        company_id   = maps:get(company_id, P, undefined),
        ride_id      = maps:get(ride_id, P, undefined),
        x          = maps:get(x, P, undefined),
        y          = maps:get(y, P, undefined),
        picked_up_at = maps:get(picked_up_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #passenger_picked_up_v1{
        vehicle_id   = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id   = maps:get(<<"company_id">>, M, undefined),
        ride_id      = maps:get(<<"ride_id">>, M, undefined),
        x          = maps:get(<<"x">>, M, undefined),
        y          = maps:get(<<"y">>, M, undefined),
        picked_up_at = maps:get(<<"picked_up_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #passenger_picked_up_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, M, undefined),
        company_id   = maps:get(company_id, M, undefined),
        ride_id      = maps:get(ride_id, M, undefined),
        x          = maps:get(x, M, undefined),
        y          = maps:get(y, M, undefined),
        picked_up_at = maps:get(picked_up_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#passenger_picked_up_v1{} = E) ->
    #{event_type   => <<"passenger_picked_up">>,
      vehicle_id   => E#passenger_picked_up_v1.vehicle_id,
      plate   => E#passenger_picked_up_v1.plate,
      company_id   => E#passenger_picked_up_v1.company_id,
      ride_id      => E#passenger_picked_up_v1.ride_id,
      x          => E#passenger_picked_up_v1.x,
      y          => E#passenger_picked_up_v1.y,
      picked_up_at => E#passenger_picked_up_v1.picked_up_at}.

get_vehicle_id(#passenger_picked_up_v1{vehicle_id = V})     -> V.
get_company_id(#passenger_picked_up_v1{company_id = V})     -> V.
get_ride_id(#passenger_picked_up_v1{ride_id = V})           -> V.
get_x(#passenger_picked_up_v1{x = V})                   -> V.
get_y(#passenger_picked_up_v1{y = V})                   -> V.
get_picked_up_at(#passenger_picked_up_v1{picked_up_at = V}) -> V.
