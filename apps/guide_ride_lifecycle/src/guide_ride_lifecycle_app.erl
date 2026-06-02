%%% @doc guide_ride_lifecycle OTP application entry.
-module(guide_ride_lifecycle_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    guide_ride_lifecycle_sup:start_link().

stop(_State) ->
    ok.
