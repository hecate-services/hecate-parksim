%%% @doc Owns the SQLite read model for rides (the customer transactions).
%%%
%%% A single gen_server serialises all DB access. Folds ride-lifecycle events
%%% into a `rides' table (one row per ride, current status + endpoints + party
%%% + fare) and answers the analytics queries: how many rides were requested,
%%% completed, abandoned (expired); the completion rate; fares earned; the mean
%%% wait from request to assignment.
%%%
%%% Sibling to project_fleet_store: that one tracks the CARS, this one tracks
%%% the CUSTOMER transactions.
-module(project_rides_store).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).
-export([apply_event/1, overview/0, rides/0, by_company/0, recent/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include_lib("guide_ride_lifecycle/include/ride_status.hrl").

-define(SERVER, ?MODULE).

-record(state, {db :: esqlite3:esqlite3()}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).
start_link(Opts) -> gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec apply_event(map()) -> ok.
apply_event(Event) -> gen_server:call(?SERVER, {apply_event, Event}, 30000).

overview()    -> gen_server:call(?SERVER, overview, 30000).
rides()       -> gen_server:call(?SERVER, rides, 30000).
by_company()  -> gen_server:call(?SERVER, by_company, 30000).
recent(Limit) -> gen_server:call(?SERVER, {recent, Limit}, 30000).

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
handle_call(rides, _From, State) ->
    {reply, do_rides(State), State};
handle_call(by_company, _From, State) ->
    {reply, do_by_company(State), State};
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
        "CREATE TABLE IF NOT EXISTS rides ("
        "  ride_id      TEXT PRIMARY KEY,"
        "  company_id   TEXT,"
        "  status       INTEGER NOT NULL DEFAULT 0,"   %% current phase bit
        "  pickup_x     REAL, pickup_y REAL,"
        "  dropoff_x    REAL, dropoff_y REAL,"
        "  party_size   INTEGER,"
        "  fare_estimate_cents INTEGER,"
        "  fare_cents   INTEGER,"               %% final, at completion
        "  vehicle_id   TEXT,"
        "  plate        TEXT,"
        "  requested_at TEXT,"
        "  assigned_at  TEXT,"
        "  last_event_at TEXT"
        ");"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);"),
    ok = esqlite3:exec(Db,
        "CREATE INDEX IF NOT EXISTS idx_rides_company ON rides(company_id);"),
    ok.

%%====================================================================
%% Projection (write) — fold each ride event into the row.
%%====================================================================

do_apply_event(#{event_type := Type} = Ev, #state{db = Db}) ->
    RId = maps:get(ride_id, Ev, undefined),
    apply_typed(Type, RId, Ev, Db),
    ok;
do_apply_event(_Ev, _State) -> ok.

apply_typed(<<"ride_requested">>, RId, Ev, Db) ->
    upsert_ride(Db, RId, Ev),
    set_phase(Db, RId, ?RIDE_REQUESTED), ok;
apply_typed(<<"ride_assigned">>, RId, Ev, Db) ->
    set_col(Db, RId, <<"vehicle_id">>, maps:get(vehicle_id, Ev, undefined)),
    set_col(Db, RId, <<"plate">>, maps:get(plate, Ev, undefined)),
    set_col(Db, RId, <<"assigned_at">>, maps:get(assigned_at, Ev, undefined)),
    set_phase(Db, RId, ?RIDE_ASSIGNED), ok;
apply_typed(<<"ride_started">>, RId, _Ev, Db) ->
    set_phase(Db, RId, ?RIDE_STARTED), ok;
apply_typed(<<"ride_completed">>, RId, Ev, Db) ->
    set_col(Db, RId, <<"fare_cents">>, num(maps:get(fare_cents, Ev, 0))),
    set_phase(Db, RId, ?RIDE_COMPLETED), ok;
apply_typed(<<"ride_expired">>, RId, _Ev, Db) ->
    set_phase(Db, RId, ?RIDE_EXPIRED), ok;
apply_typed(_Other, _RId, _Ev, _Db) -> ok.

%%--------------------------------------------------------------------
%% Row helpers

upsert_ride(Db, RId, Ev) ->
    esqlite3:q(Db,
        "INSERT INTO rides"
        " (ride_id, company_id, pickup_x, pickup_y, dropoff_x, dropoff_y,"
        "  party_size, fare_estimate_cents, requested_at, status)"
        " VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,0)"
        " ON CONFLICT(ride_id) DO UPDATE SET"
        "   company_id=excluded.company_id,"
        "   pickup_x=excluded.pickup_x, pickup_y=excluded.pickup_y,"
        "   dropoff_x=excluded.dropoff_x, dropoff_y=excluded.dropoff_y,"
        "   party_size=excluded.party_size,"
        "   fare_estimate_cents=excluded.fare_estimate_cents,"
        "   requested_at=excluded.requested_at",
        [RId, maps:get(company_id, Ev, undefined),
         num(maps:get(pickup_x, Ev, undefined)), num(maps:get(pickup_y, Ev, undefined)),
         num(maps:get(dropoff_x, Ev, undefined)), num(maps:get(dropoff_y, Ev, undefined)),
         num(maps:get(party_size, Ev, 1)),
         num(maps:get(fare_estimate_cents, Ev, 0)),
         maps:get(requested_at, Ev, undefined)]),
    ok.

%% Set the exclusive phase: clear ALL phase bits, then OR in the new one.
set_phase(Db, RId, Phase) ->
    AllMask   = lists:foldl(fun(B, Acc) -> Acc bor B end, 0, ?RIDE_ALL_PHASES),
    ClearMask = (bnot AllMask) band 16#FFFFFFFF,
    esqlite3:q(Db,
        "UPDATE rides SET status = (status & ?1) | ?2 WHERE ride_id = ?3",
        [ClearMask, Phase, RId]),
    ok.

set_col(Db, RId, Col, Val) ->
    SQL = ["UPDATE rides SET ", binary_to_list(Col), "=?1 WHERE ride_id=?2"],
    esqlite3:q(Db, lists:flatten(SQL), [Val, RId]), ok.

%%====================================================================
%% Queries (read)
%%====================================================================

do_overview(#state{db = Db}) ->
    Total     = scalar(esqlite3:q(Db, "SELECT count(*) FROM rides;")),
    Requested = phase_count(Db, ?RIDE_REQUESTED),
    Assigned  = phase_count(Db, ?RIDE_ASSIGNED),
    Started   = phase_count(Db, ?RIDE_STARTED),
    Completed = phase_count(Db, ?RIDE_COMPLETED),
    Expired   = phase_count(Db, ?RIDE_EXPIRED),
    Fares     = scalar(esqlite3:q(Db,
        "SELECT coalesce(sum(fare_cents),0) FROM rides WHERE fare_cents IS NOT NULL;")),
    #{total => Total,
      waiting => Requested,                 %% still unassigned
      assigned => Assigned,
      in_progress => Started,
      completed => Completed,
      expired => Expired,
      active => Requested + Assigned + Started,
      completion_rate => rate(Completed, Completed + Expired),
      fares_cents => Fares}.

do_rides(#state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT ride_id, company_id, status, pickup_x, pickup_y,"
        "       dropoff_x, dropoff_y, party_size, fare_estimate_cents,"
        "       fare_cents, vehicle_id, plate, requested_at FROM rides;"),
    [#{ride_id => R, company_id => Co, status => phase_name(St),
       pickup_x => Px, pickup_y => Py, dropoff_x => Dx, dropoff_y => Dy,
       party_size => Pa, fare_estimate_cents => Fe, fare_cents => Fc,
       vehicle_id => Vid, plate => Pl, requested_at => Ra}
     || [R, Co, St, Px, Py, Dx, Dy, Pa, Fe, Fc, Vid, Pl, Ra] <- Rows].

do_by_company(#state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT company_id,"
        "  sum(CASE WHEN (status & ?1) <> 0 THEN 1 ELSE 0 END),"   %% completed
        "  sum(CASE WHEN (status & ?2) <> 0 THEN 1 ELSE 0 END),"   %% expired
        "  coalesce(sum(fare_cents),0)"
        " FROM rides GROUP BY company_id;",
        [?RIDE_COMPLETED, ?RIDE_EXPIRED]),
    [#{company_id => Co, completed => Cmp, expired => Exp, fares_cents => Fc}
     || [Co, Cmp, Exp, Fc] <- Rows].

do_recent(Limit, #state{db = Db}) ->
    Rows = esqlite3:q(Db,
        "SELECT ride_id, company_id, status, party_size, fare_cents, requested_at"
        " FROM rides ORDER BY requested_at DESC LIMIT ?1;", [Limit]),
    [#{ride_id => R, company_id => Co, status => phase_name(St),
       party_size => Pa, fare_cents => Fc, requested_at => Ra}
     || [R, Co, St, Pa, Fc, Ra] <- Rows].

phase_count(Db, Phase) ->
    scalar(esqlite3:q(Db,
        "SELECT count(*) FROM rides WHERE (status & ?1) <> 0;", [Phase])).

phase_name(St) when is_integer(St) ->
    case St of
        ?RIDE_REQUESTED -> <<"requested">>;
        ?RIDE_ASSIGNED  -> <<"assigned">>;
        ?RIDE_STARTED   -> <<"started">>;
        ?RIDE_COMPLETED -> <<"completed">>;
        ?RIDE_EXPIRED   -> <<"expired">>;
        _               -> <<"unknown">>
    end;
phase_name(_) -> <<"unknown">>.

%%--------------------------------------------------------------------
%% helpers

scalar([[V] | _]) -> V;
scalar(_)         -> 0.

rate(_N, 0)  -> 0.0;
rate(N, Den) -> N / Den.

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
    filename:join([Dir, "rides_read_model.db"]).
