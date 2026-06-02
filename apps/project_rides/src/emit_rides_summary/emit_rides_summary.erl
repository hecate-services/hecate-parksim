%%% @doc Emits this operator's ride rollup as an integration FACT on the
%%% Macula mesh, on a fixed cadence.
%%%
%%% The fact is the explicit, stable public contract that lets the realm build
%%% a FEDERATED ride view — the demand-side story the vehicle summary can't
%%% tell: how many rides were requested, served (completed), or abandoned
%%% (expired), and the fares earned. Derived from the local rides read model
%%% (project_rides_store); NOT a bridge of internal ride domain events.
%%%
%%% Mesh access degrades safely: while the service is dark (no mesh client /
%%% no realm) the tick is simply skipped and retried.
-module(emit_rides_summary).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([to_fact/1]).   %% exported for tests

-define(DEFAULT_INTERVAL_MS, 5000).

-record(state, {interval :: pos_integer(),
                company  :: binary(),
                topic    :: binary()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Interval = application:get_env(hecate_parksim, rides_summary_interval_ms,
                                   ?DEFAULT_INTERVAL_MS),
    Company  = list_to_binary(hecate_parksim_service:tenant_id()),
    Topic    = <<"fleet/", Company/binary, "/rides">>,
    erlang:send_after(Interval, self(), tick),
    {ok, #state{interval = Interval, company = Company, topic = Topic}}.

handle_info(tick, #state{interval = Interval} = S) ->
    _ = publish(S),
    erlang:send_after(Interval, self(), tick),
    {noreply, S};
handle_info(_Msg, S) ->
    {noreply, S}.

handle_call(_Req, _From, S) -> {reply, ok, S}.
handle_cast(_Msg, S)        -> {noreply, S}.

%%--------------------------------------------------------------------

publish(#state{company = Company, topic = Topic}) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            Fact = to_fact(Company),
            %% Pass the map as a term — V2 wire is CBOR; never JSON-encode.
            catch macula:publish(Pool, Realm, Topic, Fact),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

%% The public integration-fact contract: this operator's ride rollup. Raw
%% counts (not a pre-computed rate) so the realm can sum across operators and
%% derive the CITY completion rate itself. Lifetime tallies (completed /
%% expired / fares) come from the event-sourced read model; waiting / active
%% are the current backlog. Degrades to empty defaults at boot.
to_fact(Company) ->
    Ov = safe(fun project_rides_store:overview/0, #{}),
    #{type        => rides_summary,
      company     => Company,
      total       => g(total, Ov),
      waiting     => g(waiting, Ov),
      active      => g(active, Ov),
      completed   => g(completed, Ov),
      expired     => g(expired, Ov),
      fares_cents => g(fares_cents, Ov),
      observed_at => erlang:system_time(millisecond)}.

g(K, M) -> maps:get(K, M, 0).

safe(Fun, Default) ->
    try Fun() of R -> R catch _:_ -> Default end.
