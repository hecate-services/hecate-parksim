%%% @doc Command `service_vehicle_v1`. Perform a physical service on a docked
%%% vehicle: `kind` is clean | maintain. (Charging was split out into its own
%%% `charge_battery_v1` / `battery_charged_v1` slice — a charge is far and away
%%% the most frequent facility visit, so it earns a first-class fact. clean +
%%% maintain will follow in the full split.)
-module(service_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_kind/1, get_battery_pct/1, get_serviced_at/1]).

-record(service_vehicle_v1, {
    vehicle_id  :: binary() | undefined,
    kind        :: binary() | undefined,   %% charge | clean | maintain
    battery_pct :: number() | undefined,
    serviced_at :: binary() | undefined
}).

-opaque t() :: #service_vehicle_v1{}.
-export_type([t/0]).

command_type() -> service_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #service_vehicle_v1{
        vehicle_id  = Id,
        kind        = maps:get(kind, P, undefined),
        battery_pct = maps:get(battery_pct, P, undefined),
        serviced_at = maps:get(serviced_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #service_vehicle_v1{
        vehicle_id  = Id,
        kind        = maps:get(<<"kind">>, M, undefined),
        battery_pct = maps:get(<<"battery_pct">>, M, undefined),
        serviced_at = maps:get(<<"serviced_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #service_vehicle_v1{
        vehicle_id  = Id,
        kind        = maps:get(kind, M, undefined),
        battery_pct = maps:get(battery_pct, M, undefined),
        serviced_at = maps:get(serviced_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#service_vehicle_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(#service_vehicle_v1{kind = undefined})       -> {error, missing_service_kind};
validate(#service_vehicle_v1{kind = K})
  when K =:= <<"clean">>; K =:= <<"maintain">> -> ok;
validate(#service_vehicle_v1{}) -> {error, invalid_service_kind}.

-spec to_map(t()) -> map().
to_map(#service_vehicle_v1{} = C) ->
    #{command_type => <<"service_vehicle">>,
      vehicle_id   => C#service_vehicle_v1.vehicle_id,
      kind         => C#service_vehicle_v1.kind,
      battery_pct  => C#service_vehicle_v1.battery_pct,
      serviced_at  => C#service_vehicle_v1.serviced_at}.

-spec stream_id(t()) -> binary().
stream_id(#service_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#service_vehicle_v1{vehicle_id = V})   -> V.
get_kind(#service_vehicle_v1{kind = V})               -> V.
get_battery_pct(#service_vehicle_v1{battery_pct = V}) -> V.
get_serviced_at(#service_vehicle_v1{serviced_at = V}) -> V.
