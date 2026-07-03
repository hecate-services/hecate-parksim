%%% @doc Event `vehicle_cleaned_v1`. A docked vehicle was cleaned.
-module(vehicle_cleaned_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_cleaned_at/1]).

-record(vehicle_cleaned_v1, {
    vehicle_id :: binary() | undefined,
    company_id :: binary() | undefined,
    cleaned_at :: binary() | undefined
}).

-opaque t() :: #vehicle_cleaned_v1{}.
-export_type([t/0]).

event_type() -> vehicle_cleaned_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_cleaned_v1{
        vehicle_id = Id,
        company_id = maps:get(company_id, P, undefined),
        cleaned_at = maps:get(cleaned_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_cleaned_v1{
        vehicle_id = Id,
        company_id = maps:get(<<"company_id">>, M, undefined),
        cleaned_at = maps:get(<<"cleaned_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_cleaned_v1{
        vehicle_id = Id,
        company_id = maps:get(company_id, M, undefined),
        cleaned_at = maps:get(cleaned_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_cleaned_v1{} = E) ->
    #{event_type => <<"vehicle_cleaned">>,
      vehicle_id => E#vehicle_cleaned_v1.vehicle_id,
      company_id => E#vehicle_cleaned_v1.company_id,
      cleaned_at => E#vehicle_cleaned_v1.cleaned_at}.

get_vehicle_id(#vehicle_cleaned_v1{vehicle_id = V}) -> V.
get_company_id(#vehicle_cleaned_v1{company_id = V}) -> V.
get_cleaned_at(#vehicle_cleaned_v1{cleaned_at = V}) -> V.
