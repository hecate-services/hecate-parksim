%%% @doc Command `return_vehicle_v1`. Pull an available vehicle off the
%%% market and send it to a facility (battery low or service due). The
%%% vehicle leaves the revenue pool and heads to `facility_id`.
-module(return_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_facility_id/1, get_returning_at/1]).

-record(return_vehicle_v1, {
    vehicle_id   :: binary() | undefined,
    plate       :: binary() | undefined,
    facility_id  :: binary() | undefined,
    returning_at :: binary() | undefined
}).

-opaque t() :: #return_vehicle_v1{}.
-export_type([t/0]).

command_type() -> return_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #return_vehicle_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, P, undefined),
        facility_id  = maps:get(facility_id, P, undefined),
        returning_at = maps:get(returning_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #return_vehicle_v1{
        vehicle_id   = Id,
        plate       = maps:get(<<"plate">>, M, undefined),
        facility_id  = maps:get(<<"facility_id">>, M, undefined),
        returning_at = maps:get(<<"returning_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #return_vehicle_v1{
        vehicle_id   = Id,
        plate       = maps:get(plate, M, undefined),
        facility_id  = maps:get(facility_id, M, undefined),
        returning_at = maps:get(returning_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#return_vehicle_v1{vehicle_id = undefined})  -> {error, missing_aggregate_id};
validate(#return_vehicle_v1{facility_id = undefined}) -> {error, missing_facility_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#return_vehicle_v1{} = C) ->
    #{command_type => <<"return_vehicle">>,
      vehicle_id   => C#return_vehicle_v1.vehicle_id,
      plate   => C#return_vehicle_v1.plate,
      facility_id  => C#return_vehicle_v1.facility_id,
      returning_at => C#return_vehicle_v1.returning_at}.

-spec stream_id(t()) -> binary().
stream_id(#return_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#return_vehicle_v1{vehicle_id = V})     -> V.
get_facility_id(#return_vehicle_v1{facility_id = V})   -> V.
get_returning_at(#return_vehicle_v1{returning_at = V}) -> V.
