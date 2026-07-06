%%% @doc Tests for the fleet SOURCE port (`parksim_fleet_source').
%%%
%%% Proves two things: (1) the simulation conforms to the port — init yields
%%% commissioning intents, poll advances and yields more intents, snapshot/rides
%%% expose the live fleet; (2) the port is implementable by a NON-sim source —
%%% an in-test fake feed emits canned intents through the same contract. That is
%%% the seam: swap the source, the intent vocabulary (and the domain) is
%%% unchanged.
-module(simulate_fleet_source_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("parksim_simulator/include/fleet.hrl").

op() ->
    #operator{id = <<"test">>, name = <<"Test">>, color = <<"#fff">>,
              home = <<"facility-leuven">>, fleet_size = 2}.

%% The behaviour declares exactly the four callbacks a source must provide.
port_declares_the_contract_test() ->
    CBs = parksim_fleet_source:behaviour_info(callbacks),
    ?assertEqual(lists:sort([{init,2}, {poll,3}, {snapshot,1}, {rides,1}]),
                 lists:sort(CBs)).

%% The simulation implements the port: init commissions the fleet.
sim_init_yields_commission_intents_test() ->
    {ok, St, Initial} = simulate_fleet_source:init(op(), fleet_config:params()),
    ?assertEqual([commission_vehicle, commission_vehicle],
                 [Cmd || {Cmd, _} <- Initial]),
    %% snapshot exposes the commissioned fleet; no rides waiting yet.
    ?assertEqual(2, length(simulate_fleet_source:snapshot(St))),
    ?assertEqual([], simulate_fleet_source:rides(St)).

%% A poll advances the fleet one instant and threads the source state.
sim_poll_advances_and_threads_state_test() ->
    {ok, St0, _} = simulate_fleet_source:init(op(), fleet_config:params()),
    {Effects, St1} = simulate_fleet_source:poll(43200, 60, St0),
    ?assert(is_list(Effects)),
    %% state is opaque but distinct instances; snapshot still returns the fleet
    ?assertEqual(2, length(simulate_fleet_source:snapshot(St1))),
    {_Effects2, St2} = simulate_fleet_source:poll(43260, 60, St1),
    ?assertEqual(2, length(simulate_fleet_source:snapshot(St2))).

%% A non-sim source (a fake live feed) satisfies the same port: it drains a
%% queue of pre-recorded intents. The runner would dispatch these identically.
fake_feed_source_conforms_test() ->
    Queued = [{pick_up_passenger, #{ride_id => <<"r1">>}},
              {complete_ride, #{ride_id => <<"r1">>, fare_cents => 700}}],
    {ok, St0, Initial} = fake_feed:init(op(), #{queue => Queued}),
    ?assertEqual([], Initial),
    {Batch1, St1} = fake_feed:poll(1, 1, St0),
    ?assertEqual([{pick_up_passenger, #{ride_id => <<"r1">>}}], Batch1),
    {Batch2, St2} = fake_feed:poll(2, 1, St1),
    ?assertEqual([{complete_ride, #{ride_id => <<"r1">>, fare_cents => 700}}], Batch2),
    {Batch3, _St3} = fake_feed:poll(3, 1, St2),
    ?assertEqual([], Batch3).
