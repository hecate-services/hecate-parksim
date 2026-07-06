%%% @doc A non-sim `parksim_fleet_source' for tests: a "live feed" that drains a
%%% pre-recorded queue of command intents, one batch per poll. Stands in for a
%%% real telematics/ANPR/charger/payment adapter to prove the source port is
%%% implementable without the simulation — the seam the whole domain is built
%%% around. Not shipped in the release (test/ only).
-module(fake_feed).
-behaviour(parksim_fleet_source).

-export([init/2, poll/3, snapshot/1, rides/1]).

init(_Operator, #{queue := Queue}) ->
    {ok, #{queue => Queue}, []}.

poll(_SimUnix, _TickSecs, #{queue := []} = St) ->
    {[], St};
poll(_SimUnix, _TickSecs, #{queue := [Next | Rest]}) ->
    {[Next], #{queue => Rest}}.

snapshot(_St) -> [].
rides(_St)    -> [].
