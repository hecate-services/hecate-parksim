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

-export([start_link/0, snapshot/0, rides/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {
    core         :: simulate_fleet_core:t(),
    params       :: map(),
    rng          :: rand:state(),
    tick_ms      :: pos_integer(),
    last_sim     :: integer(),
    %% Commissioning is deferred out of init() to the first LEADER tick, and
    %% only latched once the store confirms the writes — otherwise a boot-race
    %% (fleet commissioned on every replica, before the store had an elected
    %% leader) left in-memory state and the store divergent (wrong_expected_
    %% version), needing a manual restart. See ensure_commissioned/1.
    commissioned = false :: boolean(),
    commission_effects = [] :: [{atom(), map()}]
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Live per-vehicle snapshot (id, phase, x, y, heading, battery).
-spec snapshot() -> [map()].
snapshot() ->
    gen_server:call(?MODULE, snapshot).

%% @doc Waiting rides (unassigned requests) at their pickup points.
-spec rides() -> [map()].
rides() ->
    gen_server:call(?MODULE, rides).

%%--------------------------------------------------------------------

init([]) ->
    Op = fleet_config:operator(),
    Params = fleet_config:params(),
    Seed = erlang:phash2(Op#operator.id),
    Rng0 = rand:seed_s(exsss, {Seed, Seed bsl 1, Seed bsl 2}),
    {Core, CommissionEffects} = simulate_fleet_core:new(Op, Params, Rng0),
    %% Do NOT commission here — the store may not have an elected leader yet.
    %% Deferred to the first leader tick (ensure_commissioned/1), which retries
    %% until the writes land, so memory and store never diverge on a boot-race.
    TickMs = maps:get(tick_ms, Params, 1000),
    erlang:send_after(TickMs, self(), tick),
    {ok, #state{core = Core, params = Params, rng = Rng0,
                tick_ms = TickMs, last_sim = simulate_clock:now_unix(),
                commission_effects = CommissionEffects}}.

handle_call(snapshot, _From, #state{core = Core} = S) ->
    {reply, simulate_fleet_core:snapshot(Core), S};
handle_call(rides, _From, #state{core = Core} = S) ->
    {reply, simulate_fleet_core:rides(Core), S};
handle_call(_Req, _From, S) ->
    {reply, ok, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info(tick, #state{} = S0) ->
    erlang:send_after(S0#state.tick_ms, self(), tick),
    %% Follow-the-leader: only the store's Ra leader advances the fleet
    %% and dispatches milestone commands. Followers keep ticking (to
    %% re-check leadership) but do no work.
    %% Only the leader advances the fleet — and only once the fleet is
    %% commissioned (retried here until the store confirms). Advancing before
    %% the commissions land is what produced the wrong_expected_version divergence.
    S1 = case hecate_parksim_service:is_leader() of
             true ->
                 S = ensure_commissioned(S0),
                 case S#state.commissioned of
                     true  -> do_tick(S);
                     false -> S
                 end;
             false -> S0
         end,
    {noreply, S1};
handle_info(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%--------------------------------------------------------------------

do_tick(#state{core = Core0, params = Params, rng = Rng0, last_sim = Last} = S) ->
    SimUnix = simulate_clock:now_unix(),
    TickSimSecs = max(1, SimUnix - Last),
    {Reqs, Rng1} = simulate_demand:requests(SimUnix, TickSimSecs, Params, Rng0),
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
%%
%% Bay DCB checks are performed here (not in the handler) to keep handlers
%% pure and unit-testable — same pattern as parking_session_dcb in simulate_visit.
%% @private Commission the fleet on the first leader tick, retrying until the
%% store confirms every vehicle is present. Idempotent: a vehicle already
%% commissioned by a prior leader counts as success. Only latch `commissioned'
%% when ALL landed — otherwise stay false and retry next tick, so a boot-race
%% (no elected leader yet) can never leave memory ahead of the store.
-spec ensure_commissioned(#state{}) -> #state{}.
ensure_commissioned(#state{commissioned = true} = S) ->
    S;
ensure_commissioned(#state{commission_effects = Effects} = S) ->
    case lists:all(fun commission_ok/1, Effects) of
        true  -> S#state{commissioned = true};
        false -> S
    end.

%% @private A commission succeeded, or the vehicle is already in the store
%% (idempotent). Any store-unavailable outcome (no leader/quorum yet, timeout)
%% returns false so we retry rather than advance past an empty store.
-spec commission_ok({atom(), map()}) -> boolean().
commission_ok({commission_vehicle, Payload}) ->
    case catch maybe_commission_vehicle:dispatch(Payload) of
        {ok, _Version, _Events}                 -> true;
        {error, vehicle_already_commissioned}   -> true;
        {error, {wrong_expected_version, _, _}} -> true;
        _Other                                  -> false
    end;
commission_ok(_Effect) ->
    true.

run_effects(Effects) ->
    StoreId = hecate_parksim_service:store_id(),
    lists:foreach(fun(Effect) -> run_effect(Effect, StoreId) end, Effects).

run_effect({dock_at_facility, #{facility_id := FacId, bay_id := BayId,
                                vehicle_id  := VehicleId,
                                plate := Plate} = Payload}, StoreId) ->
    case vehicle_bay_dcb:claim_bay(StoreId, FacId, BayId, VehicleId, Plate) of
        ok ->
            _ = catch maybe_dock_at_facility:dispatch(Payload);
        {error, Reason} ->
            logger:warning("[parksim] bay ~s/~s already occupied, skipping dock: ~p",
                           [FacId, BayId, Reason])
    end;
run_effect({release_vehicle, #{facility_id := FacId, bay_id := BayId,
                               vehicle_id := VehId, plate := Plate} = Payload},
           StoreId) ->
    _ = catch maybe_release_vehicle:dispatch(Payload),
    _ = vehicle_bay_dcb:release_bay(StoreId, FacId, BayId, VehId, Plate);
run_effect({release_vehicle, Payload}, _StoreId) ->
    %% Fallback: no facility_id/bay_id in payload (e.g. test/manual dispatch).
    _ = catch maybe_release_vehicle:dispatch(Payload);
run_effect({Cmd, Payload}, _StoreId) ->
    Mod = handler_for(Cmd),
    _ = catch Mod:dispatch(Payload).

handler_for(commission_vehicle)  -> maybe_commission_vehicle;
handler_for(dispatch_vehicle)    -> maybe_dispatch_vehicle;
handler_for(pick_up_passenger)   -> maybe_pick_up_passenger;
handler_for(drop_off_passenger)  -> maybe_drop_off_passenger;
handler_for(return_vehicle)      -> maybe_return_vehicle;
handler_for(dock_at_facility)    -> maybe_dock_at_facility;
handler_for(charge_battery)      -> maybe_charge_battery;
handler_for(clean_vehicle)       -> maybe_clean_vehicle;
handler_for(maintain_vehicle)    -> maybe_maintain_vehicle;
handler_for(release_vehicle)     -> maybe_release_vehicle;
handler_for(deplete_battery)     -> maybe_deplete_battery;
handler_for(request_tow)         -> maybe_request_tow;
handler_for(dispatch_tow_truck)  -> maybe_dispatch_tow_truck;
handler_for(tow_vehicle)         -> maybe_tow_vehicle;
handler_for(request_ride)        -> maybe_request_ride;
handler_for(assign_ride)         -> maybe_assign_ride;
handler_for(start_ride)          -> maybe_start_ride;
handler_for(complete_ride)       -> maybe_complete_ride;
handler_for(expire_ride)         -> maybe_expire_ride.
