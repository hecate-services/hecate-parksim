%%% @doc Command `capture_payment_v1`. Payment recorded for a session.
-module(capture_payment_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_fee_cents/1, get_paid_at/1]).

-record(capture_payment_v1, {
    session_id   :: binary() | undefined,
    fee_cents :: non_neg_integer() | undefined,
    paid_at      :: binary() | undefined
}).

-opaque t() :: #capture_payment_v1{}.
-export_type([t/0]).

command_type() -> capture_payment_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{session_id := Id} = Params) ->
    {ok, #capture_payment_v1{
        session_id   = Id,
        fee_cents = maps:get(fee_cents, Params, undefined),
        paid_at      = maps:get(paid_at,      Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"session_id">> := Id} = Map) ->
    {ok, #capture_payment_v1{
        session_id   = Id,
        fee_cents = maps:get(<<"fee_cents">>, Map, undefined),
        paid_at      = maps:get(<<"paid_at">>,      Map, undefined)
    }};
from_map(#{session_id := Id} = Map) ->
    {ok, #capture_payment_v1{
        session_id   = Id,
        fee_cents = maps:get(fee_cents, Map, undefined),
        paid_at      = maps:get(paid_at,      Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#capture_payment_v1{session_id   = undefined}) -> {error, missing_aggregate_id};
validate(#capture_payment_v1{fee_cents = undefined}) -> {error, missing_fee_cents};
validate(#capture_payment_v1{fee_cents = N}) when not is_integer(N) -> {error, invalid_fee_cents};
validate(#capture_payment_v1{fee_cents = N}) when N < 0 -> {error, invalid_fee_cents};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#capture_payment_v1{} = Cmd) ->
    #{
        command_type => <<"capture_payment">>,
        session_id   => Cmd#capture_payment_v1.session_id,
        fee_cents => Cmd#capture_payment_v1.fee_cents,
        paid_at      => Cmd#capture_payment_v1.paid_at
    }.

-spec stream_id(t()) -> binary().
stream_id(#capture_payment_v1{session_id = Id}) ->
    <<"parking-session-", Id/binary>>.

get_session_id(#capture_payment_v1{session_id = V})     -> V.
get_fee_cents(#capture_payment_v1{fee_cents = V}) -> V.
get_paid_at(#capture_payment_v1{paid_at = V})           -> V.
