%%% @doc Command `drop_off_passenger_v1`. The vehicle reached the dropoff
%%% point; the passenger alights and the fare is settled. Produces two
%%% events: the drop-off (back to cruising) and the fare collection.
-module(drop_off_passenger_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_x/1, get_y/1, get_fare_cents/1, get_tip_cents/1, get_surge_multiplier/1, get_payment_method/1,
         get_dropped_off_at/1]).

-record(drop_off_passenger_v1, {
    vehicle_id     :: binary() | undefined,
    x            :: number() | undefined,
    y            :: number() | undefined,
    fare_cents     :: non_neg_integer() | undefined,
    tip_cents      :: non_neg_integer() | undefined,
    surge_multiplier :: number() | undefined,
    payment_method :: binary() | undefined,
    dropped_off_at :: binary() | undefined
}).

-opaque t() :: #drop_off_passenger_v1{}.
-export_type([t/0]).

command_type() -> drop_off_passenger_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #drop_off_passenger_v1{
        vehicle_id     = Id,
        x            = maps:get(x, P, undefined),
        y            = maps:get(y, P, undefined),
        fare_cents     = maps:get(fare_cents, P, 0),
        tip_cents      = maps:get(tip_cents, P, 0),
        surge_multiplier = maps:get(surge_multiplier, P, undefined),
        payment_method = maps:get(payment_method, P, undefined),
        dropped_off_at = maps:get(dropped_off_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #drop_off_passenger_v1{
        vehicle_id     = Id,
        x            = maps:get(<<"x">>, M, undefined),
        y            = maps:get(<<"y">>, M, undefined),
        fare_cents     = maps:get(<<"fare_cents">>, M, 0),
        tip_cents      = maps:get(<<"tip_cents">>, M, 0),
        surge_multiplier = maps:get(<<"surge_multiplier">>, M, undefined),
        payment_method = maps:get(<<"payment_method">>, M, undefined),
        dropped_off_at = maps:get(<<"dropped_off_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #drop_off_passenger_v1{
        vehicle_id     = Id,
        x            = maps:get(x, M, undefined),
        y            = maps:get(y, M, undefined),
        fare_cents     = maps:get(fare_cents, M, 0),
        tip_cents      = maps:get(tip_cents, M, 0),
        surge_multiplier = maps:get(surge_multiplier, M, undefined),
        payment_method = maps:get(payment_method, M, undefined),
        dropped_off_at = maps:get(dropped_off_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#drop_off_passenger_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#drop_off_passenger_v1{} = C) ->
    #{command_type   => <<"drop_off_passenger">>,
      vehicle_id     => C#drop_off_passenger_v1.vehicle_id,
      x            => C#drop_off_passenger_v1.x,
      y            => C#drop_off_passenger_v1.y,
      fare_cents     => C#drop_off_passenger_v1.fare_cents,
      tip_cents      => C#drop_off_passenger_v1.tip_cents,
      surge_multiplier => C#drop_off_passenger_v1.surge_multiplier,
      payment_method => C#drop_off_passenger_v1.payment_method,
      dropped_off_at => C#drop_off_passenger_v1.dropped_off_at}.

-spec stream_id(t()) -> binary().
stream_id(#drop_off_passenger_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#drop_off_passenger_v1{vehicle_id = V})         -> V.
get_x(#drop_off_passenger_v1{x = V})                       -> V.
get_y(#drop_off_passenger_v1{y = V})                       -> V.
get_fare_cents(#drop_off_passenger_v1{fare_cents = V})         -> V.
get_tip_cents(#drop_off_passenger_v1{tip_cents = V})           -> V.
get_surge_multiplier(#drop_off_passenger_v1{surge_multiplier = V}) -> V.
get_payment_method(#drop_off_passenger_v1{payment_method = V}) -> V.
get_dropped_off_at(#drop_off_passenger_v1{dropped_off_at = V}) -> V.
