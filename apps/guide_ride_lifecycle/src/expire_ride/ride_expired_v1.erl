%%% @doc Event `ride_expired_v1`. The rider gave up before a cab arrived.
-module(ride_expired_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_company_id/1, get_expired_at/1]).

-record(ride_expired_v1, {
    ride_id    :: binary() | undefined,
    company_id    :: binary() | undefined,
    expired_at :: binary() | undefined
}).

-opaque t() :: #ride_expired_v1{}.
-export_type([t/0]).

event_type() -> ride_expired_v1.

-spec new(map()) -> {ok, t()}.
new(#{ride_id := Id} = P) ->
    {ok, #ride_expired_v1{ride_id = Id, company_id = maps:get(company_id, P, undefined), expired_at = maps:get(expired_at, P, undefined)}}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #ride_expired_v1{ride_id = Id, company_id = maps:get(<<"company_id">>, M, undefined), expired_at = maps:get(<<"expired_at">>, M, undefined)}};
from_map(#{ride_id := Id} = M) ->
    {ok, #ride_expired_v1{ride_id = Id, company_id = maps:get(company_id, M, undefined), expired_at = maps:get(expired_at, M, undefined)}}.

-spec to_map(t()) -> map().
to_map(#ride_expired_v1{} = E) ->
    #{event_type => <<"ride_expired">>,
      ride_id    => E#ride_expired_v1.ride_id,
      company_id    => E#ride_expired_v1.company_id,
      expired_at => E#ride_expired_v1.expired_at}.

get_ride_id(#ride_expired_v1{ride_id = V})       -> V.
get_company_id(#ride_expired_v1{company_id = V}) -> V.
get_expired_at(#ride_expired_v1{expired_at = V}) -> V.
