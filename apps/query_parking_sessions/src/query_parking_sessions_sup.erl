%%% @doc Supervisor for the QRY app. QRY owns no processes — it reads
%%% the read model the PRJ app maintains — so there are no children.
-module(query_parking_sessions_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 1, period => 5}, []}}.
