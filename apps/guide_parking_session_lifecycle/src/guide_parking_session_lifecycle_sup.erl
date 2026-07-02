%%% @doc Domain supervisor for the parking-session-lifecycle CMD app.
%%%
%%% Desks (initiate_parking_session, dock_vehicle, undock_vehicle,
%%% capture_payment, archive_parking_session) are pure-function command
%%% paths dispatched via evoq_command_router — they own no processes.
%%% Retention (snapshot/scavenge) moved to the project_parking_sessions
%%% PRJ app, which drives it from the durable SQLite read model.
-module(guide_parking_session_lifecycle_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    {ok, {SupFlags, []}}.
