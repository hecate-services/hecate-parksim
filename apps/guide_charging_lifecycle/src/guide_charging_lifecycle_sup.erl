%%% @doc Domain supervisor for the charging-lifecycle CMD app.
%%%
%%% The charging desks (request_charge, start_charging, progress_charging,
%%% complete_charging, settle_energy) are pure-function command paths dispatched
%%% via evoq_command_router — they own no processes. The one process this domain
%%% owns is its integration point: the `on_grid_price_changed_schedule_charging'
%%% process manager, which subscribes to the mesh grid-price fact and holds the
%%% operative tariff the charging decisions read. Read-model projection lives in
%%% the project_energy PRJ app.
-module(guide_charging_lifecycle_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Pm = #{id    => on_grid_price_changed_schedule_charging,
           start => {on_grid_price_changed_schedule_charging, start_link, []}},
    {ok, {SupFlags, [Pm]}}.
