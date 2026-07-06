%%% @doc Command `clean_vehicle_v1`. Clean a docked vehicle (cosmetic
%%% service). Split out of `service_vehicle_v1` (kind=clean) so a clean is a
%%% first-class fact in the event log / By-Event-Type / mesh.
-module(clean_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_cleaned_at/1]).

-record(clean_vehicle_v1, {
    vehicle_id :: binary() | undefined,
    plate       :: binary() | undefined,
    cleaned_at :: binary() | undefined
}).

-opaque t() :: #clean_vehicle_v1{}.
-export_type([t/0]).

command_type() -> clean_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #clean_vehicle_v1{vehicle_id = Id,
                           cleaned_at = maps:get(cleaned_at, P, undefined)}};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #clean_vehicle_v1{vehicle_id = Id,
                           cleaned_at = maps:get(<<"cleaned_at">>, M, undefined)}};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #clean_vehicle_v1{vehicle_id = Id,
                           cleaned_at = maps:get(cleaned_at, M, undefined)}};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#clean_vehicle_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(#clean_vehicle_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#clean_vehicle_v1{} = C) ->
    #{command_type => <<"clean_vehicle">>,
      vehicle_id   => C#clean_vehicle_v1.vehicle_id,
      plate   => C#clean_vehicle_v1.plate,
      cleaned_at   => C#clean_vehicle_v1.cleaned_at}.

-spec stream_id(t()) -> binary().
stream_id(#clean_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#clean_vehicle_v1{vehicle_id = V}) -> V.
get_cleaned_at(#clean_vehicle_v1{cleaned_at = V}) -> V.
