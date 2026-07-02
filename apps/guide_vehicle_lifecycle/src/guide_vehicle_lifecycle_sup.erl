%%% @doc Domain supervisor for the vehicle-lifecycle CMD app.
%%%
%%% Desks (commission_vehicle, dispatch_vehicle, pick_up_passenger,
%%% drop_off_passenger, return_vehicle, dock_vehicle, service_vehicle,
%%% release_vehicle, deplete_battery) are pure-function command paths
%%% dispatched via evoq_command_router — they own no processes. Read-model
%%% projection + retention live in the project_fleet PRJ app.
-module(guide_vehicle_lifecycle_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    {ok, {SupFlags, []}}.
