%%% @doc The SIMULATION source — the default `parksim_fleet_source'.
%%%
%%% Wraps the pure kinematic brain (`simulate_fleet_core') and the demand
%%% generator (`simulate_demand') behind the source port. Each `poll/3'
%%% fabricates the demand for the instant, advances every vehicle one step with
%%% real OSRM routing (`route_leg'), and returns the milestone intents the brain
%%% produced. Swap this module for a real-feed implementation (via the
%%% `fleet_source' param) and the domain is unchanged — see
%%% `parksim_fleet_source'.
-module(simulate_fleet_source).
-behaviour(parksim_fleet_source).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([init/2, poll/3, snapshot/1, rides/1]).

-record(sim, {
    core   :: simulate_fleet_core:t(),
    rng    :: rand:state(),
    params :: map()
}).

init(#operator{} = Op, Params) ->
    Seed = erlang:phash2(Op#operator.id),
    Rng0 = rand:seed_s(exsss, {Seed, Seed bsl 1, Seed bsl 2}),
    {Core, CommissionEffects} = simulate_fleet_core:new(Op, Params, Rng0),
    {ok, #sim{core = Core, rng = Rng0, params = Params}, CommissionEffects}.

poll(SimUnix, TickSecs, #sim{core = Core0, rng = Rng0, params = Params} = S) ->
    {Reqs, Rng1} = simulate_demand:requests(SimUnix, TickSecs, Params, Rng0),
    {Core1, _N, Effects} =
        simulate_fleet_core:tick(Core0, SimUnix, TickSecs, Reqs, fun route/2),
    {Effects, S#sim{core = Core1, rng = Rng1}}.

snapshot(#sim{core = Core}) -> simulate_fleet_core:snapshot(Core).
rides(#sim{core = Core})    -> simulate_fleet_core:rides(Core).

%% Real OSRM routing (the sim's one live dependency): coordinate pair -> the
%% polyline the brain walks and its length in metres.
route(From, To) ->
    Leg = route_leg:route(From, To),
    {maps:get(polyline, Leg), maps:get(distance_m, Leg)}.
