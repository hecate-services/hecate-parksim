%%% @doc Event `ride_assigned_v1`. A cab is on its way to the pickup.
-module(ride_assigned_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_vehicle_id/1, get_assigned_at/1]).

-record(ride_assigned_v1, {
    ride_id     :: binary() | undefined,
    vehicle_id  :: binary() | undefined,
    assigned_at :: binary() | undefined
}).

-opaque t() :: #ride_assigned_v1{}.
-export_type([t/0]).

event_type() -> ride_assigned_v1.

-spec new(map()) -> {ok, t()}.
new(#{ride_id := Id} = P) ->
    {ok, #ride_assigned_v1{ride_id = Id,
                           vehicle_id = maps:get(vehicle_id, P, undefined),
                           assigned_at = maps:get(assigned_at, P, undefined)}}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, #ride_assigned_v1{ride_id = Id,
                           vehicle_id = maps:get(<<"vehicle_id">>, M, undefined),
                           assigned_at = maps:get(<<"assigned_at">>, M, undefined)}};
from_map(#{ride_id := Id} = M) ->
    {ok, #ride_assigned_v1{ride_id = Id,
                           vehicle_id = maps:get(vehicle_id, M, undefined),
                           assigned_at = maps:get(assigned_at, M, undefined)}}.

-spec to_map(t()) -> map().
to_map(#ride_assigned_v1{} = E) ->
    #{event_type  => <<"ride_assigned">>,
      ride_id     => E#ride_assigned_v1.ride_id,
      vehicle_id  => E#ride_assigned_v1.vehicle_id,
      assigned_at => E#ride_assigned_v1.assigned_at}.

get_ride_id(#ride_assigned_v1{ride_id = V})         -> V.
get_vehicle_id(#ride_assigned_v1{vehicle_id = V})   -> V.
get_assigned_at(#ride_assigned_v1{assigned_at = V}) -> V.
