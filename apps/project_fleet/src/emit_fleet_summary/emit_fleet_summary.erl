%%% @doc Emits this operator's fleet summary as an integration FACT on the
%%% Macula mesh, on a fixed cadence.
%%%
%%% The fact is an explicit, stable public contract — a per-operator rollup
%%% (phase counts, trips, revenue, per-facility occupancy) derived from the
%%% local read model — NOT a bridge of internal domain events. The realm-side
%%% consumer subscribes to `fleet/+/summary' to assemble the city view.
%%%
%%% Mesh access degrades safely: while the service is dark (no mesh client /
%%% no realm) `hecate_om:macula_client/0' returns `{error, _}', so a tick is
%%% simply skipped and retried. Nothing here can disturb the sim or store.
-module(emit_fleet_summary).
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
    Interval = application:get_env(hecate_parksim, summary_interval_ms, ?DEFAULT_INTERVAL_MS),
    Company  = list_to_binary(hecate_parksim_service:tenant_id()),
    Topic    = <<"fleet/", Company/binary, "/summary">>,
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

%% The public integration-fact contract: a stable rollup of the operator's
%% fleet. CQRS split by data NATURE:
%%   * Live phase distribution (how many cabs are cruising / on_trip / ...
%%     right now) is current operational state — taken from the fleet brain
%%     (`simulate_fleet:snapshot/0'), the SAME source the telemetry emitter
%%     uses, so summary and telemetry are always consistent.
%%   * Lifetime tallies (trips completed, revenue earned) and facility
%%     occupancy are genuinely accumulated history — taken from the
%%     event-sourced read model (`project_fleet_store').
%% Both degrade safely to empty defaults at boot (the sim or the store may
%% not be up yet); never let that crash the emitter.
to_fact(Company) ->
    Snap   = safe(fun simulate_fleet:snapshot/0, []),
    Counts = phase_counts(Snap),
    Ov     = safe(fun project_fleet_store:overview/0, #{}),   %% lifetime tallies
    Fac    = safe(fun project_fleet_store:by_facility/0, []),
    Cruising   = c(cruising, Counts),
    Dispatched = c(dispatched, Counts),
    OnTrip     = c(on_trip, Counts),
    #{type          => fleet_summary,
      company       => Company,
      total         => length(Snap),
      %% commissioned cabs (only at the very first tick) fold into cruising.
      cruising      => Cruising + c(commissioned, Counts),
      dispatched    => Dispatched,
      on_trip       => OnTrip,
      returning     => c(returning, Counts),
      docked        => c(docked, Counts),
      servicing     => c(servicing, Counts),
      %% the brain snapshot carries no service_kind, so 'charging' (a subset
      %% of servicing) comes from the read model; 0 until trips accrue there.
      charging      => g(charging, Ov),
      depleted      => c(depleted, Counts),
      active        => Cruising + Dispatched + OnTrip,   %% on the market
      trips         => g(trips, Ov),
      revenue_cents => g(revenue_cents, Ov),
      facilities    => Fac,
      observed_at   => erlang:system_time(millisecond)}.

%% Count live vehicles by phase atom from the brain snapshot.
phase_counts(Snap) ->
    lists:foldl(
      fun(V, Acc) ->
          P = maps:get(phase, V, undefined),
          maps:update_with(P, fun(N) -> N + 1 end, 1, Acc)
      end, #{}, Snap).

c(Phase, Counts) -> maps:get(Phase, Counts, 0).

g(K, M) -> maps:get(K, M, 0).

%% Read models may be momentarily unavailable at boot; never let that crash
%% the emitter — fall back to the empty default and try again next tick.
safe(Fun, Default) ->
    try Fun() of R -> R catch _:_ -> Default end.
