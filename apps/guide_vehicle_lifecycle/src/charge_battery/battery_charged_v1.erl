%%% @doc Event `battery_charged_v1`. A docked vehicle's battery was topped
%%% up. `battery_pct` is the restored level (default 100). The natural
%%% complement to `battery_depleted_v1`.
-module(battery_charged_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_battery_pct/1, get_charged_at/1]).

-record(battery_charged_v1, {
    vehicle_id  :: binary() | undefined,
    company_id  :: binary() | undefined,
    battery_pct :: number() | undefined,
    charged_at  :: binary() | undefined
}).

-opaque t() :: #battery_charged_v1{}.
-export_type([t/0]).

event_type() -> battery_charged_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #battery_charged_v1{
        vehicle_id  = Id,
        company_id  = maps:get(company_id, P, undefined),
        battery_pct = maps:get(battery_pct, P, undefined),
        charged_at  = maps:get(charged_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #battery_charged_v1{
        vehicle_id  = Id,
        company_id  = maps:get(<<"company_id">>, M, undefined),
        battery_pct = maps:get(<<"battery_pct">>, M, undefined),
        charged_at  = maps:get(<<"charged_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #battery_charged_v1{
        vehicle_id  = Id,
        company_id  = maps:get(company_id, M, undefined),
        battery_pct = maps:get(battery_pct, M, undefined),
        charged_at  = maps:get(charged_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#battery_charged_v1{} = E) ->
    #{event_type  => <<"battery_charged">>,
      vehicle_id  => E#battery_charged_v1.vehicle_id,
      company_id  => E#battery_charged_v1.company_id,
      battery_pct => E#battery_charged_v1.battery_pct,
      charged_at  => E#battery_charged_v1.charged_at}.

get_vehicle_id(#battery_charged_v1{vehicle_id = V})   -> V.
get_company_id(#battery_charged_v1{company_id = V})   -> V.
get_battery_pct(#battery_charged_v1{battery_pct = V}) -> V.
get_charged_at(#battery_charged_v1{charged_at = V})   -> V.
