%%% @doc Command `charge_battery_v1`. Top up a docked vehicle's battery.
%%%
%%% Split out of `service_vehicle_v1` (kind=charge) so charging is a
%%% first-class fact: a charge is the fleet's most frequent facility visit
%%% (every trip drains the battery), and modelling it as its own event makes
%%% it legible in the event log / By-Event-Type / mesh instead of hiding
%%% behind a `service_kind` discriminator. `battery_pct` is the restored
%%% level (default 100 — a full top-up).
-module(charge_battery_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_battery_soh_pct/1, get_charge_cycle/1]).
-export([get_vehicle_id/1, get_battery_pct/1, get_charged_at/1]).

-record(charge_battery_v1, {
    vehicle_id  :: binary() | undefined,
    charge_cycle       :: non_neg_integer() | undefined,
    battery_soh_pct       :: number() | undefined,
    plate       :: binary() | undefined,
    battery_pct :: number() | undefined,
    charged_at  :: binary() | undefined
}).

-opaque t() :: #charge_battery_v1{}.
-export_type([t/0]).

command_type() -> charge_battery_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #charge_battery_v1{
        vehicle_id  = Id,
        charge_cycle       = maps:get(charge_cycle, P, undefined),
        battery_soh_pct       = maps:get(battery_soh_pct, P, undefined),
        plate       = maps:get(plate, P, undefined),
        battery_pct = maps:get(battery_pct, P, undefined),
        charged_at  = maps:get(charged_at, P, undefined)
    }};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #charge_battery_v1{
        vehicle_id  = Id,
        charge_cycle       = maps:get(<<"charge_cycle">>, M, undefined),
        battery_soh_pct       = maps:get(<<"battery_soh_pct">>, M, undefined),
        plate       = maps:get(<<"plate">>, M, undefined),
        battery_pct = maps:get(<<"battery_pct">>, M, undefined),
        charged_at  = maps:get(<<"charged_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #charge_battery_v1{
        vehicle_id  = Id,
        charge_cycle       = maps:get(charge_cycle, M, undefined),
        battery_soh_pct       = maps:get(battery_soh_pct, M, undefined),
        plate       = maps:get(plate, M, undefined),
        battery_pct = maps:get(battery_pct, M, undefined),
        charged_at  = maps:get(charged_at, M, undefined)
    }};
from_map(_) -> {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#charge_battery_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(#charge_battery_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#charge_battery_v1{} = C) ->
    #{command_type => <<"charge_battery">>,
      vehicle_id   => C#charge_battery_v1.vehicle_id,
      charge_cycle   => C#charge_battery_v1.charge_cycle,
      battery_soh_pct   => C#charge_battery_v1.battery_soh_pct,
      plate   => C#charge_battery_v1.plate,
      battery_pct  => C#charge_battery_v1.battery_pct,
      charged_at   => C#charge_battery_v1.charged_at}.

-spec stream_id(t()) -> binary().
stream_id(#charge_battery_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#charge_battery_v1{vehicle_id = V})   -> V.
get_battery_pct(#charge_battery_v1{battery_pct = V}) -> V.
get_charged_at(#charge_battery_v1{charged_at = V})   -> V.
get_battery_soh_pct(#charge_battery_v1{battery_soh_pct = V}) -> V.
get_charge_cycle(#charge_battery_v1{charge_cycle = V})       -> V.
