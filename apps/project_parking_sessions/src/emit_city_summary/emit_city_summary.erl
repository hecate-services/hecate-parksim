%%% @doc Emits this city's parking summary as an integration FACT on the
%%% Macula mesh, on a fixed cadence.
%%%
%%% This is the publisher half of "mesh parksim". The fact is an explicit,
%%% stable public contract — a per-city occupancy/revenue summary derived
%%% from the local read model — NOT a bridge of internal domain events.
%%% A realm-side consumer subscribes to `parking/+/summary' to assemble the
%%% federated view (e.g. the parksim dashboard).
%%%
%%% Mesh access degrades safely: while the service is dark (no cert / no
%%% station seeds) `hecate_om:macula_client/0' returns `{error, _}', so a
%%% tick is simply skipped and retried on the next one. Nothing here can
%%% disturb the simulator or the store.
-module(emit_city_summary).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_INTERVAL_MS, 5000).

-record(state, {interval :: pos_integer(),
                city     :: binary(),
                topic    :: binary()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Interval = application:get_env(hecate_parksim, summary_interval_ms, ?DEFAULT_INTERVAL_MS),
    City     = list_to_binary(hecate_parksim_service:tenant_id()),
    Topic    = <<"parking/", City/binary, "/summary">>,
    erlang:send_after(Interval, self(), tick),
    {ok, #state{interval = Interval, city = City, topic = Topic}}.

handle_info(tick, #state{interval = Interval} = S) ->
    _ = publish(S),
    erlang:send_after(Interval, self(), tick),
    {noreply, S};
handle_info(_Msg, S) ->
    {noreply, S}.

handle_call(_Req, _From, S) -> {reply, ok, S}.
handle_cast(_Msg, S)        -> {noreply, S}.

%%--------------------------------------------------------------------

%% Publish only when the mesh client AND the realm are both available;
%% otherwise the service is dark — skip this tick, retry on the next.
publish(#state{city = City, topic = Topic}) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            case project_parking_sessions_store:overview() of
                {ok, Overview} ->
                    Fact = to_fact(City, Overview),
                    %% Pass the map as a term — the V2 mesh wire is CBOR;
                    %% never json-encode a publish payload.
                    catch macula:publish(Pool, Realm, Topic, Fact),
                    ok;
                {error, _} ->
                    ok
            end;
        _DarkOrNoRealm ->
            ok
    end.

%% The public integration-fact contract. Deliberately a stable subset of
%% the read model; internal event/read-model shapes can change without
%% breaking mesh consumers.
to_fact(City, O) ->
    #{type          => parking_city_summary,
      city          => City,
      parked_now    => g(in_progress, O),
      total         => g(total, O),
      revenue_cents => g(revenue_cents, O),
      by_lot        => g(by_lot, O),
      observed_at   => erlang:system_time(millisecond)}.

g(K, M) -> maps:get(K, M, 0).
