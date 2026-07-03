%%% @doc eunit tests for the pure robotaxi fleet brain.
%%%
%%% Drives the pure core with a STUB router (no OSRM, no I/O) and asserts the
%%% phase transitions + the milestone command effects produced. The core is
%%% deterministic given an rng + stub route, so these are exact assertions.
-module(simulate_fleet_core_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("parksim_simulator/include/fleet.hrl").

%% Stub: a single-waypoint path straight to the target, short distance — so
%% one tick always completes the leg.
route(_From, To) -> {[To], 100.0}.

op() ->
    #operator{id = <<"test">>, name = <<"Test">>, color = <<"#fff">>,
              home = <<"facility-leuven">>, fleet_size = 1}.

cmds(Effects) -> [C || {C, _} <- Effects].

phase(Core) -> maps:get(phase, hd(simulate_fleet_core:snapshot(Core))).
battery(Core) -> maps:get(battery_pct, hd(simulate_fleet_core:snapshot(Core))).

%% A full fare: commission -> dispatch -> pickup -> dropoff(+fare).
full_fare_test() ->
    {C0, Comm} = simulate_fleet_core:new(op(), fleet_config:params(),
                                         rand:seed_s(exsss, {1,2,3})),
    ?assertEqual([commission_vehicle], cmds(Comm)),
    ?assertEqual(commissioned, phase(C0)),

    Req = #ride_request{id = <<"r1">>, pickup = {50.879, 4.701},
                        dropoff = {50.876, 4.700}, created = 0},
    {C1, _, E1} = simulate_fleet_core:tick(C0, 43200, 1000.0, [Req], fun route/2),
    ?assertEqual([request_ride, assign_ride, dispatch_vehicle], cmds(E1)),
    ?assertEqual(dispatched, phase(C1)),

    {C2, _, E2} = simulate_fleet_core:tick(C1, 43260, 1000.0, [], fun route/2),
    ?assertEqual([start_ride, pick_up_passenger], cmds(E2)),
    ?assertEqual(on_trip, phase(C2)),

    {C3, _, E3} = simulate_fleet_core:tick(C2, 43320, 1000.0, [], fun route/2),
    ?assertEqual([complete_ride, drop_off_passenger], cmds(E3)),
    ?assertEqual(cruising, phase(C3)).

%% Forced return -> dock+service -> release restores a full charge.
service_cycle_test() ->
    P = maps:put(return_threshold_pct, 200, fleet_config:params()),  %% always return
    {C0, _} = simulate_fleet_core:new(op(), P, rand:seed_s(exsss, {1,2,3})),
    {C1, _, E1} = simulate_fleet_core:tick(C0, 43200, 1000.0, [], fun route/2),
    ?assertEqual([return_vehicle], cmds(E1)),
    ?assertEqual(returning, phase(C1)),

    {C2, _, E2} = simulate_fleet_core:tick(C1, 43260, 1000.0, [], fun route/2),
    %% Low battery is the return reason, so the facility visit charges —
    %% charge_battery now, not the generic service_vehicle.
    ?assertEqual([dock_at_facility, charge_battery], cmds(E2)),
    ?assertEqual(servicing, phase(C2)),

    %% advance past service_until (charge = 1800 sim s)
    {C3, _, E3} = simulate_fleet_core:tick(C2, 43260 + 5000, 5000.0, [], fun route/2),
    ?assertEqual([release_vehicle], cmds(E3)),
    ?assertEqual(cruising, phase(C3)),
    ?assertEqual(100.0, battery(C3)).

%% Battery hitting zero mid-leg strands the vehicle.
depletion_test() ->
    P = maps:put(battery_drain_per_km, 100000, fleet_config:params()),  %% absurd drain
    {C0, _} = simulate_fleet_core:new(op(), P, rand:seed_s(exsss, {1,2,3})),
    Req = #ride_request{id = <<"rc">>, pickup = {50.879, 4.701},
                        dropoff = {50.876, 4.700}, created = 0},
    {C1, _, _} = simulate_fleet_core:tick(C0, 43200, 1000.0, [Req], fun route/2),
    {C2, _, E2} = simulate_fleet_core:tick(C1, 43260, 1000.0, [], fun route/2),
    ?assert(lists:member(deplete_battery, cmds(E2))),
    ?assertEqual(depleted, phase(C2)).

%% Demand follows a day/night curve: peak hour >> small hours.
demand_curve_test() ->
    Rng = rand:seed_s(exsss, {7,7,7}),
    P = fleet_config:params(),
    {Peak, _}  = simulate_demand:requests(8 * 3600 + 1800, 3600, P, Rng),
    {Night, _} = simulate_demand:requests(3 * 3600, 3600, P, Rng),
    ?assert(length(Peak) > length(Night) * 3).
