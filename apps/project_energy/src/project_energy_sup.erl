%%% @doc Starts the energy read-model store and the projection worker that folds
%%% the charging process's events into it.
-module(project_energy_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Store = #{id => project_energy_store,
              start => {project_energy_store, start_link, []}},
    Projection = #{id => charging_event_to_energy,
                   start => {evoq_projection, start_link,
                             [charging_event_to_energy, #{},
                              #{store_id => hecate_parksim_service:store_id()}]}},
    %% Mesh publisher: emits this operator's energy summary fact on a cadence.
    Emitter = #{id => emit_energy_summary,
                start => {emit_energy_summary, start_link, []}},
    {ok, {SupFlags, [Store, Projection, Emitter]}}.
