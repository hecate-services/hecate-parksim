%%% @doc Event `refund_issued_v1`. Part or all of a completed ride's fare was
%%% refunded. A COST reversal — it reduces the operator's net (a ledger debit).
-module(refund_issued_v1).
-behaviour(evoq_event).

-export([event_type/0, new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_company_id/1, get_refund_cents/1, get_reason/1,
         get_refunded_at/1]).

-record(refund_issued_v1, {ride_id, company_id, refund_cents, reason, refunded_at}).
-opaque t() :: #refund_issued_v1{}.
-export_type([t/0]).

event_type() -> refund_issued_v1.

new(#{ride_id := Id} = P) -> {ok, f(Id, fun(K, D) -> maps:get(K, P, D) end)};
new(P) -> {ok, f(maps:get(ride_id, P, undefined), fun(K, D) -> maps:get(K, P, D) end)}.

from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, f(Id, fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end)};
from_map(#{ride_id := Id} = M) ->
    {ok, f(Id, fun(K, D) -> maps:get(K, M, D) end)}.

f(Id, G) ->
    #refund_issued_v1{ride_id = Id,
        company_id = G(company_id, undefined),
        refund_cents = G(refund_cents, 0),
        reason = G(reason, <<"dispute">>),
        refunded_at = G(refunded_at, undefined)}.

to_map(#refund_issued_v1{} = E) ->
    #{event_type => <<"refund_issued">>,
      ride_id => E#refund_issued_v1.ride_id,
      company_id => E#refund_issued_v1.company_id,
      refund_cents => E#refund_issued_v1.refund_cents,
      reason => E#refund_issued_v1.reason,
      refunded_at => E#refund_issued_v1.refunded_at}.

get_ride_id(#refund_issued_v1{ride_id = V}) -> V.
get_company_id(#refund_issued_v1{company_id = V}) -> V.
get_refund_cents(#refund_issued_v1{refund_cents = V}) -> V.
get_reason(#refund_issued_v1{reason = V}) -> V.
get_refunded_at(#refund_issued_v1{refunded_at = V}) -> V.
