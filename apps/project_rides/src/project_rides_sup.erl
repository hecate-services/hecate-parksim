%%% @doc Starts the rides read-model store + the projection worker for the
%%% ride PRJ department. (No mesh emitters — ride analytics are served by the
%%% query_rides QRY app; ride markers reach the realm via the fleet telemetry.)
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
    {ok, {SupFlags, [Store, Projection]}}.
