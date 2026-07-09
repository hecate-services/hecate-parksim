%%% @doc Emits this operator's energy summary as an integration FACT on the
%%% Macula mesh, on a fixed cadence.
%%%
%%% The publisher half of the charging story. The fact is an explicit, stable
%%% public contract — a per-operator rollup (sessions, kWh, cost, off-peak
%%% share) derived from the local `project_energy' read model, plus the current
%%% regional grid price from the charging PM — NOT a bridge of internal events.
%%% The realm-side ClankerCab consumer subscribes to `energy/+/summary' to render
%%% the Energy card.
%%%
%%% Follow-the-leader: only the store's Ra leader publishes, so the mesh sees
%%% one publisher per operator. Mesh access degrades safely — a dark tick is
%%% skipped and retried; nothing here can disturb the store.
-module(emit_energy_summary).
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
    Topic    = <<"energy/", Company/binary, "/summary">>,
    erlang:send_after(Interval, self(), tick),
    {ok, #state{interval = Interval, company = Company, topic = Topic}}.

handle_info(tick, #state{interval = Interval} = S) ->
    case hecate_parksim_service:is_leader() of
        true  -> _ = publish(S);
        false -> ok
    end,
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

%% The public integration-fact contract: the operator's energy rollup plus the
%% live regional grid price. A stable subset of the read model; internal shapes
%% can change without breaking mesh consumers. Degrades to empty defaults at
%% boot (store or PM may not be up yet); never crash the emitter.
to_fact(Company) ->
    S = safe(fun project_energy_store:summary/0, #{}),
    {GridCents, GridOffPeak} = grid_now(),
    #{type              => energy_summary,
      company           => Company,
      sessions          => g(sessions, S),
      settled           => g(settled, S),
      energy_kwh        => g(energy_kwh, S),
      cost_cents        => g(cost_cents, S),
      off_peak_sessions => g(off_peak_sessions, S),
      off_peak_pct      => g(off_peak_pct, S),
      avg_tariff_cents  => g(avg_tariff_cents, S),
      grid_cents        => GridCents,
      grid_off_peak     => GridOffPeak,
      observed_at       => erlang:system_time(millisecond)}.

%% Current regional grid price from the charging PM, or nulls when no signal.
grid_now() ->
    case safe(fun on_grid_price_changed_schedule_charging:current_tariff/0,
              {error, no_signal}) of
        {ok, Cents, OffPeak} -> {Cents, OffPeak};
        _                    -> {null, null}
    end.

g(K, M) -> maps:get(K, M, 0).

safe(Fun, Default) ->
    try Fun() of R -> R catch _:_ -> Default end.
