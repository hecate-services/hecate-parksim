%%% @doc query_rides supervisor (no children; the cowboy listener is started
%%% in the app module). Present for OTP app structure.
-module(query_rides_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 5}, []}}.
