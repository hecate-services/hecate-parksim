%%% @doc The robotaxi fleet brain — one gen_server per node (operator).
%%%
%%% Holds the whole fleet's in-memory kinematic state (via the pure
%%% `simulate_fleet_core'), ticks on a wall timer, and on each tick:
%%%   1. generates new ride requests (`simulate_demand'),
%%%   2. advances every vehicle one step (the pure core, with real OSRM
%%%      routing via `route_leg'),
%%%   3. dispatches the resulting milestone commands into the vehicle
%%%      aggregate (`maybe_*:dispatch/1').
%%%
%%% Position/battery are high-frequency in-memory state; only the sparse
%%% milestones become domain events. `snapshot/0' exposes the live fleet for
%%% the telemetry publisher (step 5) and any inspection.
-module(simulate_fleet).
-behaviour(gen_server).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([start_link/0, snapshot/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {
    core        :: simulate_fleet_core:t(),
    params      :: map(),
    rng         :: rand:state(),
    tick_ms     :: pos_integer(),
    last_sim    :: integer()
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Live per-vehicle snapshot (id, phase, x, y, heading, battery).
-spec snapshot() -> [map()].
snapshot() ->
    gen_server:call(?MODULE, snapshot).

%%--------------------------------------------------------------------

init([]) ->
    Op = fleet_config:operator(),
    Params = fleet_config:params(),
    Seed = erlang:phash2(Op#operator.id),
    Rng0 = rand:seed_s(exsss, {Seed, Seed bsl 1, Seed bsl 2}),
    {Core, CommissionEffects} = simulate_fleet_core:new(Op, Params, Rng0),
    %% Commission the whole fleet up front.
    _ = run_effects(CommissionEffects),
    TickMs = maps:get(tick_ms, Params, 1000),
    erlang:send_after(TickMs, self(), tick),
    {ok, #state{core = Core, params = Params, rng = Rng0,
                tick_ms = TickMs, last_sim = simulate_clock:now_unix()}}.

handle_call(snapshot, _From, #state{core = Core} = S) ->
    {reply, simulate_fleet_core:snapshot(Core), S};
handle_call(_Req, _From, S) ->
    {reply, ok, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info(tick, #state{} = S0) ->
    erlang:send_after(S0#state.tick_ms, self(), tick),
    {noreply, do_tick(S0)};
handle_info(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%--------------------------------------------------------------------

do_tick(#state{core = Core0, params = Params, rng = Rng0, last_sim = Last} = S) ->
    SimUnix = simulate_clock:now_unix(),
    TickSimSecs = max(1, SimUnix - Last),
    Peak = maps:get(peak_requests_per_min, Params, 6.0),
    {Reqs, Rng1} = simulate_demand:requests(SimUnix, TickSimSecs, Peak, Rng0),
    Route = fun(From, To) ->
                Leg = route_leg:route(From, To),
                {maps:get(polyline, Leg), maps:get(distance_m, Leg)}
            end,
    {Core2, _N, Effects} =
        simulate_fleet_core:tick(Core0, SimUnix, TickSimSecs, Reqs, Route),
    _ = run_effects(Effects),
    S#state{core = Core2, rng = Rng1, last_sim = SimUnix}.

%% Dispatch each {Command, Payload} effect into the aggregate. Failures are
%% logged-and-swallowed: a single bad command must not stall the fleet.
run_effects(Effects) ->
    lists:foreach(fun({Cmd, Payload}) ->
        Mod = handler_for(Cmd),
        _ = catch Mod:dispatch(Payload)
    end, Effects).

handler_for(commission_vehicle)  -> maybe_commission_vehicle;
handler_for(dispatch_vehicle)    -> maybe_dispatch_vehicle;
handler_for(pick_up_passenger)   -> maybe_pick_up_passenger;
handler_for(drop_off_passenger)  -> maybe_drop_off_passenger;
handler_for(return_vehicle)      -> maybe_return_vehicle;
handler_for(dock_at_facility)    -> maybe_dock_at_facility;
handler_for(service_vehicle)     -> maybe_service_vehicle;
handler_for(release_vehicle)     -> maybe_release_vehicle;
handler_for(deplete_battery)     -> maybe_deplete_battery.
