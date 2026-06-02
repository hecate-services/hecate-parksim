%%% @doc Domain supervisor for the ride-lifecycle CMD app.
%%%
%%% Desks (request_ride, assign_ride, start_ride, complete_ride, expire_ride)
%%% are pure-function command paths dispatched via evoq_dispatcher — they own
%%% no processes. Read-model projection lives in the project_rides PRJ app.
-module(guide_ride_lifecycle_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    {ok, {SupFlags, []}}.
