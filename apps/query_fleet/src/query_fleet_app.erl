%%% @doc query_fleet OTP application + cowboy listener.
%%%
%%% Binds HTTP_PORT + 1. A parksim container has three listeners — the
%%% main admin/sessions cowboy on HTTP_PORT (base), fleet on base+1, rides
%%% on base+2 — so all three are distinct and the 3 single-tenant
%%% containers co-located on one beam node (host networking) never collide.
%%% Dev fallback base is 8473 (=> fleet 8474), matching the old fixed port.
-module(query_fleet_app).
-behaviour(application).

-export([start/2, stop/1]).

-define(PORT_OFFSET, 1).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/api/fleet/overview",   query_fleet_api, overview},
            {"/api/fleet/vehicles",   query_fleet_api, vehicles},
            {"/api/fleet/facilities", query_fleet_api, facilities},
            {"/api/fleet/recent",     query_fleet_api, recent},
            {"/health",               query_fleet_api, health}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(query_fleet_http,
                                 [{port, port()}],
                                 #{env => #{dispatch => Dispatch}}),
    query_fleet_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(query_fleet_http),
    ok.

%% HTTP_PORT base + this app's offset (see moduledoc).
port() ->
    Base = case os:getenv("HTTP_PORT") of
               false -> 8473;
               ""    -> 8473;
               P     -> list_to_integer(P)
           end,
    Base + ?PORT_OFFSET.
