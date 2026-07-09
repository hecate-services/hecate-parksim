%%% @doc Supervises the regional grid-price emitter.
-module(simulate_grid_prices_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 10},
    Emitter = #{id    => emit_grid_price,
                start => {emit_grid_price, start_link, []}},
    {ok, {SupFlags, [Emitter]}}.
