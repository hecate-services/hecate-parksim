%%% @doc OTP application entry for the settlement (operator ledger) PRJ.
-module(project_settlements_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    project_settlements_sup:start_link().

stop(_State) ->
    ok.
