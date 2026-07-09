%%% @doc Charging-session aggregate — one EV charging session's lifecycle.
%%%
%%% Stream: `charging-<md5(session_id)>'. Store derived from TENANT_ID at boot
%%% (see hecate_parksim_service).
%%%
%%% The highest-frequency process in a real EV fleet: a vehicle charges several
%%% times a sim-day, and the per-SoC `charging_progressed' milestones make it a
%%% genuinely dense stream. Sibling to `vehicle_aggregate' (what the CAR is) and
%%% `ride_aggregate' (what the CUSTOMER experiences): this models the ENERGY
%%% process, scheduled by the mesh grid-price signal (see the
%%% `on_grid_price_changed_schedule_charging' process manager).
-module(charging_aggregate).
-behaviour(evoq_aggregate).

-include("charging_state.hrl").

-export([state_module/0, init/1, execute/2, apply/2]).
-export([stream_id/1]).

-type state() :: #charging_state{}.
-export_type([state/0]).

-spec state_module() -> module().
state_module() -> charging_state.

%% @doc The reckon-db stream id for a charging session. reckon-db requires
%% `^[a-z]{1,32}-[a-f0-9]{32}$', so derive a stable compliant id as
%% `charging-<md5(session_id)>'. The human `session_id' stays in each event
%% payload (what the read model + telemetry key on).
-spec stream_id(binary()) -> binary().
stream_id(SessionId) when is_binary(SessionId) ->
    Hex = binary:encode_hex(crypto:hash(md5, SessionId), lowercase),
    <<"charging-", Hex/binary>>.

-spec init(binary()) -> {ok, state()}.
init(AggregateId) ->
    {ok, charging_state:new(AggregateId)}.

-spec execute(state(), map()) -> {ok, [map()]} | {error, term()}.
execute(State, #{command_type := <<"request_charge">>} = P) ->
    route(request_charge_v1, maybe_request_charge, State, P);
execute(State, #{command_type := <<"start_charging">>} = P) ->
    route(start_charging_v1, maybe_start_charging, State, P);
execute(State, #{command_type := <<"progress_charging">>} = P) ->
    route(progress_charging_v1, maybe_progress_charging, State, P);
execute(State, #{command_type := <<"complete_charging">>} = P) ->
    route(complete_charging_v1, maybe_complete_charging, State, P);
execute(State, #{command_type := <<"settle_energy">>} = P) ->
    route(settle_energy_v1, maybe_settle_energy, State, P);
execute(_State, #{command_type := Other}) ->
    {error, {unhandled_command, Other}};
execute(_State, _Payload) ->
    {error, missing_command_type}.

route(CmdMod, HandlerMod, State, Payload) ->
    case CmdMod:from_map(Payload) of
        {ok, Cmd}      -> HandlerMod:handle(Cmd, State);
        {error, _} = E -> E
    end.

-spec apply(state(), map()) -> state().
apply(State, Event) ->
    charging_state:apply_event(State, Event).
