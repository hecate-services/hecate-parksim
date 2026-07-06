%%% @doc Command `cancel_ride_v1`. A ride is cancelled after a cab was assigned
%%% (rider changed their mind, no-show, or operator pulled it). A cancellation
%%% fee may apply.
-module(cancel_ride_v1).
-behaviour(evoq_command).

-export([command_type/0, new/1, from_map/1, validate/1, to_map/1, stream_id/1]).
-export([get_ride_id/1, get_reason/1, get_cancellation_fee_cents/1, get_cancelled_at/1]).

-record(cancel_ride_v1, {ride_id, reason, cancellation_fee_cents, cancelled_at}).
-opaque t() :: #cancel_ride_v1{}.
-export_type([t/0]).

command_type() -> cancel_ride_v1.

new(#{ride_id := Id} = P) -> {ok, f(Id, P)};
new(_) -> {error, missing_aggregate_id}.

from_map(#{<<"ride_id">> := Id} = M) -> {ok, fb(Id, M)};
from_map(#{ride_id := Id} = M) -> {ok, f(Id, M)};
from_map(_) -> {error, missing_aggregate_id}.

f(Id, M) -> #cancel_ride_v1{ride_id = Id,
    reason = maps:get(reason, M, <<"rider_cancelled">>),
    cancellation_fee_cents = maps:get(cancellation_fee_cents, M, 0),
    cancelled_at = maps:get(cancelled_at, M, undefined)}.
fb(Id, M) -> #cancel_ride_v1{ride_id = Id,
    reason = maps:get(<<"reason">>, M, <<"rider_cancelled">>),
    cancellation_fee_cents = maps:get(<<"cancellation_fee_cents">>, M, 0),
    cancelled_at = maps:get(<<"cancelled_at">>, M, undefined)}.

validate(#cancel_ride_v1{ride_id = undefined}) -> {error, missing_aggregate_id};
validate(#cancel_ride_v1{}) -> ok.

to_map(#cancel_ride_v1{} = C) ->
    #{command_type => <<"cancel_ride">>,
      ride_id => C#cancel_ride_v1.ride_id,
      reason => C#cancel_ride_v1.reason,
      cancellation_fee_cents => C#cancel_ride_v1.cancellation_fee_cents,
      cancelled_at => C#cancel_ride_v1.cancelled_at}.

stream_id(#cancel_ride_v1{ride_id = Id}) -> <<"ride-", Id/binary>>.

get_ride_id(#cancel_ride_v1{ride_id = V}) -> V.
get_reason(#cancel_ride_v1{reason = V}) -> V.
get_cancellation_fee_cents(#cancel_ride_v1{cancellation_fee_cents = V}) -> V.
get_cancelled_at(#cancel_ride_v1{cancelled_at = V}) -> V.
