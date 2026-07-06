%%% @doc Owns the SQLite operator ledger — the financial read model.
%%%
%%% An append-only `ledger_entries' table: every money movement is one immutable
%%% entry (credit = revenue in, debit = cost out). Per-operator settlement is a
%%% pure aggregation over it. This is the real-world-accurate shape: swap the
%%% simulator for real ride/charger/parking/tow feeds and the same ledger holds.
%%%
%%% Revenue: ride fares + tips (`ride_completed`), parking fees
%%% (`payment_captured`). Cost: energy (`battery_charged.charging_cents`), tow
%%% (`vehicle_towed.tow_cents`).
-module(project_settlements_store).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).
-export([apply_event/1, settlement/0, ledger/1, by_kind/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include_lib("parksim_simulator/include/fleet.hrl").

-define(SERVER, ?MODULE).

-record(state, {db :: esqlite3:esqlite3(), operator :: binary()}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).
start_link(Opts) -> gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec apply_event(map()) -> ok.
apply_event(Event) -> gen_server:call(?SERVER, {apply_event, Event}, 30000).

%% @doc Settlement summary: revenue, cost, and net owed to the operator.
settlement()  -> gen_server:call(?SERVER, settlement, 30000).
%% @doc Recent ledger entries (most recent first).
ledger(Limit) -> gen_server:call(?SERVER, {ledger, Limit}, 30000).
%% @doc Revenue/cost broken down by kind.
by_kind()     -> gen_server:call(?SERVER, by_kind, 30000).

%%====================================================================
%% gen_server
%%====================================================================

init(Opts) ->
    DbPath = maps:get(db_path, Opts, default_db_path()),
    ok = filelib:ensure_dir(DbPath),
    {ok, Db} = esqlite3:open(DbPath),
    ok = init_schema(Db),
    %% Each store serves ONE operator; attribute every entry to it.
    Operator = maps:get(operator, Opts, store_operator()),
    {ok, #state{db = Db, operator = Operator}}.

handle_call({apply_event, Event}, _From, State) ->
    {reply, do_apply_event(Event, State), State};
handle_call(settlement, _From, State) ->
    {reply, do_settlement(State), State};
handle_call({ledger, Limit}, _From, State) ->
    {reply, do_ledger(Limit, State), State};
handle_call(by_kind, _From, State) ->
    {reply, do_by_kind(State), State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, #state{db = Db}) -> catch esqlite3:close(Db), ok.

%%====================================================================
%% Schema
%%====================================================================

init_schema(Db) ->
    ok = esqlite3:exec(Db,
        "CREATE TABLE IF NOT EXISTS ledger_entries ("
        "  entry_id     INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  operator     TEXT NOT NULL,"
        "  occurred_at  TEXT,"
        "  kind         TEXT NOT NULL,"    %% ride_fare|ride_tip|parking_fee|energy_cost|tow_cost
        "  direction    TEXT NOT NULL,"    %% credit | debit
        "  amount_cents INTEGER NOT NULL,"
        "  ref          TEXT"              %% ride_id | session_id | vehicle_id
        ");"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_ledger_op ON ledger_entries(operator);"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_ledger_kind ON ledger_entries(kind);"),
    ok.

%%====================================================================
%% Projection (fold money events into ledger entries)
%%====================================================================

do_apply_event(#{event_type := <<"ride_completed">>} = Ev, S) ->
    Ref = g(ride_id, Ev), At = g(completed_at, Ev),
    entry(S, At, <<"ride_fare">>, credit, num(g(fare_cents, Ev)), Ref),
    entry(S, At, <<"ride_tip">>,  credit, num(g(tip_cents, Ev)),  Ref),
    ok;
do_apply_event(#{event_type := <<"payment_captured">>} = Ev, S) ->
    entry(S, g(paid_at, Ev), <<"parking_fee">>, credit,
          num(g(fee_cents, Ev)), g(session_id, Ev)),
    ok;
do_apply_event(#{event_type := <<"battery_charged">>} = Ev, S) ->
    entry(S, g(charged_at, Ev), <<"energy_cost">>, debit,
          num(g(charging_cents, Ev)), g(vehicle_id, Ev)),
    ok;
do_apply_event(#{event_type := <<"vehicle_towed">>} = Ev, S) ->
    entry(S, g(towed_at, Ev), <<"tow_cost">>, debit,
          num(g(tow_cents, Ev)), g(vehicle_id, Ev)),
    ok;
do_apply_event(_Ev, _S) ->
    ok.

%% @private Append one ledger entry (skips zero/undefined amounts).
entry(_S, _At, _Kind, _Dir, 0, _Ref) -> ok;
entry(#state{db = Db, operator = Op}, At, Kind, Dir, Amount, Ref)
  when is_integer(Amount), Amount > 0 ->
    esqlite3:q(Db,
        "INSERT INTO ledger_entries"
        " (operator, occurred_at, kind, direction, amount_cents, ref)"
        " VALUES (?1,?2,?3,?4,?5,?6)",
        [Op, nullable(At), Kind, atom_to_binary(Dir, utf8), Amount, nullable(Ref)]),
    ok;
entry(_S, _At, _Kind, _Dir, _Amount, _Ref) -> ok.

%%====================================================================
%% Queries
%%====================================================================

do_settlement(#state{db = Db, operator = Op}) ->
    [[Rev, Cost]] = esqlite3:q(Db,
        "SELECT"
        "  coalesce(sum(CASE WHEN direction='credit' THEN amount_cents END),0),"
        "  coalesce(sum(CASE WHEN direction='debit'  THEN amount_cents END),0)"
        " FROM ledger_entries;"),
    Entries = scalar(esqlite3:q(Db, "SELECT count(*) FROM ledger_entries;")),
    #{operator => Op,
      revenue_cents => Rev,
      cost_cents => Cost,
      net_cents => Rev - Cost,
      entries => Entries}.

do_by_kind(#state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT kind, direction, coalesce(sum(amount_cents),0), count(*)"
        " FROM ledger_entries GROUP BY kind, direction ORDER BY kind;"),
    [#{kind => K, direction => D, amount_cents => A, count => N}
     || [K, D, A, N] <- Rows].

do_ledger(Limit, #state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT operator, occurred_at, kind, direction, amount_cents, ref"
        " FROM ledger_entries ORDER BY entry_id DESC LIMIT ?1;", [Limit]),
    [#{operator => O, occurred_at => At, kind => K, direction => D,
       amount_cents => A, ref => R}
     || [O, At, K, D, A, R] <- Rows].

%%====================================================================
%% Helpers
%%====================================================================

g(K, M) -> maps:get(K, M, undefined).
num(N) when is_integer(N) -> N;
num(N) when is_float(N) -> round(N);
num(_) -> 0.
nullable(undefined) -> null;
nullable(V) -> V.
scalar([[V]]) -> V;
scalar(_) -> 0.

store_operator() ->
    try (fleet_config:operator())#operator.id
    catch _:_ -> <<"operator">> end.

default_db_path() ->
    Dir = case os:getenv("HECATE_DATA_DIR") of
              false -> "/tmp/hecate-parksim";
              ""    -> "/tmp/hecate-parksim";
              D     -> D
          end,
    filename:join([Dir, "settlements_read_model.db"]).
