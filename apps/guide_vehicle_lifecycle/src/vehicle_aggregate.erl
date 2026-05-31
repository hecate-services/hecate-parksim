%%% @doc Vehicle (robotaxi) aggregate.
%%%
%%% Stream: `vehicle-<vehicle_id>`.
%%% Store:  derived from TENANT_ID (= operator/company) at boot, see
%%%         hecate_parksim_service.
%%%
%%% A vehicle is the persistent, identity-bearing entity that lives for its
%%% whole operating life, cycling through phases (commission -> cruise ->
%%% dispatch -> trip -> ... -> dock -> service -> release -> cruise). Trips
%%% are events ON the vehicle stream, not a separate aggregate.
-module(vehicle_aggregate).
-behaviour(evoq_aggregate).

-include("vehicle_state.hrl").

-export([state_module/0, init/1, execute/2, apply/2]).
-export([stream_id/1]).

-type state() :: #vehicle_state{}.
-export_type([state/0]).

-spec state_module() -> module().
state_module() -> vehicle_state.

%% @doc The reckon-db stream id for a vehicle.
%%
%% reckon-db rejects stream ids that don't match `^[a-z]{1,32}-[a-f0-9]{32}$'
%% (`reckon_gater_stream_id'), so the human vehicle id ("leuven-taxi-1") cannot
%% be used as the evoq AggregateId == stream id directly — every dispatch then
%% returns `{error, {invalid_stream_id, malformed_user_id, _}}', which the fleet
%% brain swallows, so no vehicle events persist and the read model stays empty.
%%
%% Derive a STABLE, compliant id as `veh-<md5(vehicle_id)>' (md5 = 16 bytes =
%% exactly 32 lowercase hex). Deterministic, so every command for a vehicle
%% lands on the SAME store stream without threading an extra id through
%% commands/events; the human `vehicle_id' stays in each event payload, which
%% is what the read model and telemetry key on.
-spec stream_id(binary()) -> binary().
stream_id(VehicleId) when is_binary(VehicleId) ->
    Hex = binary:encode_hex(crypto:hash(md5, VehicleId), lowercase),
    <<"veh-", Hex/binary>>.

-spec init(binary()) -> {ok, state()}.
init(AggregateId) ->
    {ok, vehicle_state:new(AggregateId)}.

-spec execute(state(), map()) -> {ok, [map()]} | {error, term()}.
execute(State, #{command_type := <<"commission_vehicle">>} = P) ->
    route(commission_vehicle_v1, maybe_commission_vehicle, State, P);
execute(State, #{command_type := <<"dispatch_vehicle">>} = P) ->
    route(dispatch_vehicle_v1, maybe_dispatch_vehicle, State, P);
execute(State, #{command_type := <<"pick_up_passenger">>} = P) ->
    route(pick_up_passenger_v1, maybe_pick_up_passenger, State, P);
execute(State, #{command_type := <<"drop_off_passenger">>} = P) ->
    route(drop_off_passenger_v1, maybe_drop_off_passenger, State, P);
execute(State, #{command_type := <<"return_vehicle">>} = P) ->
    route(return_vehicle_v1, maybe_return_vehicle, State, P);
execute(State, #{command_type := <<"dock_at_facility">>} = P) ->
    route(dock_at_facility_v1, maybe_dock_at_facility, State, P);
execute(State, #{command_type := <<"service_vehicle">>} = P) ->
    route(service_vehicle_v1, maybe_service_vehicle, State, P);
execute(State, #{command_type := <<"release_vehicle">>} = P) ->
    route(release_vehicle_v1, maybe_release_vehicle, State, P);
execute(State, #{command_type := <<"deplete_battery">>} = P) ->
    route(deplete_battery_v1, maybe_deplete_battery, State, P);
execute(_State, #{command_type := Other}) ->
    {error, {unhandled_command, Other}};
execute(_State, _Payload) ->
    {error, missing_command_type}.

%% Each handler returns already-serialised event maps (some desks emit more
%% than one event, e.g. drop_off -> dropped_off + fare_collected), so the
%% handler owns the to_map/1 conversion. Aggregate just threads them.
route(CmdMod, HandlerMod, State, Payload) ->
    case CmdMod:from_map(Payload) of
        {ok, Cmd}      -> HandlerMod:handle(Cmd, State);
        {error, _} = E -> E
    end.

%% Delegate state folding to the state module.
-spec apply(state(), map()) -> state().
apply(State, Event) ->
    vehicle_state:apply_event(State, Event).
