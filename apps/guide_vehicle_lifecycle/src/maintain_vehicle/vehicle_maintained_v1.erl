%%% @doc Event `vehicle_maintained_v1`. Scheduled maintenance was performed
%%% on a docked vehicle.
-module(vehicle_maintained_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_maintenance_cents/1, get_maintained_at/1]).

-record(vehicle_maintained_v1, {
    vehicle_id    :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id    :: binary() | undefined,
    maintenance_cents :: non_neg_integer() | undefined,
    maintained_at :: binary() | undefined
}).

-opaque t() :: #vehicle_maintained_v1{}.
-export_type([t/0]).

event_type() -> vehicle_maintained_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #vehicle_maintained_v1{
        vehicle_id    = Id,
        plate       = maps:get(plate, P, undefined),
        company_id    = maps:get(company_id, P, undefined),
        maintenance_cents = maps:get(maintenance_cents, P, undefined),
        maintained_at = maps:get(maintained_at, P, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #vehicle_maintained_v1{
        vehicle_id    = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        company_id    = maps:get(<<"company_id">>, M, undefined),
        maintenance_cents = maps:get(<<"maintenance_cents">>, M, undefined),
        maintained_at = maps:get(<<"maintained_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #vehicle_maintained_v1{
        vehicle_id    = Id,
        plate       = maps:get(plate, M, undefined),
        company_id    = maps:get(company_id, M, undefined),
        maintenance_cents = maps:get(maintenance_cents, M, undefined),
        maintained_at = maps:get(maintained_at, M, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_maintained_v1{} = E) ->
    #{event_type    => <<"vehicle_maintained">>,
      vehicle_id    => E#vehicle_maintained_v1.vehicle_id,
      plate    => E#vehicle_maintained_v1.plate,
      company_id    => E#vehicle_maintained_v1.company_id,
      maintenance_cents => E#vehicle_maintained_v1.maintenance_cents,
      maintained_at => E#vehicle_maintained_v1.maintained_at}.

get_vehicle_id(#vehicle_maintained_v1{vehicle_id = V})       -> V.
get_company_id(#vehicle_maintained_v1{company_id = V})       -> V.
get_maintenance_cents(#vehicle_maintained_v1{maintenance_cents = V}) -> V.
get_maintained_at(#vehicle_maintained_v1{maintained_at = V}) -> V.
