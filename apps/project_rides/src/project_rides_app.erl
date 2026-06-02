%%% @doc project_rides OTP application entry.
-module(project_rides_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    project_rides_sup:start_link().

stop(_State) ->
    ok.
