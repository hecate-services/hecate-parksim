%%% @doc The fleet RUNNER — one gen_server per node (operator).
%%%
%%% Source-agnostic: it owns the tick loop, the leader-gating, and the dispatch
%%% of command intents into the aggregates — but NOT what drives the fleet. That
%%% is a pluggable `parksim_fleet_source' (the `fleet_source' param, default
%%% `simulate_fleet_source'). Each tick, on the store's Ra leader, it:
%%%   1. polls the source for this instant's command intents,
%%%   2. dispatches each intent into its aggregate (`maybe_*:dispatch/1'),
%%%      applying the bay DCB cross-cut where needed.
%%%
%%% The source produces the sparse milestones; only those become domain events.
%%% Position/battery live only in the source's in-memory state. `snapshot/0'
%%% exposes the live fleet (via the source) for the telemetry publisher.
%%%
%%% Swapping the source for a real telematics/ANPR/charger/payment feed changes
%%% nothing here or in the domain — see `parksim_fleet_source'.
-module(simulate_fleet).
-behaviour(gen_server).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([start_link/0, snapshot/0, rides/0]).
-ifdef(TEST).
-export([charge_milestones/2]).
-endif.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {
    source_mod   :: module(),
    source       :: term(),
    tick_ms      :: pos_integer(),
    last_sim     :: integer(),
    %% Commissioning is deferred out of init() to the first LEADER tick, and
    %% only latched once the store confirms the writes — otherwise a boot-race
    %% (fleet commissioned on every replica, before the store had an elected
    %% leader) left the source state and the store divergent (wrong_expected_
    %% version), needing a manual restart. See ensure_commissioned/1.
    commissioned = false :: boolean(),
    commission_effects = [] :: [parksim_fleet_source:effect()]
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
    %% Pluggable source: the sim by default, a real feed adapter in production.
    SourceMod = maps:get(fleet_source, Params, simulate_fleet_source),
    {ok, Source, CommissionEffects} = SourceMod:init(Op, Params),
    %% Do NOT commission here — the store may not have an elected leader yet.
    %% Deferred to the first leader tick (ensure_commissioned/1), which retries
    %% until the writes land, so the source and store never diverge on a boot-race.
    TickMs = maps:get(tick_ms, Params, 1000),
    erlang:send_after(TickMs, self(), tick),
    {ok, #state{source_mod = SourceMod, source = Source,
                tick_ms = TickMs, last_sim = simulate_clock:now_unix(),
                commission_effects = CommissionEffects}}.

handle_call(snapshot, _From, #state{source_mod = M, source = Src} = S) ->
    {reply, M:snapshot(Src), S};
handle_call(rides, _From, #state{source_mod = M, source = Src} = S) ->
    {reply, M:rides(Src), S};
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

do_tick(#state{source_mod = M, source = Src0, last_sim = Last} = S) ->
    SimUnix = simulate_clock:now_unix(),
    TickSimSecs = max(1, SimUnix - Last),
    {Effects, Src1} = M:poll(SimUnix, TickSimSecs, Src0),
    _ = run_effects(Effects),
    S#state{source = Src1, last_sim = SimUnix}.

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
run_effect({charge_session, Payload}, _StoreId) ->
    %% Expand the sim's charge descriptor into the full charging PROCESS,
    %% priced by the live regional grid tariff (from the charging PM). One
    %% dense session per charge: request -> start -> progress* -> complete ->
    %% settle. The tariff drives the settled cost + off-peak flag, so the
    %% mesh-propagated price signal is visible in the energy read model.
    run_charge_session(Payload);
run_effect({Cmd, Payload}, _StoreId) ->
    Mod = handler_for(Cmd),
    _ = catch Mod:dispatch(Payload).

run_charge_session(P) ->
    Session = maps:get(session_id, P),
    Vehicle = maps:get(vehicle_id, P),
    Company = maps:get(company_id, P, undefined),
    Before  = maps:get(battery_pct_before, P, 0),
    Energy  = maps:get(energy_kwh, P, 0),
    Tariff  = grid_tariff_cents(),
    _ = catch maybe_request_charge:dispatch(
        #{session_id => Session, vehicle_id => Vehicle, company_id => Company,
          plate => maps:get(plate, P, undefined),
          battery_pct_before => Before, target_pct => maps:get(target_pct, P, 100),
          tariff_cents_per_kwh => Tariff}),
    _ = catch maybe_start_charging:dispatch(
        #{session_id => Session, vehicle_id => Vehicle, company_id => Company,
          charger_id => maps:get(charger_id, P, undefined),
          battery_pct_before => Before, tariff_cents_per_kwh => Tariff}),
    lists:foreach(
        fun({Soc, Delta, Total}) ->
            _ = catch maybe_progress_charging:dispatch(
                #{session_id => Session, vehicle_id => Vehicle,
                  soc_pct => Soc, energy_kwh_delta => Delta,
                  energy_kwh_total => Total})
        end, charge_milestones(Before, Energy)),
    _ = catch maybe_complete_charging:dispatch(
        #{session_id => Session, vehicle_id => Vehicle,
          final_soc_pct => maps:get(target_pct, P, 100), energy_kwh => Energy,
          charge_cycle => maps:get(charge_cycle, P, undefined),
          battery_soh_pct => maps:get(battery_soh_pct, P, undefined)}),
    _ = catch maybe_settle_energy:dispatch(
        #{session_id => Session, vehicle_id => Vehicle, company_id => Company,
          energy_kwh => Energy, tariff_cents_per_kwh => Tariff}),
    ok.

%% SoC checkpoints from the starting charge up to full, with the per-step and
%% cumulative energy — the dense progress stream.
charge_milestones(Before, _Energy) when Before >= 100 -> [];
charge_milestones(Before, Energy) ->
    Span  = max(1, 100 - Before),
    Marks = lists:usort([M || M <- [40, 60, 80], M > Before] ++ [100]),
    {Steps, _} = lists:mapfoldl(
        fun(Soc, Prev) ->
            Total = round(Energy * (Soc - Before) / Span * 10) / 10,
            {{Soc, round((Total - Prev) * 10) / 10, Total}, Total}
        end, 0.0, Marks),
    Steps.

grid_tariff_cents() ->
    case catch on_grid_price_changed_schedule_charging:current_tariff() of
        {ok, Cents, _OffPeak} when is_number(Cents) -> Cents;
        _ -> 26   %% no live signal — shoulder-band fallback
    end.

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
handler_for(cancel_ride)         -> maybe_cancel_ride;
handler_for(issue_refund)        -> maybe_issue_refund;
handler_for(expire_ride)         -> maybe_expire_ride.
