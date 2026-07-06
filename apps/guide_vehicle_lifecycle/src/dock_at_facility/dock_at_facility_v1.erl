%%% @doc Command `dock_at_facility_v1`. A returning robotaxi takes a free
%%% bay at a service facility. The fleet brain allocates the bay (global
%%% view), so no distributed contention here.
%%%
%%% Named with the `_at_facility` suffix to distinguish from the
%%% parking-session `dock_vehicle_v1` (a car taking a parking bay) — Erlang
%%% module names are global.
-module(dock_at_facility_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_facility_id/1, get_bay_id/1, get_x/1,
         get_y/1, get_docked_at/1]).

-record(dock_at_facility_v1, {
    vehicle_id  :: binary() | undefined,
    plate       :: binary() | undefined,
    facility_id :: binary() | undefined,
    bay_id      :: binary() | undefined,
    x         :: number() | undefined,
    y         :: number() | undefined,
    docked_at   :: binary() | undefined
}).

-opaque t() :: #dock_at_facility_v1{}.
-export_type([t/0]).

command_type() -> dock_at_facility_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #dock_at_facility_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, P, undefined),
        facility_id = maps:get(facility_id, P, undefined),
        bay_id      = maps:get(bay_id, P, undefined),
        x         = maps:get(x, P, undefined),
        y         = maps:get(y, P, undefined),
        docked_at   = maps:get(docked_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #dock_at_facility_v1{
        vehicle_id  = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        facility_id = maps:get(<<"facility_id">>, M, undefined),
        bay_id      = maps:get(<<"bay_id">>, M, undefined),
        x         = maps:get(<<"x">>, M, undefined),
        y         = maps:get(<<"y">>, M, undefined),
        docked_at   = maps:get(<<"docked_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #dock_at_facility_v1{
        vehicle_id  = Id,
        plate       = maps:get(plate, M, undefined),
        facility_id = maps:get(facility_id, M, undefined),
        bay_id      = maps:get(bay_id, M, undefined),
        x         = maps:get(x, M, undefined),
        y         = maps:get(y, M, undefined),
        docked_at   = maps:get(docked_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#dock_at_facility_v1{vehicle_id = undefined})  -> {error, missing_aggregate_id};
validate(#dock_at_facility_v1{facility_id = undefined}) -> {error, missing_facility_id};
validate(#dock_at_facility_v1{bay_id = undefined})      -> {error, missing_bay_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#dock_at_facility_v1{} = C) ->
    #{command_type => <<"dock_at_facility">>,
      vehicle_id   => C#dock_at_facility_v1.vehicle_id,
      plate   => C#dock_at_facility_v1.plate,
      facility_id  => C#dock_at_facility_v1.facility_id,
      bay_id       => C#dock_at_facility_v1.bay_id,
      x          => C#dock_at_facility_v1.x,
      y          => C#dock_at_facility_v1.y,
      docked_at    => C#dock_at_facility_v1.docked_at}.

-spec stream_id(t()) -> binary().
stream_id(#dock_at_facility_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#dock_at_facility_v1{vehicle_id = V})   -> V.
get_facility_id(#dock_at_facility_v1{facility_id = V}) -> V.
get_bay_id(#dock_at_facility_v1{bay_id = V})           -> V.
get_x(#dock_at_facility_v1{x = V})                 -> V.
get_y(#dock_at_facility_v1{y = V})                 -> V.
get_docked_at(#dock_at_facility_v1{docked_at = V})     -> V.
