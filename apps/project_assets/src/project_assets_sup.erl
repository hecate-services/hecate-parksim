%%% @doc Starts the fleet asset-register read-model store and its projection.
-module(project_assets_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).
start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).
init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Store = #{id => project_assets_store,
              start => {project_assets_store, start_link, []}},
    Projection = #{id => asset_event_to_register,
                   start => {evoq_projection, start_link,
                             [asset_event_to_register, #{},
                              #{store_id => hecate_parksim_service:store_id()}]}},
    {ok, {SupFlags, [Store, Projection]}}.
