%%% @doc Owns the SQLite energy read model — one row per charging session.
%%%
%%% The charging process is the highest-frequency, most economically central
%%% process in an EV fleet; this read model turns its event stream into
%%% per-operator energy totals: kWh drawn, cost, and the OFF-PEAK SHARE — the
%%% measurable payoff of price-aware, mesh-coordinated scheduling. Each store
%%% serves one operator (like the settlements ledger); swap the simulator for
%%% real charger feeds and the same table holds.
-module(project_energy_store).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).
-export([apply_event/1, summary/0, recent/1]).
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

%% @doc Per-operator energy summary: sessions, kWh, cost, off-peak share.
summary() -> gen_server:call(?SERVER, summary, 30000).
%% @doc Most-recent charging sessions (newest first).
recent(Limit) -> gen_server:call(?SERVER, {recent, Limit}, 30000).

%%====================================================================
%% gen_server
%%====================================================================

init(Opts) ->
    DbPath = maps:get(db_path, Opts, default_db_path()),
    ok = filelib:ensure_dir(DbPath),
    {ok, Db} = esqlite3:open(DbPath),
    ok = init_schema(Db),
    Operator = maps:get(operator, Opts, store_operator()),
    {ok, #state{db = Db, operator = Operator}}.

handle_call({apply_event, Event}, _From, State) ->
    {reply, do_apply_event(Event, State), State};
handle_call(summary, _From, State) ->
    {reply, do_summary(State), State};
handle_call({recent, Limit}, _From, State) ->
    {reply, do_recent(Limit, State), State};
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
        "CREATE TABLE IF NOT EXISTS charging_sessions ("
        "  session_id           TEXT PRIMARY KEY,"
        "  operator             TEXT NOT NULL,"
        "  vehicle_id           TEXT,"
        "  tariff_cents_per_kwh REAL,"
        "  energy_kwh           REAL,"
        "  final_soc_pct        REAL,"
        "  cost_cents           INTEGER,"
        "  off_peak             INTEGER,"    %% 0 | 1
        "  status               TEXT,"       %% charging | completed | settled
        "  started_at           TEXT,"
        "  completed_at         TEXT,"
        "  settled_at           TEXT"
        ");"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_energy_status ON charging_sessions(status);"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_energy_vehicle ON charging_sessions(vehicle_id);"),
    ok.

%%====================================================================
%% Projection (fold charging events into session rows)
%%====================================================================

do_apply_event(#{event_type := <<"charging_started">>} = Ev, #state{db = Db, operator = Op}) ->
    esqlite3:q(Db,
        "INSERT INTO charging_sessions"
        " (session_id, operator, vehicle_id, tariff_cents_per_kwh, status, started_at)"
        " VALUES (?1,?2,?3,?4,'charging',?5)"
        " ON CONFLICT(session_id) DO UPDATE SET"
        "   vehicle_id           = excluded.vehicle_id,"
        "   tariff_cents_per_kwh = excluded.tariff_cents_per_kwh,"
        "   started_at           = excluded.started_at;",
        [g(session_id, Ev), Op, nullable(g(vehicle_id, Ev)),
         numn(g(tariff_cents_per_kwh, Ev)), nullable(g(started_at, Ev))]),
    ok;
do_apply_event(#{event_type := <<"charging_completed">>} = Ev, #state{db = Db, operator = Op}) ->
    esqlite3:q(Db,
        "INSERT INTO charging_sessions"
        " (session_id, operator, vehicle_id, energy_kwh, final_soc_pct, status, completed_at)"
        " VALUES (?1,?2,?3,?4,?5,'completed',?6)"
        " ON CONFLICT(session_id) DO UPDATE SET"
        "   energy_kwh    = excluded.energy_kwh,"
        "   final_soc_pct = excluded.final_soc_pct,"
        "   completed_at  = excluded.completed_at,"
        "   vehicle_id    = coalesce(excluded.vehicle_id, charging_sessions.vehicle_id),"
        "   status        = CASE WHEN charging_sessions.status='settled'"
        "                        THEN 'settled' ELSE 'completed' END;",
        [g(session_id, Ev), Op, nullable(g(vehicle_id, Ev)),
         numn(g(energy_kwh, Ev)), numn(g(final_soc_pct, Ev)),
         nullable(g(completed_at, Ev))]),
    ok;
do_apply_event(#{event_type := <<"energy_settled">>} = Ev, #state{db = Db, operator = Op}) ->
    esqlite3:q(Db,
        "INSERT INTO charging_sessions"
        " (session_id, operator, vehicle_id, energy_kwh, tariff_cents_per_kwh,"
        "  cost_cents, off_peak, status, settled_at)"
        " VALUES (?1,?2,?3,?4,?5,?6,?7,'settled',?8)"
        " ON CONFLICT(session_id) DO UPDATE SET"
        "   cost_cents           = excluded.cost_cents,"
        "   off_peak             = excluded.off_peak,"
        "   settled_at           = excluded.settled_at,"
        "   energy_kwh           = coalesce(excluded.energy_kwh, charging_sessions.energy_kwh),"
        "   tariff_cents_per_kwh = coalesce(excluded.tariff_cents_per_kwh, charging_sessions.tariff_cents_per_kwh),"
        "   status               = 'settled';",
        [g(session_id, Ev), Op, nullable(g(vehicle_id, Ev)),
         numn(g(energy_kwh, Ev)), numn(g(tariff_cents_per_kwh, Ev)),
         numn(g(cost_cents, Ev)), bool01(g(off_peak, Ev)),
         nullable(g(settled_at, Ev))]),
    ok;
do_apply_event(_Ev, _S) ->
    ok.

%%====================================================================
%% Queries
%%====================================================================

do_summary(#state{db = Db, operator = Op}) ->
    [[Sessions, Settled, Kwh, Cost, OffPeak, AvgTariff]] = esqlite3:q(Db,
        "SELECT"
        "  count(*),"
        "  coalesce(sum(CASE WHEN status='settled' THEN 1 ELSE 0 END),0),"
        "  coalesce(sum(energy_kwh),0),"
        "  coalesce(sum(cost_cents),0),"
        "  coalesce(sum(CASE WHEN off_peak=1 THEN 1 ELSE 0 END),0),"
        "  coalesce(avg(CASE WHEN status='settled' THEN tariff_cents_per_kwh END),0)"
        " FROM charging_sessions;"),
    #{operator          => Op,
      sessions          => Sessions,
      settled           => Settled,
      energy_kwh        => round1(Kwh),
      cost_cents        => round(Cost),
      off_peak_sessions => OffPeak,
      off_peak_pct      => pct(OffPeak, Settled),
      avg_tariff_cents  => round1(AvgTariff)}.

do_recent(Limit, #state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT session_id, vehicle_id, energy_kwh, tariff_cents_per_kwh,"
        "       cost_cents, off_peak, status, settled_at"
        " FROM charging_sessions"
        " ORDER BY coalesce(settled_at, completed_at, started_at) DESC LIMIT ?1;",
        [Limit]),
    [#{session_id => Sid, vehicle_id => Vid, energy_kwh => Kwh,
       tariff_cents_per_kwh => Tar, cost_cents => Cost,
       off_peak => (OffPeak =:= 1), status => Status, settled_at => At}
     || [Sid, Vid, Kwh, Tar, Cost, OffPeak, Status, At] <- Rows].

%%====================================================================
%% Helpers
%%====================================================================

g(K, M) -> maps:get(K, M, maps:get(atom_to_binary(K, utf8), M, undefined)).

numn(N) when is_number(N) -> N;
numn(_) -> null.

bool01(true)  -> 1;
bool01(1)     -> 1;
bool01(_)     -> 0.

nullable(undefined) -> null;
nullable(V)         -> V.

round1(F) when is_number(F) -> round(F * 10) / 10;
round1(_) -> 0.

pct(_N, 0) -> 0;
pct(N, Total) when is_integer(N), is_integer(Total), Total > 0 ->
    round(N / Total * 1000) / 10.

store_operator() ->
    try (fleet_config:operator())#operator.id
    catch _:_ -> <<"operator">> end.

default_db_path() ->
    Dir = case os:getenv("HECATE_DATA_DIR") of
              false -> "/tmp/hecate-parksim";
              ""    -> "/tmp/hecate-parksim";
              D     -> D
          end,
    filename:join([Dir, "energy_read_model.db"]).
