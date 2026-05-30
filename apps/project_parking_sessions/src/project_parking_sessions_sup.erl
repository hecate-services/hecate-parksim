%%% @doc Supervisor for the parking-sessions projection.
%%%
%%% Starts the SQLite read-model store first, then the evoq_projection
%%% that feeds it. The projection registers its event types here; the
%%% store subscription (started by hecate_parksim_service after the
%%% event store is up) then delivers events — catch-up + live.
-module(project_parking_sessions_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Children = [
        #{id    => project_parking_sessions_store,
          start => {project_parking_sessions_store, start_link, []},
          type  => worker},
        #{id    => parking_session_to_read_model,
          start => {evoq_projection, start_link,
                    [parking_session_to_read_model, #{},
                     #{store_id => hecate_parksim_service:store_id()}]},
          type  => worker},
        %% Retention: read-model-driven scavenge of aged event streams.
        #{id    => scavenge_aged_sessions,
          start => {scavenge_aged_sessions, start_link, []},
          type  => worker},
        %% Mesh publisher: emits this city's summary fact on a cadence.
        %% No-op while the service is dark (no mesh client).
        #{id    => emit_city_summary,
          start => {emit_city_summary, start_link, []},
          type  => worker}
    ],
    {ok, {SupFlags, Children}}.
