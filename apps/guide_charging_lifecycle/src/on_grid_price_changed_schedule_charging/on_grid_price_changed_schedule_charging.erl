%%% @doc Process manager: react to the mesh grid-price FACT by shaping this
%%% edge's charging schedule — with NO central charging controller.
%%%
%%% This is the decentralized-coordination NFR made tangible. A
%%% `grid_price_changed' integration fact propagates across the mesh (topic
%%% `energy/<region>/grid_price', published by `simulate_grid_prices'). Every
%%% edge runs this PM; it holds the OPERATIVE tariff (its own region's latest
%%% price) and answers charge-now-vs-defer for the local scheduler. The fleet's
%%% aggregate charging behaviour EMERGES from fact propagation, not a dispatcher.
%%%
%%% Sovereignty boundary: the operative tariff for the local region arrives via
%%% an in-process cast from the local producer (the mesh does not loop a node's
%%% own publish back to it). Peer regions' prices arrive over the mesh and feed
%%% only the regional VIEW — charging decisions stay local.
%%%
%%% Lives in the TARGET domain (charging) per the cross-domain-via-PM rule: it
%%% consumes an external fact and shapes local commands. Mesh access degrades
%%% safely — while the service is dark the subscribe is retried, and the
%%% scheduler simply falls back to charging whenever a vehicle needs it.
-module(on_grid_price_changed_schedule_charging).
-behaviour(gen_server).

-include_lib("guide_charging_lifecycle/include/grid_tariff.hrl").

-export([start_link/0]).
-export([current_tariff/0, should_defer/1, regional_view/0, note_local_price/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Below this SoC a charge is never deferred, however dear the grid — a robotaxi
%% that can't finish its next trip earns nothing.
-define(CRITICAL_SOC_PCT, 22).
-define(RESUBSCRIBE_MS, 15000).
-define(TOPIC, <<"energy/+/grid_price">>).

-record(state, {
    region   :: binary(),
    sub_ref  :: reference() | undefined,
    operative :: #{cents := number(), window := binary(), at := integer()} | undefined,
    regions = #{} :: #{binary() => map()}   %% region => last fact (regional view)
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% API — read by the local charging scheduler (the sim)

%% @doc The operative tariff for this edge's region, or `{error, no_signal}'
%% until the first price has been seen.
-spec current_tariff() -> {ok, number(), boolean()} | {error, no_signal}.
current_tariff() -> gen_server:call(?MODULE, current_tariff).

%% @doc Should a non-critical charge be deferred right now? True only when the
%% grid is expensive AND the battery is not critically low. No signal => never
%% defer (charge as the fleet always did).
-spec should_defer(number()) -> boolean().
should_defer(BatteryPct) -> gen_server:call(?MODULE, {should_defer, BatteryPct}).

%% @doc The cross-region price map assembled from mesh facts (for display).
-spec regional_view() -> #{binary() => map()}.
regional_view() -> gen_server:call(?MODULE, regional_view).

%% @doc In-process delivery of THIS region's freshly-produced price (the mesh
%% does not loop a node's own publish back), so the operative tariff is live
%% even on the producer's own edge.
-spec note_local_price(map()) -> ok.
note_local_price(Fact) -> gen_server:cast(?MODULE, {local_price, Fact}).

%%--------------------------------------------------------------------
%% gen_server

init([]) ->
    Region = list_to_binary(hecate_parksim_service:tenant_id()),
    self() ! subscribe,
    {ok, #state{region = Region}}.

handle_call(current_tariff, _From, #state{operative = undefined} = S) ->
    {reply, {error, no_signal}, S};
handle_call(current_tariff, _From, #state{operative = #{cents := C}} = S) ->
    {reply, {ok, C, C =< ?OFF_PEAK_MAX_CENTS}, S};
handle_call({should_defer, BatteryPct}, _From, S) ->
    {reply, defer(BatteryPct, S#state.operative), S};
handle_call(regional_view, _From, S) ->
    {reply, S#state.regions, S};
handle_call(_Req, _From, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast({local_price, Fact}, #state{region = Region} = S) ->
    Op = #{cents  => num(fact_get(cents, Fact), 0),
           window => bin(fact_get(window, Fact), <<"unknown">>),
           at     => erlang:system_time(millisecond)},
    Regions = maps:put(Region, Fact, S#state.regions),
    {noreply, S#state{operative = Op, regions = Regions}};
handle_cast(_Msg, S) ->
    {noreply, S}.

handle_info(subscribe, S) ->
    {noreply, try_subscribe(S)};
handle_info({macula_event, _Ref, Topic, Payload, _Meta}, S) ->
    %% A peer region's price. Feeds only the regional view — never overrides the
    %% operative tariff, which is this region's own locally-produced price.
    {noreply, S#state{regions = record_region(Topic, Payload, S#state.regions)}};
handle_info(_Info, S) ->
    {noreply, S}.

%%--------------------------------------------------------------------
%% Internals

%% Defer a non-critical charge only when the grid is dear. No signal, or a
%% critically low battery, never defers.
defer(_BatteryPct, undefined) -> false;
defer(BatteryPct, _Op) when is_number(BatteryPct), BatteryPct =< ?CRITICAL_SOC_PCT -> false;
defer(_BatteryPct, #{cents := C}) -> C > ?CHARGE_DEFER_ABOVE_CENTS.

try_subscribe(#state{sub_ref = Ref} = S) when is_reference(Ref) ->
    S;   %% already subscribed
try_subscribe(S) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            case catch macula:subscribe(Pool, Realm, ?TOPIC, self()) of
                {ok, Ref} -> S#state{sub_ref = Ref};
                _         -> schedule_resubscribe(), S
            end;
        _DarkOrNoRealm ->
            schedule_resubscribe(),
            S
    end.

schedule_resubscribe() ->
    erlang:send_after(?RESUBSCRIBE_MS, self(), subscribe).

record_region(Topic, Payload, Regions) ->
    case region_of(Topic) of
        undefined -> Regions;
        Region    -> maps:put(Region, normalise(Payload), Regions)
    end.

%% Topic is `energy/<region>/grid_price'.
region_of(Topic) when is_binary(Topic) ->
    case binary:split(Topic, <<"/">>, [global]) of
        [<<"energy">>, Region, <<"grid_price">>] -> Region;
        _ -> undefined
    end;
region_of(_) -> undefined.

%% CBOR round-trips can wrap keys/values; keep only what we display, coerced.
normalise(P) when is_map(P) ->
    #{region => bin(fact_get(region, P), <<>>),
      cents  => num(fact_get(cents, P), 0),
      window => bin(fact_get(window, P), <<"unknown">>)};
normalise(_) -> #{}.

%% Read a key from a fact map tolerant of atom/binary keys.
fact_get(K, M) when is_map(M) ->
    case maps:find(K, M) of
        {ok, V} -> V;
        error   -> maps:get(atom_to_binary(K, utf8), M, undefined)
    end;
fact_get(_, _) -> undefined.

num(N, _) when is_number(N) -> N;
num(_, D) -> D.

bin(B, _) when is_binary(B) -> B;
bin(_, D) -> D.
