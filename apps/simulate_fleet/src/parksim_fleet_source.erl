%%% @doc The fleet SOURCE port — the seam between "what drives the fleet" and
%%% "the domain the fleet feeds."
%%%
%%% The whole point of parksim: the event-sourced domain (vehicle + ride
%%% aggregates, the operator ledger, the read models) is SOURCE-AGNOSTIC. It
%%% does not care whether a `pick_up_passenger' command came from a simulated
%%% kinematic brain or from a real robotaxi's telematics reporting a geofence
%%% crossing. The difference between the simulation and a real deployment is the
%%% SOURCE, not the domain.
%%%
%%% A source produces a stream of domain command INTENTS — `{Command, Payload}'
%%% pairs — which the runner (`simulate_fleet') dispatches into the aggregates.
%%% The runner owns the tick loop, leader-gating, and dispatch; the source owns
%%% only "what happened in the world this instant."
%%%
%%% Implementations:
%%%   - `simulate_fleet_source' — the simulation. Generates demand
%%%     (`simulate_demand'), advances a kinematic fleet brain
%%%     (`simulate_fleet_core'), and emits the milestone intents.
%%%   - A REAL deployment implements this same behaviour over live feeds and
%%%     swaps it in via the `fleet_source' param — no domain change:
%%%       * telematics (GPS + trip state)  -> dispatch_vehicle / pick_up_passenger
%%%                                            / drop_off_passenger / start_ride
%%%                                            / complete_ride milestones
%%%       * ANPR cameras at facility gates -> dock_at_facility / release_vehicle
%%%       * charger session telemetry      -> charge_battery (kWh -> cents)
%%%       * payment gateway webhooks       -> payment_captured / issue_refund
%%%       * rider app / dispatch desk      -> request_ride, cancellations
%%%
%%% The intent vocabulary (the `{Command, Payload}' set in
%%% `simulate_fleet:handler_for/1') is the contract both sides share.
-module(parksim_fleet_source).

-include_lib("parksim_simulator/include/fleet.hrl").

-type effect() :: {Command :: atom(), Payload :: map()}.
-export_type([effect/0]).

%% @doc Start the source for one operator. Returns the source's private state
%% plus any INITIAL intents (e.g. commissioning the fleet's vehicles) the runner
%% must land before the first poll — the runner retries these until the store
%% confirms them (boot-race safety), so they must be idempotent.
-callback init(Operator :: #operator{}, Params :: map()) ->
    {ok, State :: term(), InitialEffects :: [effect()]}.

%% @doc Produce the batch of command intents for the world-instant `SimUnix'
%% (a monotonic sim clock second), covering `TickSecs' elapsed sim seconds.
%% Called only on the store's Ra leader, once commissioning has landed.
-callback poll(SimUnix :: integer(), TickSecs :: pos_integer(), State) ->
    {[effect()], State}.

%% @doc Live per-vehicle view (id, phase, x, y, heading, battery) for the
%% telemetry publisher. High-frequency, in-memory; never event-sourced.
-callback snapshot(State :: term()) -> [map()].

%% @doc Rides awaiting assignment (unfulfilled demand) at their pickup points.
-callback rides(State :: term()) -> [map()].
