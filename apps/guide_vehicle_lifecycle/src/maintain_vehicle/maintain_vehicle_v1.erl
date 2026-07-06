%%% @doc Command `maintain_vehicle_v1`. Perform scheduled mechanical
%%% maintenance on a docked vehicle. Split out of `service_vehicle_v1`
%%% (kind=maintain) so maintenance is a first-class fact.
-module(maintain_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_maintained_at/1]).

-record(maintain_vehicle_v1, {
    vehicle_id    :: binary() | undefined,
    plate       :: binary() | undefined,
    maintained_at :: binary() | undefined
}).

-opaque t() :: #maintain_vehicle_v1{}.
-export_type([t/0]).

command_type() -> maintain_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #maintain_vehicle_v1{vehicle_id = Id,
                              maintained_at = maps:get(maintained_at, P, undefined)}};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #maintain_vehicle_v1{vehicle_id = Id,
                              maintained_at = maps:get(<<"maintained_at">>, M, undefined)}};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #maintain_vehicle_v1{vehicle_id = Id,
                              maintained_at = maps:get(maintained_at, M, undefined)}};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#maintain_vehicle_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(#maintain_vehicle_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#maintain_vehicle_v1{} = C) ->
    #{command_type  => <<"maintain_vehicle">>,
      vehicle_id    => C#maintain_vehicle_v1.vehicle_id,
      plate    => C#maintain_vehicle_v1.plate,
      maintained_at => C#maintain_vehicle_v1.maintained_at}.

-spec stream_id(t()) -> binary().
stream_id(#maintain_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#maintain_vehicle_v1{vehicle_id = V})       -> V.
get_maintained_at(#maintain_vehicle_v1{maintained_at = V}) -> V.
