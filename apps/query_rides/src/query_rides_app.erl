%%% @doc query_rides OTP application + cowboy listener.
%%%
%%% Binds HTTP_PORT + 2 (main cowboy = base, fleet = base+1, rides =
%%% base+2), so a container's three listeners are distinct and 3
%%% co-located single-tenant containers on one beam node (host networking)
%%% never collide. Dev fallback base is 8473 (=> rides 8475).
-module(query_rides_app).
-behaviour(application).

-export([start/2, stop/1]).

-define(PORT_OFFSET, 2).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/api/rides/overview",  query_rides_api, overview},
            {"/api/rides/companies", query_rides_api, companies},
            {"/api/rides/recent",    query_rides_api, recent},
            {"/api/rides",           query_rides_api, rides},
            {"/health",              query_rides_api, health}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(query_rides_http,
                                 [{port, port()}],
                                 #{env => #{dispatch => Dispatch}}),
    query_rides_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(query_rides_http),
    ok.

%% HTTP_PORT base + this app's offset (see moduledoc).
port() ->
    Base = case os:getenv("HTTP_PORT") of
               false -> 8473;
               ""    -> 8473;
               P     -> list_to_integer(P)
           end,
    Base + ?PORT_OFFSET.
