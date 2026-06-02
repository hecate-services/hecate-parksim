%%% @doc Starts the rides read-model store, the projection worker, and the
%%% ride-summary mesh emitter for the ride PRJ department. The emitter no-ops
%%% while the service is dark, so it's always safe to run.
-module(project_rides_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Store = #{id => project_rides_store,
              start => {project_rides_store, start_link, []}},
    Projection = #{id => ride_event_to_read_model,
                   start => {evoq_projection, start_link,
                             [ride_event_to_read_model, #{},
                              #{store_id => hecate_parksim_service:store_id()}]}},
    Summary = #{id => emit_rides_summary,
                start => {emit_rides_summary, start_link, []}},
    {ok, {SupFlags, [Store, Projection, Summary]}}.
