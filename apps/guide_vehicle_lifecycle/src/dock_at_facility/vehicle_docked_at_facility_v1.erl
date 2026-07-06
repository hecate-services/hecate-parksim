%%% @doc Event `vehicle_docked_at_facility_v1`. The robotaxi took a bay at a
%%% service facility. (`_at_facility` suffix disambiguates from the
%%% parking-session `vehicle_docked_v1` — module names are global.)
-module(vehicle_docked_at_facility_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_facility_id/1, get_bay_id/1,
         get_x/1, get_y/1, get_docked_at/1]).

-record(vehicle_docked_at_facility_v1, {
    vehicle_id  :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id  :: binary() | undefined,
    facility_id :: binary() | undefined,
    bay_id      :: binary() | undefined,
    x           :: number() | undefined,
    y           :: number() | undefined,
    docked_at   :: binary() | undefined
}).

-opaque t() :: #vehicle_docked_at_facility_v1{}.
-export_type([t/0]).

event_type() -> vehicle_docked_at_facility_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_docked_at_facility_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, P, undefined),
        company_id  = maps:get(company_id, P, undefined),
        facility_id = maps:get(facility_id, P, undefined),
        bay_id      = maps:get(bay_id, P, undefined),
        x           = maps:get(x, P, undefined),
        y           = maps:get(y, P, undefined),
        docked_at   = maps:get(docked_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_docked_at_facility_v1{
        vehicle_id  = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id  = maps:get(<<"company_id">>, M, undefined),
        facility_id = maps:get(<<"facility_id">>, M, undefined),
        bay_id      = maps:get(<<"bay_id">>, M, undefined),
        x           = maps:get(<<"x">>, M, undefined),
        y           = maps:get(<<"y">>, M, undefined),
        docked_at   = maps:get(<<"docked_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_docked_at_facility_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, M, undefined),
        company_id  = maps:get(company_id, M, undefined),
        facility_id = maps:get(facility_id, M, undefined),
        bay_id      = maps:get(bay_id, M, undefined),
        x           = maps:get(x, M, undefined),
        y           = maps:get(y, M, undefined),
        docked_at   = maps:get(docked_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_docked_at_facility_v1{} = E) ->
    #{event_type   => <<"vehicle_docked_at_facility">>,
      vehicle_id   => E#vehicle_docked_at_facility_v1.vehicle_id,
      plate        => E#vehicle_docked_at_facility_v1.plate,
      company_id   => E#vehicle_docked_at_facility_v1.company_id,
      facility_id  => E#vehicle_docked_at_facility_v1.facility_id,
      bay_id       => E#vehicle_docked_at_facility_v1.bay_id,
      x            => E#vehicle_docked_at_facility_v1.x,
      y            => E#vehicle_docked_at_facility_v1.y,
      docked_at    => E#vehicle_docked_at_facility_v1.docked_at}.

get_vehicle_id(#vehicle_docked_at_facility_v1{vehicle_id = V})   -> V.
get_company_id(#vehicle_docked_at_facility_v1{company_id = V})   -> V.
get_facility_id(#vehicle_docked_at_facility_v1{facility_id = V}) -> V.
get_bay_id(#vehicle_docked_at_facility_v1{bay_id = V})           -> V.
get_x(#vehicle_docked_at_facility_v1{x = V})                 -> V.
get_y(#vehicle_docked_at_facility_v1{y = V})                 -> V.
get_docked_at(#vehicle_docked_at_facility_v1{docked_at = V})     -> V.
