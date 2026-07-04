%%% @doc Event `battery_depleted_v1`. The vehicle's battery hit zero; it is
%%% stranded at (x,y) awaiting a tow.
-module(battery_depleted_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_x/1, get_y/1, get_depleted_at/1]).

-record(battery_depleted_v1, {
    vehicle_id  :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id  :: binary() | undefined,
    x         :: number() | undefined,
    y         :: number() | undefined,
    depleted_at :: binary() | undefined
}).

-opaque t() :: #battery_depleted_v1{}.
-export_type([t/0]).

event_type() -> battery_depleted_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #battery_depleted_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, P, undefined),
        company_id  = maps:get(company_id, P, undefined),
        x         = maps:get(x, P, undefined),
        y         = maps:get(y, P, undefined),
        depleted_at = maps:get(depleted_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #battery_depleted_v1{
        vehicle_id  = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id  = maps:get(<<"company_id">>, M, undefined),
        x         = maps:get(<<"x">>, M, undefined),
        y         = maps:get(<<"y">>, M, undefined),
        depleted_at = maps:get(<<"depleted_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #battery_depleted_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, M, undefined),
        company_id  = maps:get(company_id, M, undefined),
        x         = maps:get(x, M, undefined),
        y         = maps:get(y, M, undefined),
        depleted_at = maps:get(depleted_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#battery_depleted_v1{} = E) ->
    #{event_type   => <<"battery_depleted">>,
      vehicle_id   => E#battery_depleted_v1.vehicle_id,
      plate   => E#battery_depleted_v1.plate,
      company_id   => E#battery_depleted_v1.company_id,
      x          => E#battery_depleted_v1.x,
      y          => E#battery_depleted_v1.y,
      depleted_at  => E#battery_depleted_v1.depleted_at}.

get_vehicle_id(#battery_depleted_v1{vehicle_id = V})   -> V.
get_company_id(#battery_depleted_v1{company_id = V})   -> V.
get_x(#battery_depleted_v1{x = V})                 -> V.
get_y(#battery_depleted_v1{y = V})                 -> V.
get_depleted_at(#battery_depleted_v1{depleted_at = V}) -> V.
