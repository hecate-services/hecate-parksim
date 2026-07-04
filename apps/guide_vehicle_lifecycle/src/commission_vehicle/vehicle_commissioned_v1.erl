%%% @doc Event `vehicle_commissioned_v1`. A robotaxi joined the fleet;
%%% vehicle dossier born.
-module(vehicle_commissioned_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_model/1, get_home_facility_id/1, get_battery_pct/1,
         get_x/1, get_y/1, get_commissioned_at/1]).

-record(vehicle_commissioned_v1, {
    vehicle_id      :: binary() | undefined,
    plate           :: binary() | undefined,
    company_id      :: binary() | undefined,
    model           :: binary() | undefined,
    home_facility_id :: binary() | undefined,
    battery_pct     :: number() | undefined,
    x             :: number() | undefined,
    y             :: number() | undefined,
    commissioned_at :: binary() | undefined
}).

-opaque t() :: #vehicle_commissioned_v1{}.
-export_type([t/0]).

event_type() -> vehicle_commissioned_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_commissioned_v1{
        vehicle_id      = Id,
        plate           = maps:get(plate, P, undefined),
        company_id      = maps:get(company_id, P, undefined),
        model           = maps:get(model, P, undefined),
        home_facility_id = maps:get(home_facility_id, P, undefined),
        battery_pct     = maps:get(battery_pct, P, 100),
        x             = maps:get(x, P, undefined),
        y             = maps:get(y, P, undefined),
        commissioned_at = maps:get(commissioned_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_commissioned_v1{
        vehicle_id      = Id,
        plate           = maps:get(<<"plate">>, M, undefined),
        company_id      = maps:get(<<"company_id">>, M, undefined),
        model           = maps:get(<<"model">>, M, undefined),
        home_facility_id = maps:get(<<"home_facility_id">>, M, undefined),
        battery_pct     = maps:get(<<"battery_pct">>, M, 100),
        x             = maps:get(<<"x">>, M, undefined),
        y             = maps:get(<<"y">>, M, undefined),
        commissioned_at = maps:get(<<"commissioned_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_commissioned_v1{
        vehicle_id      = Id,
        plate           = maps:get(plate, M, undefined),
        company_id      = maps:get(company_id, M, undefined),
        model           = maps:get(model, M, undefined),
        home_facility_id = maps:get(home_facility_id, M, undefined),
        battery_pct     = maps:get(battery_pct, M, 100),
        x             = maps:get(x, M, undefined),
        y             = maps:get(y, M, undefined),
        commissioned_at = maps:get(commissioned_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_commissioned_v1{} = E) ->
    #{event_type      => <<"vehicle_commissioned">>,
      vehicle_id      => E#vehicle_commissioned_v1.vehicle_id,
      plate           => E#vehicle_commissioned_v1.plate,
      company_id      => E#vehicle_commissioned_v1.company_id,
      model           => E#vehicle_commissioned_v1.model,
      home_facility_id => E#vehicle_commissioned_v1.home_facility_id,
      battery_pct     => E#vehicle_commissioned_v1.battery_pct,
      x             => E#vehicle_commissioned_v1.x,
      y             => E#vehicle_commissioned_v1.y,
      commissioned_at => E#vehicle_commissioned_v1.commissioned_at}.

get_vehicle_id(#vehicle_commissioned_v1{vehicle_id = V})           -> V.
get_company_id(#vehicle_commissioned_v1{company_id = V})           -> V.
get_model(#vehicle_commissioned_v1{model = V})                     -> V.
get_home_facility_id(#vehicle_commissioned_v1{home_facility_id = V}) -> V.
get_battery_pct(#vehicle_commissioned_v1{battery_pct = V})         -> V.
get_x(#vehicle_commissioned_v1{x = V})                         -> V.
get_y(#vehicle_commissioned_v1{y = V})                         -> V.
get_commissioned_at(#vehicle_commissioned_v1{commissioned_at = V}) -> V.
