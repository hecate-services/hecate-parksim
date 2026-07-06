%%% @doc Starts the operator-ledger read-model store and the projection worker
%%% that folds money-bearing events into it.
-module(project_settlements_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Store = #{id => project_settlements_store,
              start => {project_settlements_store, start_link, []}},
    Projection = #{id => settlement_event_to_ledger,
                   start => {evoq_projection, start_link,
                             [settlement_event_to_ledger, #{},
                              #{store_id => hecate_parksim_service:store_id()}]}},
    {ok, {SupFlags, [Store, Projection]}}.
