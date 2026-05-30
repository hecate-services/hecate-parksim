%%% @doc SQLite read model for parking sessions — the durable,
%%% queryable system of record (one row per session). The projection
%%% feeds it as events arrive; QRY reads here. Because this is durable,
%%% the event store can be scavenged freely without losing "what
%%% happened".
%%%
%%% Writes are async + batched: `apply_event/1` casts (never blocks the
%%% projection), the store buffers, and flushes in one SQLite
%%% transaction every ~FLUSH_MS or every MAX_BATCH events. A synchronous
%%% call-per-event here previously serialised the whole projection
%%% pipeline into a multi-hundred-MB mailbox/heap → constant GC → pegged
%%% CPU. The DB lives under the tenant's data dir (persistent /bulk),
%%% survives restarts, and is never rebuilt from the (scavenged) event
%%% store — the projection only moves forward.
-module(project_parking_sessions_store).
-behaviour(gen_server).

-include_lib("guide_parking_session_lifecycle/include/parking_session_status.hrl").

-export([start_link/0, apply_event/1, flush_now/0, overview/0, get/1, recent/1]).
-export([due_for_scavenge/2, mark_scavenged/1, lot_in_progress/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(MAX_BATCH, 500).   %% flush immediately once the buffer reaches this
-define(FLUSH_MS,  250).   %% otherwise flush on this cadence

-record(state, {db :: term(),
                buf = [] :: [map()],          %% pending events, newest-first
                flush_pending = false :: boolean()}).

-define(SELECT_COLS,
    "session_id, status, lot_id, bay_id, plate, card_id, permit_ref, "
    "entered_at, docked_at, undocked_at, paid_at, archived_at, amount_cents").
-define(SELECT_ONE,    "SELECT " ?SELECT_COLS " FROM sessions WHERE session_id = ?1;").
-define(SELECT_RECENT, "SELECT " ?SELECT_COLS " FROM sessions ORDER BY entered_at DESC LIMIT ?1;").

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Buffer one event for the read model (called by the projection).
%% Async — never blocks the projection pipeline.
-spec apply_event(map()) -> ok.
apply_event(Event) -> gen_server:cast(?MODULE, {apply_event, Event}).

%% @doc Force a synchronous flush of buffered writes (tests / ops).
-spec flush_now() -> ok.
flush_now() -> gen_server:call(?MODULE, flush).

%% @doc Aggregate overview for the QRY side — counts, revenue, by-status, by-lot.
-spec overview() -> {ok, map()} | {error, term()}.
overview() -> gen_server:call(?MODULE, overview).

%% @doc Live occupancy of a lot — non-archived sessions for that lot. Drives
%% the simulator's capacity enforcement (turn arrivals away when full).
-spec lot_in_progress(binary()) -> {ok, non_neg_integer()} | {error, term()}.
lot_in_progress(LotId) -> gen_server:call(?MODULE, {lot_in_progress, LotId}).

-spec get(binary()) -> {ok, map()} | {error, not_found | term()}.
get(SessionId) -> gen_server:call(?MODULE, {get, SessionId}).

-spec recent(pos_integer()) -> {ok, [map()]} | {error, term()}.
recent(Limit) -> gen_server:call(?MODULE, {recent, Limit}).

%% @doc Session ids archived before CutoffIso whose event streams have
%% not yet been scavenged — drives the retention sweep (O(aged), indexed).
-spec due_for_scavenge(binary() | string(), pos_integer()) -> {ok, [binary()]} | {error, term()}.
due_for_scavenge(CutoffIso, Limit) -> gen_server:call(?MODULE, {due_for_scavenge, CutoffIso, Limit}).

%% @doc Mark a session's events as scavenged so it isn't revisited.
-spec mark_scavenged(binary()) -> ok | {error, term()}.
mark_scavenged(SessionId) -> gen_server:call(?MODULE, {mark_scavenged, SessionId}).

%%--------------------------------------------------------------------

%% The SQLite read model is independent of the reckon-db event store, so
%% open it eagerly here (the PRJ sup boots before the event store exists).
init([]) ->
    {ok, Db} = open(),
    {ok, #state{db = Db}}.

%% Reads (and the infrequent mark_scavenged) are synchronous; they see
%% rows up to the last flush (eventual consistency, ~FLUSH_MS lag).
handle_call(flush, _From, S) ->
    {reply, ok, flush(S#state{flush_pending = false})};
handle_call(Req, _From, #state{db = Db} = S) ->
    {reply, do(Req, Db), S}.

%% Buffer writes; flush on size or on the timer. Never touches SQLite
%% per event, so the mailbox drains instantly.
handle_cast({apply_event, Event}, #state{buf = Buf} = S) ->
    maybe_flush(S#state{buf = [Event | Buf]});
handle_cast(_Msg, S) ->
    {noreply, S}.

handle_info(flush, S) ->
    {noreply, flush(S#state{flush_pending = false})};
handle_info(_Msg, S) ->
    {noreply, S}.

terminate(_R, #state{db = Db, buf = Buf}) ->
    _ = flush_events(Db, Buf),   %% best-effort drain on shutdown
    catch esqlite3:close(Db),
    ok.

%%--------------------------------------------------------------------
%% Write buffering

maybe_flush(#state{buf = Buf} = S) when length(Buf) >= ?MAX_BATCH ->
    {noreply, flush(S#state{flush_pending = false})};
maybe_flush(#state{flush_pending = true} = S) ->
    {noreply, S};
maybe_flush(#state{flush_pending = false} = S) ->
    erlang:send_after(?FLUSH_MS, self(), flush),
    {noreply, S#state{flush_pending = true}}.

%% Flush the buffer in one transaction (oldest-first), one fsync.
flush(#state{buf = []} = S) -> S;
flush(#state{db = Db, buf = Buf} = S) ->
    flush_events(Db, Buf),
    S#state{buf = []}.

flush_events(_Db, []) -> ok;
flush_events(Db, Buf) ->
    Events = lists:reverse(Buf),
    esqlite3:exec(Db, "BEGIN;"),
    lists:foreach(fun(E) -> upsert(Db, E) end, Events),
    esqlite3:exec(Db, "COMMIT;"),
    ok.

%%--------------------------------------------------------------------
%% Request handlers (reads)

do(overview, Db)             -> {ok, build_overview(Db)};
do({lot_in_progress, LotId}, Db) ->
    {ok, scalar(esqlite3:q(Db,
        ["SELECT count(*) FROM sessions WHERE lot_id = ?1 "
         "AND (status & ", i(?SESSION_ARCHIVED), ") = 0;"], [LotId]))};
do({get, Id}, Db)            -> row_to_session(esqlite3:q(Db, ?SELECT_ONE, [Id]));
do({recent, Limit}, Db)      -> {ok, [as_session(R) || R <- esqlite3:q(Db, ?SELECT_RECENT, [Limit])]};
do({due_for_scavenge, Cutoff, Limit}, Db) ->
    Rows = esqlite3:q(Db,
        "SELECT session_id FROM sessions "
        "WHERE archived_at IS NOT NULL AND archived_at < ?1 AND scavenged = 0 "
        "ORDER BY archived_at LIMIT ?2;", [Cutoff, Limit]),
    {ok, [Id || [Id] <- Rows]};
do({mark_scavenged, Id}, Db) ->
    _ = esqlite3:q(Db, "UPDATE sessions SET scavenged = 1 WHERE session_id = ?1;", [Id]),
    ok.

%%--------------------------------------------------------------------
%% Upsert — one row per session, columns filled in as events arrive.

upsert(Db, #{event_type := <<"parking_session_initiated">>} = E) ->
    ins(Db, sid(E), ?SESSION_INITIATED,
        [{lot_id, g(lot_id, E)}, {plate, g(plate, E)}, {card_id, g(card_id, E)},
         {permit_ref, g(permit_ref, E)}, {entered_at, g(entered_at, E)}]);
upsert(Db, #{event_type := <<"vehicle_docked">>} = E) ->
    ins(Db, sid(E), ?SESSION_DOCKED,
        [{bay_id, g(bay_id, E)}, {docked_at, g(docked_at, E)}]);
upsert(Db, #{event_type := <<"vehicle_undocked">>} = E) ->
    ins(Db, sid(E), ?SESSION_UNDOCKED, [{undocked_at, g(undocked_at, E)}]);
upsert(Db, #{event_type := <<"payment_captured">>} = E) ->
    ins(Db, sid(E), ?SESSION_PAID,
        [{amount_cents, g(amount_cents, E)}, {paid_at, g(paid_at, E)}]);
upsert(Db, #{event_type := <<"parking_session_archived">>} = E) ->
    ins(Db, sid(E), ?SESSION_ARCHIVED, [{archived_at, g(archived_at, E)}]);
upsert(_Db, _Other) -> ok.

%% Ensure the row exists with the flag OR'd in, then set the named columns.
ins(Db, SessionId, Flag, Cols) ->
    _ = esqlite3:q(Db,
        "INSERT INTO sessions (session_id, status) VALUES (?1, ?2) "
        "ON CONFLICT(session_id) DO UPDATE SET status = status | excluded.status;",
        [SessionId, Flag]),
    lists:foreach(
        fun({_C, undefined}) -> ok;
           ({C, V}) ->
               _ = esqlite3:q(Db,
                   ["UPDATE sessions SET ", atom_to_list(C), " = ?1 WHERE session_id = ?2;"],
                   [V, SessionId])
        end, Cols),
    ok.

%%--------------------------------------------------------------------
%% Overview (bitwise flag queries; SQLite supports & and |)

build_overview(Db) ->
    One = fun(Sql) -> scalar(esqlite3:q(Db, Sql)) end,
    #{total         => One("SELECT count(*) FROM sessions;"),
      initiated     => One(["SELECT count(*) FROM sessions WHERE status & ", i(?SESSION_INITIATED), ";"]),
      docked        => One(["SELECT count(*) FROM sessions WHERE status & ", i(?SESSION_DOCKED), ";"]),
      paid          => One(["SELECT count(*) FROM sessions WHERE status & ", i(?SESSION_PAID), ";"]),
      archived      => One(["SELECT count(*) FROM sessions WHERE status & ", i(?SESSION_ARCHIVED), ";"]),
      in_progress   => One(["SELECT count(*) FROM sessions WHERE (status & ", i(?SESSION_ARCHIVED), ") = 0;"]),
      revenue_cents => One("SELECT coalesce(sum(amount_cents),0) FROM sessions;"),
      by_lot        => [#{lot_id => L, sessions => N}
                        || [L, N] <- esqlite3:q(Db,
                             "SELECT coalesce(lot_id,'?'), count(*) FROM sessions GROUP BY lot_id ORDER BY 2 DESC;")]}.

%%--------------------------------------------------------------------
%% DB open + schema

open() ->
    DbPath = filename:join([hecate_parksim_service:data_dir(), "read_models",
                            "parking_sessions.sqlite"]),
    ok = filelib:ensure_dir(DbPath),
    {ok, Db} = esqlite3:open(DbPath),
    ok = migrate(Db),
    {ok, Db}.

migrate(Db) ->
    esqlite3:exec(Db,
        "CREATE TABLE IF NOT EXISTS sessions ("
        "  session_id   TEXT PRIMARY KEY,"
        "  status       INTEGER NOT NULL DEFAULT 0,"
        "  lot_id       TEXT, bay_id TEXT, plate TEXT, card_id TEXT, permit_ref TEXT,"
        "  entered_at   TEXT, docked_at TEXT, undocked_at TEXT, paid_at TEXT, archived_at TEXT,"
        "  amount_cents INTEGER,"
        "  scavenged    INTEGER NOT NULL DEFAULT 0"
        ");").

%%--------------------------------------------------------------------
%% Helpers

sid(E) -> g(session_id, E).

%% Read a value by atom OR binary key (events may arrive either way).
g(Key, Map) ->
    case maps:get(Key, Map, undefined) of
        undefined -> maps:get(atom_to_binary(Key, utf8), Map, undefined);
        V -> V
    end.

i(N) -> integer_to_list(N).

scalar([[N] | _]) -> N;
scalar(_)         -> 0.

row_to_session([]) -> {error, not_found};
row_to_session([R | _]) -> {ok, as_session(R)};
row_to_session({error, _} = E) -> E.

as_session([Sid, St, Lot, Bay, Plate, Card, Permit, Ent, Dock, Undock, Paid, Arch, Amt]) ->
    #{session_id => Sid, status => St, lot_id => Lot, bay_id => Bay, plate => Plate,
      card_id => Card, permit_ref => Permit, entered_at => Ent, docked_at => Dock,
      undocked_at => Undock, paid_at => Paid, archived_at => Arch, amount_cents => Amt}.
