%%% @doc Event `payment_captured_v1`. Payment recorded for a session.
-module(payment_captured_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_fee_cents/1, get_plate/1, get_lot_id/1,
         get_payment_method/1, get_paid_at/1]).

-record(payment_captured_v1, {
    session_id     :: binary() | undefined,
    fee_cents   :: non_neg_integer() | undefined,
    plate          :: binary() | undefined,
    lot_id         :: binary() | undefined,
    payment_method :: binary() | undefined,
    paid_at        :: binary() | undefined
}).

-opaque t() :: #payment_captured_v1{}.
-export_type([t/0]).

event_type() -> payment_captured_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = Params) ->
    {ok, #payment_captured_v1{
        session_id     = Id,
        fee_cents   = maps:get(fee_cents,   Params, undefined),
        plate          = maps:get(plate,           Params, undefined),
        lot_id         = maps:get(lot_id,          Params, undefined),
        payment_method = maps:get(payment_method,  Params, undefined),
        paid_at        = maps:get(paid_at,         Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = Map) ->
    {ok, #payment_captured_v1{
        session_id     = Id,
        fee_cents   = maps:get(<<"fee_cents">>,   Map, undefined),
        plate          = maps:get(<<"plate">>,          Map, undefined),
        lot_id         = maps:get(<<"lot_id">>,         Map, undefined),
        payment_method = maps:get(<<"payment_method">>, Map, undefined),
        paid_at        = maps:get(<<"paid_at">>,        Map, undefined)
    }};
from_map(#{session_id := Id} = Map) ->
    {ok, #payment_captured_v1{
        session_id     = Id,
        fee_cents   = maps:get(fee_cents,   Map, undefined),
        plate          = maps:get(plate,          Map, undefined),
        lot_id         = maps:get(lot_id,         Map, undefined),
        payment_method = maps:get(payment_method, Map, undefined),
        paid_at        = maps:get(paid_at,        Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#payment_captured_v1{} = Ev) ->
    #{
        event_type     => <<"payment_captured">>,
        session_id     => Ev#payment_captured_v1.session_id,
        fee_cents   => Ev#payment_captured_v1.fee_cents,
        plate          => Ev#payment_captured_v1.plate,
        lot_id         => Ev#payment_captured_v1.lot_id,
        payment_method => Ev#payment_captured_v1.payment_method,
        paid_at        => Ev#payment_captured_v1.paid_at
    }.

get_session_id(#payment_captured_v1{session_id = V})         -> V.
get_fee_cents(#payment_captured_v1{fee_cents = V})     -> V.
get_plate(#payment_captured_v1{plate = V})                   -> V.
get_lot_id(#payment_captured_v1{lot_id = V})                 -> V.
get_payment_method(#payment_captured_v1{payment_method = V}) -> V.
get_paid_at(#payment_captured_v1{paid_at = V})               -> V.
