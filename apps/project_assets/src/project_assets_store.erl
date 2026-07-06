%%% @doc Owns the SQLite fleet ASSET register — one row per vehicle-as-asset.
%%%
%%% VIN + plate + model identify the asset; battery State-of-Health + charge
%%% cycles track its ageing (an EV's value follows its pack health); trips and
%%% tows track utilisation and incidents. `fleet_health/0' summarises the fleet
%%% and flags packs at/near the replacement threshold.
-module(project_assets_store).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).
-export([apply_event/1, assets/0, asset/1, fleet_health/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(REPLACE_SOH, 65).   %% flag packs at/below this for replacement

-record(state, {db :: esqlite3:esqlite3()}).

start_link() -> start_link(#{}).
start_link(Opts) -> gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec apply_event(map()) -> ok.
apply_event(Event) -> gen_server:call(?SERVER, {apply_event, Event}, 30000).

assets()       -> gen_server:call(?SERVER, assets, 30000).
asset(VId)     -> gen_server:call(?SERVER, {asset, VId}, 30000).
fleet_health() -> gen_server:call(?SERVER, fleet_health, 30000).

init(Opts) ->
    DbPath = maps:get(db_path, Opts, default_db_path()),
    ok = filelib:ensure_dir(DbPath),
    {ok, Db} = esqlite3:open(DbPath),
    ok = init_schema(Db),
    {ok, #state{db = Db}}.

handle_call({apply_event, Event}, _From, S) -> {reply, do_apply(Event, S), S};
handle_call(assets, _From, S)               -> {reply, do_assets(S), S};
handle_call({asset, VId}, _From, S)         -> {reply, do_asset(VId, S), S};
handle_call(fleet_health, _From, S)         -> {reply, do_fleet_health(S), S};
handle_call(_Req, _From, S)                 -> {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Info, S) -> {noreply, S}.
terminate(_Reason, #state{db = Db}) -> catch esqlite3:close(Db), ok.

%%====================================================================

init_schema(Db) ->
    ok = esqlite3:exec(Db,
        "CREATE TABLE IF NOT EXISTS fleet_assets ("
        "  vehicle_id      TEXT PRIMARY KEY,"
        "  vin             TEXT,"
        "  plate           TEXT,"
        "  model           TEXT,"
        "  operator        TEXT,"
        "  battery_soh_pct REAL,"
        "  charge_cycles   INTEGER DEFAULT 0,"
        "  trips           INTEGER DEFAULT 0,"
        "  tows            INTEGER DEFAULT 0,"
        "  commissioned_at TEXT,"
        "  last_event_at   TEXT"
        ");"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_assets_soh ON fleet_assets(battery_soh_pct);"),
    ok.

%%====================================================================
%% Projection
%%====================================================================

do_apply(#{event_type := <<"vehicle_commissioned">>} = Ev, #state{db = Db}) ->
    esqlite3:q(Db,
        "INSERT INTO fleet_assets"
        " (vehicle_id, vin, plate, model, operator, battery_soh_pct,"
        "  charge_cycles, commissioned_at, last_event_at)"
        " VALUES (?1,?2,?3,?4,?5,?6,0,?7,?7)"
        " ON CONFLICT(vehicle_id) DO UPDATE SET"
        "   vin=excluded.vin, plate=excluded.plate, model=excluded.model,"
        "   operator=excluded.operator",
        [g(vehicle_id, Ev), g(vin, Ev), g(plate, Ev), g(model, Ev),
         g(company_id, Ev), num(g(battery_soh_pct, Ev), 100), g(commissioned_at, Ev)]),
    ok;
do_apply(#{event_type := <<"battery_charged">>} = Ev, #state{db = Db}) ->
    %% SoH + cycle come from the event (the sim's ageing model).
    set(Db, g(vehicle_id, Ev), "battery_soh_pct", num(g(battery_soh_pct, Ev), 100),
        g(charged_at, Ev)),
    set(Db, g(vehicle_id, Ev), "charge_cycles", num(g(charge_cycle, Ev), 0),
        g(charged_at, Ev)),
    ok;
do_apply(#{event_type := <<"passenger_dropped_off">>} = Ev, #state{db = Db}) ->
    bump(Db, g(vehicle_id, Ev), "trips", g(dropped_off_at, Ev)),
    ok;
do_apply(#{event_type := <<"vehicle_towed">>} = Ev, #state{db = Db}) ->
    bump(Db, g(vehicle_id, Ev), "tows", g(towed_at, Ev)),
    ok;
do_apply(_Ev, _S) ->
    ok.

set(_Db, undefined, _Col, _Val, _At) -> ok;
set(Db, VId, Col, Val, At) ->
    esqlite3:q(Db, lists:flatten(
        ["UPDATE fleet_assets SET ", Col, "=?1, last_event_at=?2 WHERE vehicle_id=?3"]),
        [Val, nullable(At), VId]), ok.

bump(_Db, undefined, _Col, _At) -> ok;
bump(Db, VId, Col, At) ->
    esqlite3:q(Db, lists:flatten(
        ["UPDATE fleet_assets SET ", Col, "=", Col, "+1, last_event_at=?1 WHERE vehicle_id=?2"]),
        [nullable(At), VId]), ok.

%%====================================================================
%% Queries
%%====================================================================

do_assets(#state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT vehicle_id, vin, plate, model, operator, battery_soh_pct,"
        "       charge_cycles, trips, tows FROM fleet_assets ORDER BY vehicle_id;"),
    [asset_map(R) || R <- Rows].

do_asset(VId, #state{db = Db}) ->
    case esqlite3:q(Db,
        "SELECT vehicle_id, vin, plate, model, operator, battery_soh_pct,"
        "       charge_cycles, trips, tows FROM fleet_assets WHERE vehicle_id=?1;", [VId]) of
        [R] -> asset_map(R);
        _   -> undefined
    end.

do_fleet_health(#state{db = Db}) ->
    [[N, Avg, MinSoh, NeedReplace]] = esqlite3:q(Db,
        "SELECT count(*), coalesce(round(avg(battery_soh_pct),1),0),"
        "  coalesce(min(battery_soh_pct),0),"
        "  sum(CASE WHEN battery_soh_pct <= ?1 THEN 1 ELSE 0 END)"
        " FROM fleet_assets;", [?REPLACE_SOH]),
    #{fleet_size => N,
      avg_battery_soh_pct => Avg,
      min_battery_soh_pct => MinSoh,
      packs_due_replacement => nz(NeedReplace)}.

asset_map([VId, Vin, Plate, Model, Op, Soh, Cyc, Trips, Tows]) ->
    #{vehicle_id => VId, vin => Vin, plate => Plate, model => Model,
      operator => Op, battery_soh_pct => Soh, charge_cycles => Cyc,
      trips => Trips, tows => Tows}.

%%====================================================================
g(K, M) -> maps:get(K, M, undefined).
num(N, _) when is_number(N) -> N;
num(_, D) -> D.
nz(N) when is_integer(N) -> N;
nz(_) -> 0.
nullable(undefined) -> null;
nullable(V) -> V.

default_db_path() ->
    Dir = case os:getenv("HECATE_DATA_DIR") of
              false -> "/tmp/hecate-parksim";
              ""    -> "/tmp/hecate-parksim";
              D     -> D
          end,
    filename:join([Dir, "assets_read_model.db"]).
