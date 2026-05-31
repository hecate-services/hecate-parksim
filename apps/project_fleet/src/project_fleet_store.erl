%%% @doc Owns the SQLite read model for the robotaxi fleet.
%%%
%%% A single gen_server serialises all DB access (esqlite handles are not
%%% shareable across processes). Folds vehicle-lifecycle events into a
%%% `vehicles' table (one row per vehicle, current phase + position-at-last-
%%% event + lifetime tallies) and answers the queries the dashboard needs.
%%%
%%% Position here is the value AT THE LAST MILESTONE EVENT — live high-
%%% frequency position is telemetry (in the fleet sim, streamed as a mesh
%%% fact), never event-sourced. So the read model lags the live map slightly
%%% by design; that is correct CQRS, not a bug.
-module(project_fleet_store).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).
-export([apply_event/1, overview/0, vehicles/0, by_facility/0, recent/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include_lib("guide_vehicle_lifecycle/include/vehicle_status.hrl").

-define(SERVER, ?MODULE).

-record(state, {db :: esqlite3:esqlite3()}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).
start_link(Opts) -> gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Apply one event map to the read model (called by the projection).
-spec apply_event(map()) -> ok.
apply_event(Event) -> gen_server:call(?SERVER, {apply_event, Event}, 30000).

overview()     -> gen_server:call(?SERVER, overview, 30000).
vehicles()     -> gen_server:call(?SERVER, vehicles, 30000).
by_facility()  -> gen_server:call(?SERVER, by_facility, 30000).
recent(Limit)  -> gen_server:call(?SERVER, {recent, Limit}, 30000).

%%====================================================================
%% gen_server
%%====================================================================

init(Opts) ->
    DbPath = maps:get(db_path, Opts, default_db_path()),
    ok = filelib:ensure_dir(DbPath),
    {ok, Db} = esqlite3:open(DbPath),
    ok = init_schema(Db),
    {ok, #state{db = Db}}.

handle_call({apply_event, Event}, _From, State) ->
    {reply, do_apply_event(Event, State), State};
handle_call(overview, _From, State) ->
    {reply, do_overview(State), State};
handle_call(vehicles, _From, State) ->
    {reply, do_vehicles(State), State};
handle_call(by_facility, _From, State) ->
    {reply, do_by_facility(State), State};
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
        "CREATE TABLE IF NOT EXISTS vehicles ("
        "  vehicle_id   TEXT PRIMARY KEY,"
        "  company_id   TEXT,"
        "  status       INTEGER NOT NULL DEFAULT 0,"  %% current phase bit
        "  battery_pct  REAL,"
        "  x          REAL,"
        "  y          REAL,"
        "  facility_id  TEXT,"
        "  service_kind TEXT,"
        "  trips        INTEGER NOT NULL DEFAULT 0,"
        "  fares_cents  INTEGER NOT NULL DEFAULT 0,"
        "  last_event   TEXT,"               %% last event type seen
        "  last_event_at TEXT,"
        "  commissioned_at TEXT"
        ");"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_vehicles_status ON vehicles(status);"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_vehicles_facility ON vehicles(facility_id);"),
    %% A compact event log feeds the dashboard's "recent activity" feed.
    ok = esqlite3:exec(Db,
        "CREATE TABLE IF NOT EXISTS activity ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  vehicle_id TEXT, event TEXT, at TEXT"
        ");"),
    ok.

%%====================================================================
%% Projection (write) — fold each vehicle event into the row.
%%====================================================================

do_apply_event(#{event_type := Type} = Ev, #state{db = Db}) ->
    VId = maps:get(vehicle_id, Ev, undefined),
    apply_typed(Type, VId, Ev, Db),
    log_activity(Db, VId, Type, Ev),
    ok;
do_apply_event(_Ev, _State) -> ok.

%% Phase transitions set the (exclusive) phase bit. Each clause also lands
%% whatever fields the event carries.
apply_typed(<<"vehicle_commissioned">>, VId, Ev, Db) ->
    upsert_vehicle(Db, VId, Ev),
    set_phase(Db, VId, ?VEH_COMMISSIONED),
    ok;
apply_typed(<<"vehicle_dispatched">>, VId, _Ev, Db) ->
    set_phase(Db, VId, ?VEH_DISPATCHED), ok;
apply_typed(<<"passenger_picked_up">>, VId, Ev, Db) ->
    set_pos(Db, VId, Ev),
    set_phase(Db, VId, ?VEH_ON_TRIP), ok;
apply_typed(<<"passenger_dropped_off">>, VId, Ev, Db) ->
    set_pos(Db, VId, Ev),
    bump_trips(Db, VId),
    set_phase(Db, VId, ?VEH_CRUISING), ok;
apply_typed(<<"fare_collected">>, VId, Ev, Db) ->
    add_fare(Db, VId, maps:get(amount_cents, Ev, 0)), ok;
apply_typed(<<"vehicle_returning">>, VId, Ev, Db) ->
    set_col(Db, VId, <<"facility_id">>, maps:get(facility_id, Ev, undefined)),
    set_phase(Db, VId, ?VEH_RETURNING), ok;
apply_typed(<<"vehicle_docked_at_facility">>, VId, Ev, Db) ->
    set_pos(Db, VId, Ev),
    set_col(Db, VId, <<"facility_id">>, maps:get(facility_id, Ev, undefined)),
    set_phase(Db, VId, ?VEH_DOCKED), ok;
apply_typed(<<"vehicle_serviced">>, VId, Ev, Db) ->
    set_col(Db, VId, <<"service_kind">>, maps:get(service_kind, Ev, undefined)),
    maybe_recharge(Db, VId, Ev),
    set_phase(Db, VId, ?VEH_SERVICING), ok;
apply_typed(<<"vehicle_released">>, VId, _Ev, Db) ->
    set_col(Db, VId, <<"facility_id">>, undefined),
    set_col(Db, VId, <<"service_kind">>, undefined),
    set_phase(Db, VId, ?VEH_CRUISING), ok;
apply_typed(<<"battery_depleted">>, VId, Ev, Db) ->
    set_pos(Db, VId, Ev),
    set_battery(Db, VId, 0.0),
    set_phase(Db, VId, ?VEH_DEPLETED), ok;
apply_typed(_Other, _VId, _Ev, _Db) -> ok.

%%--------------------------------------------------------------------
%% Row helpers

upsert_vehicle(Db, VId, Ev) ->
    esqlite3:q(Db,
        "INSERT INTO vehicles"
        " (vehicle_id, company_id, battery_pct, x, y, commissioned_at, status)"
        " VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)"
        " ON CONFLICT(vehicle_id) DO UPDATE SET"
        "   company_id=excluded.company_id, battery_pct=excluded.battery_pct,"
        "   x=excluded.x, y=excluded.y,"
        "   commissioned_at=excluded.commissioned_at",
        [VId, maps:get(company_id, Ev, undefined), num(maps:get(battery_pct, Ev, 100)),
         num(maps:get(x, Ev, undefined)), num(maps:get(y, Ev, undefined)),
         maps:get(commissioned_at, Ev, undefined)]),
    ok.

%% Set the exclusive phase: clear ALL phase bits, then OR in the new one.
%% The clear-mask is computed in Erlang (SQLite won't parse `~?1` — a bound
%% param immediately after bitwise-NOT is a syntax error), so we bind a plain
%% AND-mask = bnot(all phase bits), truncated to the status column's width.
set_phase(Db, VId, Phase) ->
    AllMask   = lists:foldl(fun(B, Acc) -> Acc bor B end, 0, ?VEH_ALL_PHASES),
    ClearMask = (bnot AllMask) band 16#FFFFFFFF,
    esqlite3:q(Db,
        "UPDATE vehicles SET status = (status & ?1) | ?2 WHERE vehicle_id = ?3",
        [ClearMask, Phase, VId]),
    ok.

set_pos(Db, VId, Ev) ->
    case {maps:get(x, Ev, undefined), maps:get(y, Ev, undefined)} of
        {undefined, _} -> ok;
        {X, Y} ->
            esqlite3:q(Db, "UPDATE vehicles SET x=?1, y=?2 WHERE vehicle_id=?3",
                       [num(X), num(Y), VId]),
            ok
    end.

set_battery(Db, VId, Pct) ->
    esqlite3:q(Db, "UPDATE vehicles SET battery_pct=?1 WHERE vehicle_id=?2",
               [num(Pct), VId]), ok.

maybe_recharge(Db, VId, Ev) ->
    case maps:get(battery_pct, Ev, undefined) of
        undefined -> ok;
        Pct       -> set_battery(Db, VId, Pct)
    end.

set_col(Db, VId, Col, Val) ->
    SQL = ["UPDATE vehicles SET ", binary_to_list(Col), "=?1 WHERE vehicle_id=?2"],
    esqlite3:q(Db, lists:flatten(SQL), [Val, VId]), ok.

bump_trips(Db, VId) ->
    esqlite3:q(Db, "UPDATE vehicles SET trips = trips + 1 WHERE vehicle_id=?1", [VId]), ok.

add_fare(Db, VId, Cents) ->
    esqlite3:q(Db, "UPDATE vehicles SET fares_cents = fares_cents + ?1 WHERE vehicle_id=?2",
               [num(Cents), VId]), ok.

log_activity(_Db, undefined, _Type, _Ev) -> ok;
log_activity(Db, VId, Type, Ev) ->
    At = maps:get(last_event_at, Ev, undefined),
    esqlite3:q(Db, "INSERT INTO activity (vehicle_id, event, at) VALUES (?1,?2,?3)",
               [VId, Type, At]),
    %% keep the activity log bounded (~last 500 rows)
    esqlite3:q(Db,
        "DELETE FROM activity WHERE id < (SELECT max(id)-500 FROM activity)"),
    ok.

%%====================================================================
%% Queries (read)
%%====================================================================

do_overview(#state{db = Db}) ->
    Total    = scalar(esqlite3:q(Db, "SELECT count(*) FROM vehicles;")),
    Cruising = phase_count(Db, ?VEH_CRUISING),
    OnTrip   = phase_count(Db, ?VEH_ON_TRIP),
    Dispatched = phase_count(Db, ?VEH_DISPATCHED),
    Returning = phase_count(Db, ?VEH_RETURNING),
    Docked   = phase_count(Db, ?VEH_DOCKED),
    Servicing = phase_count(Db, ?VEH_SERVICING),
    Charging = scalar(esqlite3:q(Db,
        "SELECT count(*) FROM vehicles WHERE (status & ?1) <> 0 AND service_kind='charge';",
        [?VEH_SERVICING])),
    Depleted = phase_count(Db, ?VEH_DEPLETED),
    Trips    = scalar(esqlite3:q(Db, "SELECT coalesce(sum(trips),0) FROM vehicles;")),
    Fares    = scalar(esqlite3:q(Db, "SELECT coalesce(sum(fares_cents),0) FROM vehicles;")),
    #{total => Total,
      cruising => Cruising, dispatched => Dispatched, on_trip => OnTrip,
      returning => Returning, docked => Docked, servicing => Servicing,
      charging => Charging, depleted => Depleted,
      active => Cruising + Dispatched + OnTrip,   %% on the market
      trips => Trips, revenue_cents => Fares}.

do_vehicles(#state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT vehicle_id, company_id, status, battery_pct, x, y,"
        "       facility_id, service_kind, trips, fares_cents FROM vehicles;"),
    [#{vehicle_id => V, company_id => Co, phase => phase_name(St),
       battery_pct => Bat, x => X, y => Y,
       facility_id => Fac, service_kind => Svc,
       trips => Tr, fares_cents => Fc}
     || [V, Co, St, Bat, X, Y, Fac, Svc, Tr, Fc] <- Rows].

do_by_facility(#state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT facility_id, count(*) FROM vehicles"
        " WHERE facility_id IS NOT NULL AND (status & ?1) <> 0"
        " GROUP BY facility_id;", [?VEH_DOCKED bor ?VEH_SERVICING]),
    [#{facility_id => F, vehicles => N} || [F, N] <- Rows].

do_recent(Limit, #state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT vehicle_id, event, at FROM activity ORDER BY id DESC LIMIT ?1;",
        [Limit]),
    [#{vehicle_id => V, event => E, at => At} || [V, E, At] <- Rows].

phase_count(Db, Phase) ->
    scalar(esqlite3:q(Db,
        "SELECT count(*) FROM vehicles WHERE (status & ?1) <> 0;", [Phase])).

%%--------------------------------------------------------------------
%% Phase bit -> name (single set bit; falls back to 'unknown').

phase_name(St) when is_integer(St) ->
    case St of
        ?VEH_COMMISSIONED -> <<"commissioned">>;
        ?VEH_CRUISING     -> <<"cruising">>;
        ?VEH_DISPATCHED   -> <<"dispatched">>;
        ?VEH_ON_TRIP      -> <<"on_trip">>;
        ?VEH_RETURNING    -> <<"returning">>;
        ?VEH_DOCKED       -> <<"docked">>;
        ?VEH_SERVICING    -> <<"servicing">>;
        ?VEH_DEPLETED     -> <<"depleted">>;
        _                 -> <<"unknown">>
    end;
phase_name(_) -> <<"unknown">>.

%%--------------------------------------------------------------------
%% helpers

scalar([[V] | _]) -> V;
scalar(_)         -> 0.

%% esqlite wants numbers, not undefined; coerce undefined -> null via 'undefined'
%% (esqlite maps the atom undefined to SQL NULL).
num(undefined) -> undefined;
num(N) when is_integer(N) -> N;
num(N) when is_float(N)   -> N;
num(_) -> undefined.

default_db_path() ->
    Dir = case os:getenv("HECATE_DATA_DIR") of
              false -> "/tmp/hecate-parksim";
              ""    -> "/tmp/hecate-parksim";
              D     -> D
          end,
    filename:join([Dir, "fleet_read_model.db"]).
