%%% @doc simulate_grid_prices OTP application entry.
-module(simulate_grid_prices_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    simulate_grid_prices_sup:start_link().

stop(_State) ->
    ok.
