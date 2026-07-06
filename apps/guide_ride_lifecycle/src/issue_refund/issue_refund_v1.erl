%%% @doc Command `issue_refund_v1`. A completed ride's fare is (partly) refunded
%%% after a rider dispute/complaint.
-module(issue_refund_v1).
-behaviour(evoq_command).

-export([command_type/0, new/1, from_map/1, validate/1, to_map/1, stream_id/1]).
-export([get_ride_id/1, get_refund_cents/1, get_reason/1, get_refunded_at/1]).

-record(issue_refund_v1, {ride_id, refund_cents, reason, refunded_at}).
-opaque t() :: #issue_refund_v1{}.
-export_type([t/0]).

command_type() -> issue_refund_v1.

new(#{ride_id := Id} = P) -> {ok, f(Id, P)};
new(_) -> {error, missing_aggregate_id}.

from_map(#{<<"ride_id">> := Id} = M) -> {ok, fb(Id, M)};
from_map(#{ride_id := Id} = M) -> {ok, f(Id, M)};
from_map(_) -> {error, missing_aggregate_id}.

f(Id, M) -> #issue_refund_v1{ride_id = Id,
    refund_cents = maps:get(refund_cents, M, 0),
    reason = maps:get(reason, M, <<"dispute">>),
    refunded_at = maps:get(refunded_at, M, undefined)}.
fb(Id, M) -> #issue_refund_v1{ride_id = Id,
    refund_cents = maps:get(<<"refund_cents">>, M, 0),
    reason = maps:get(<<"reason">>, M, <<"dispute">>),
    refunded_at = maps:get(<<"refunded_at">>, M, undefined)}.

validate(#issue_refund_v1{ride_id = undefined}) -> {error, missing_aggregate_id};
validate(#issue_refund_v1{}) -> ok.

to_map(#issue_refund_v1{} = C) ->
    #{command_type => <<"issue_refund">>,
      ride_id => C#issue_refund_v1.ride_id,
      refund_cents => C#issue_refund_v1.refund_cents,
      reason => C#issue_refund_v1.reason,
      refunded_at => C#issue_refund_v1.refunded_at}.

stream_id(#issue_refund_v1{ride_id = Id}) -> <<"ride-", Id/binary>>.

get_ride_id(#issue_refund_v1{ride_id = V}) -> V.
get_refund_cents(#issue_refund_v1{refund_cents = V}) -> V.
get_reason(#issue_refund_v1{reason = V}) -> V.
get_refunded_at(#issue_refund_v1{refunded_at = V}) -> V.
