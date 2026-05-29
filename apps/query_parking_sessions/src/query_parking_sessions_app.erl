-module(query_parking_sessions_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) -> query_parking_sessions_sup:start_link().
stop(_State) -> ok.
