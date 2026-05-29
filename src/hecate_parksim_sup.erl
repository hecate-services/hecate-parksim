%%% @doc Root supervisor for hecate-parksim.
-module(hecate_parksim_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Children = [
        %% Cowboy listener — small HTTP admin surface (/health + /api/run + /api/event).
        cowboy_child(),
        %% Traffic generation: simulate_arrivals (one gen_server per lot
        %% in the preset) spawns short-lived simulate_visit processes
        %% per arrival; simulate_visit dispatches the 3 session events
        %% directly via evoq_dispatcher to the local tenant store.
        #{id => simulate_arrivals_sup,
          start => {simulate_arrivals_sup, start_link, []},
          restart => permanent, shutdown => 5000,
          type => supervisor, modules => [simulate_arrivals_sup]}
    ],
    {ok, {SupFlags, Children}}.

cowboy_child() ->
    Port = application:get_env(hecate_parksim, http_port, 8473),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/health", hecate_om_health_handler, []},
            {"/api/run",   hecate_parksim_admin_api, [run]},
            {"/api/event", hecate_parksim_admin_api, [event]},
            %% QRY read-model surface (specific paths before the :id catch).
            {"/api/sessions/overview", query_parking_sessions_api, [overview]},
            {"/api/sessions/recent",   query_parking_sessions_api, [recent]},
            {"/api/sessions/:id",      query_parking_sessions_api, [session]}
        ]}
    ]),
    #{id => cowboy_listener,
      start => {cowboy, start_clear, [
          hecate_parksim_http_listener,
          [{port, Port}],
          #{env => #{dispatch => Dispatch}}
      ]},
      restart => permanent, shutdown => 5000,
      type => worker, modules => [cowboy]}.
