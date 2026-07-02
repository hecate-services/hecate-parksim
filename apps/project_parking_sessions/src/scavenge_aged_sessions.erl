%%% @doc Retention sweep — bounds the event store using the read model.
%%%
%%% The SQLite read model is the durable system of record, so raw event
%%% streams are disposable once a session has aged out. Each cycle this
%%% asks the read model (indexed, O(aged)) for sessions archived before
%%% the retention window whose streams aren't yet scavenged, deletes
%%% their events (require_snapshot=false — the read model is the
%%% durable record, no snapshot needed), and marks them scavenged.
%%%
%%% No event-store enumeration, no per-stream polling — that's what
%%% pegged the weak beam CPUs in the earlier design.
-module(scavenge_aged_sessions).
-behaviour(gen_server).

-export([start_link/0, sweep_now/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_INTERVAL_MS, 60000).    %% check the read model every 60s
-define(DEFAULT_WINDOW_MS,   1800000).  %% keep raw events 30 min real
-define(DEFAULT_BATCH,       500).      %% scavenge at most N streams per cycle

-record(st, {store :: atom(), interval_ms :: pos_integer(),
             window_ms :: non_neg_integer(), batch :: pos_integer()}).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec sweep_now() -> ok.
sweep_now() -> gen_server:cast(?MODULE, sweep).

init([]) ->
    St = #st{store       = hecate_parksim_service:store_id(),
             interval_ms = cfg(retention_interval_ms, ?DEFAULT_INTERVAL_MS),
             window_ms   = cfg(retention_window_ms, ?DEFAULT_WINDOW_MS),
             batch       = cfg(retention_batch, ?DEFAULT_BATCH)},
    erlang:send_after(St#st.interval_ms, self(), sweep),
    {ok, St}.

handle_call(_Req, _From, St) -> {reply, {error, unsupported}, St}.
handle_cast(sweep, St) -> do_sweep(St), {noreply, St};
handle_cast(_Msg, St)  -> {noreply, St}.

handle_info(sweep, #st{interval_ms = Ms} = St) ->
    %% Follow-the-leader: retention deletes are issued only by the store's
    %% Ra leader, so the sweep runs once cluster-wide, not once per replica.
    case hecate_parksim_service:is_leader() of
        true  -> do_sweep(St);
        false -> ok
    end,
    erlang:send_after(Ms, self(), sweep),
    {noreply, St};
handle_info(_Msg, St) -> {noreply, St}.

%%--------------------------------------------------------------------

do_sweep(#st{store = Store, window_ms = WindowMs, batch = Batch}) ->
    CutoffIso = iso8601(erlang:system_time(second) - (WindowMs div 1000)),
    case project_parking_sessions_store:due_for_scavenge(CutoffIso, Batch) of
        {ok, Ids}      -> lists:foreach(fun(Id) -> scavenge_one(Store, Id) end, Ids);
        {error, Reason} ->
            logger:warning("[scavenge_aged_sessions] due query failed: ~p", [Reason])
    end.

scavenge_one(Store, SessionId) ->
    %% Delete all events of this aged session; the read-model row is the
    %% durable record, so no snapshot is required.
    Opts = #{before => erlang:system_time(microsecond), require_snapshot => false},
    case reckon_gater_api:scavenge(Store, SessionId, Opts) of
        {ok, _}         -> project_parking_sessions_store:mark_scavenged(SessionId);
        {error, Reason} ->
            logger:warning("[scavenge_aged_sessions] scavenge ~s failed: ~p", [SessionId, Reason])
    end.

%%--------------------------------------------------------------------

%% ISO-8601 UTC for a unix-second timestamp (matches simulate_clock's
%% real-time stamps stored in archived_at).
iso8601(UnixSec) ->
    {{Y, Mo, D}, {H, Mi, S}} =
        calendar:system_time_to_universal_time(UnixSec, second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).

cfg(Key, Default) ->
    case application:get_env(hecate_parksim, Key, Default) of
        N when is_integer(N), N > 0 -> N;
        _                           -> Default
    end.
