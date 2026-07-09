%%% @doc project_energy OTP application entry.
-module(project_energy_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    project_energy_sup:start_link().

stop(_State) ->
    ok.
