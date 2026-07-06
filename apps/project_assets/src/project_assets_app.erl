%%% @doc OTP application entry for the fleet asset register PRJ.
-module(project_assets_app).
-behaviour(application).
-export([start/2, stop/1]).
start(_Type, _Args) -> project_assets_sup:start_link().
stop(_State) -> ok.
