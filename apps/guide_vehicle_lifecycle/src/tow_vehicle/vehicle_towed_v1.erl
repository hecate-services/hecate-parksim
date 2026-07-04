%%% @doc Event `vehicle_towed_v1`. A stranded (depleted) vehicle was towed
%%% to a facility. `tow_cents` is the rescue cost (an operator expense);
%%% `destination_facility_id` is where it was taken. The vehicle is now
%%% RETURNING to that facility (docks + charges normally on arrival).
-module(vehicle_towed_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_tow_truck_id/1, get_from_x/1, get_from_y/1,
         get_destination_facility_id/1, get_tow_distance_m/1, get_tow_cents/1,
         get_towed_at/1]).

-record(vehicle_towed_v1, {
    vehicle_id              :: binary() | undefined,
    plate       :: binary() | undefined,
    company_id              :: binary() | undefined,
    tow_truck_id            :: binary() | undefined,
    from_x                  :: number() | undefined,
    from_y                  :: number() | undefined,
    destination_facility_id :: binary() | undefined,
    tow_distance_m          :: number() | undefined,
    tow_cents               :: non_neg_integer() | undefined,
    towed_at                :: binary() | undefined
}).

-opaque t() :: #vehicle_towed_v1{}.
-export_type([t/0]).

event_type() -> vehicle_towed_v1.

-spec new(map()) -> {ok, t()}.
new(#{vehicle_id := Id} = P) -> {ok, from(Id, P)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"vehicle_id">> := Id} = M) -> {ok, from_bin(Id, M)};
from_map(#{vehicle_id := Id} = M)       -> {ok, from(Id, M)}.

from(Id, M) ->
    #vehicle_towed_v1{
        vehicle_id = Id,
        plate       = maps:get(plate, M, undefined),
        company_id = maps:get(company_id, M, undefined),
        tow_truck_id = maps:get(tow_truck_id, M, undefined),
        from_x = maps:get(from_x, M, undefined),
        from_y = maps:get(from_y, M, undefined),
        destination_facility_id = maps:get(destination_facility_id, M, undefined),
        tow_distance_m = maps:get(tow_distance_m, M, undefined),
        tow_cents = maps:get(tow_cents, M, undefined),
        towed_at = maps:get(towed_at, M, undefined)}.

from_bin(Id, M) ->
    #vehicle_towed_v1{
        vehicle_id = Id,
        plate       = maps:get(plate, M, undefined),
        company_id = maps:get(<<"company_id">>, M, undefined),
        tow_truck_id = maps:get(<<"tow_truck_id">>, M, undefined),
        from_x = maps:get(<<"from_x">>, M, undefined),
        from_y = maps:get(<<"from_y">>, M, undefined),
        destination_facility_id = maps:get(<<"destination_facility_id">>, M, undefined),
        tow_distance_m = maps:get(<<"tow_distance_m">>, M, undefined),
        tow_cents = maps:get(<<"tow_cents">>, M, undefined),
        towed_at = maps:get(<<"towed_at">>, M, undefined)}.

-spec to_map(t()) -> map().
to_map(#vehicle_towed_v1{} = E) ->
    #{event_type              => <<"vehicle_towed">>,
      vehicle_id              => E#vehicle_towed_v1.vehicle_id,
      plate              => E#vehicle_towed_v1.plate,
      company_id              => E#vehicle_towed_v1.company_id,
      tow_truck_id            => E#vehicle_towed_v1.tow_truck_id,
      from_x                  => E#vehicle_towed_v1.from_x,
      from_y                  => E#vehicle_towed_v1.from_y,
      destination_facility_id => E#vehicle_towed_v1.destination_facility_id,
      tow_distance_m          => E#vehicle_towed_v1.tow_distance_m,
      tow_cents               => E#vehicle_towed_v1.tow_cents,
      towed_at                => E#vehicle_towed_v1.towed_at}.

get_vehicle_id(#vehicle_towed_v1{vehicle_id = V}) -> V.
get_company_id(#vehicle_towed_v1{company_id = V}) -> V.
get_tow_truck_id(#vehicle_towed_v1{tow_truck_id = V}) -> V.
get_from_x(#vehicle_towed_v1{from_x = V}) -> V.
get_from_y(#vehicle_towed_v1{from_y = V}) -> V.
get_destination_facility_id(#vehicle_towed_v1{destination_facility_id = V}) -> V.
get_tow_distance_m(#vehicle_towed_v1{tow_distance_m = V}) -> V.
get_tow_cents(#vehicle_towed_v1{tow_cents = V}) -> V.
get_towed_at(#vehicle_towed_v1{towed_at = V}) -> V.
