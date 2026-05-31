%%% @doc Command `commission_vehicle_v1`. Birth slip — a robotaxi joins
%%% the operator's fleet (full battery, parked at its home depot).
-module(commission_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_company_id/1, get_battery_pct/1,
         get_x/1, get_y/1, get_commissioned_at/1]).

-record(commission_vehicle_v1, {
    vehicle_id      :: binary() | undefined,
    company_id      :: binary() | undefined,
    battery_pct     :: number() | undefined,
    x             :: number() | undefined,
    y             :: number() | undefined,
    commissioned_at :: binary() | undefined
}).

-opaque t() :: #commission_vehicle_v1{}.
-export_type([t/0]).

command_type() -> commission_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, #commission_vehicle_v1{
        vehicle_id      = Id,
        company_id      = maps:get(company_id, P, undefined),
        battery_pct     = maps:get(battery_pct, P, 100),
        x             = maps:get(x, P, undefined),
        y             = maps:get(y, P, undefined),
        commissioned_at = maps:get(commissioned_at, P, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) ->
    {ok, #commission_vehicle_v1{
        vehicle_id      = Id,
        company_id      = maps:get(<<"company_id">>, M, undefined),
        battery_pct     = maps:get(<<"battery_pct">>, M, 100),
        x             = maps:get(<<"x">>, M, undefined),
        y             = maps:get(<<"y">>, M, undefined),
        commissioned_at = maps:get(<<"commissioned_at">>, M, undefined)
    }};
from_map(#{vehicle_id := Id} = M) ->
    {ok, #commission_vehicle_v1{
        vehicle_id      = Id,
        company_id      = maps:get(company_id, M, undefined),
        battery_pct     = maps:get(battery_pct, M, 100),
        x             = maps:get(x, M, undefined),
        y             = maps:get(y, M, undefined),
        commissioned_at = maps:get(commissioned_at, M, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#commission_vehicle_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(#commission_vehicle_v1{company_id = undefined}) -> {error, missing_company_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#commission_vehicle_v1{} = C) ->
    #{command_type    => <<"commission_vehicle">>,
      vehicle_id      => C#commission_vehicle_v1.vehicle_id,
      company_id      => C#commission_vehicle_v1.company_id,
      battery_pct     => C#commission_vehicle_v1.battery_pct,
      x             => C#commission_vehicle_v1.x,
      y             => C#commission_vehicle_v1.y,
      commissioned_at => C#commission_vehicle_v1.commissioned_at}.

-spec stream_id(t()) -> binary().
stream_id(#commission_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#commission_vehicle_v1{vehicle_id = V})           -> V.
get_company_id(#commission_vehicle_v1{company_id = V})           -> V.
get_battery_pct(#commission_vehicle_v1{battery_pct = V})         -> V.
get_x(#commission_vehicle_v1{x = V})                         -> V.
get_y(#commission_vehicle_v1{y = V})                         -> V.
get_commissioned_at(#commission_vehicle_v1{commissioned_at = V}) -> V.
