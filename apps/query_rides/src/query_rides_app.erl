%%% @doc query_rides OTP application + cowboy listener.
%%%
%%% Listens on its own port (parking 8473, fleet 8474, rides 8475).
-module(query_rides_app).
-behaviour(application).

-export([start/2, stop/1]).

-define(PORT, 8475).

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
                                 [{port, ?PORT}],
                                 #{env => #{dispatch => Dispatch}}),
    query_rides_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(query_rides_http),
    ok.
