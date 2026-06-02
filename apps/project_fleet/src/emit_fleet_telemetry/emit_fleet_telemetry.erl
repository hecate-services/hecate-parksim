%%% @doc Emits this operator's live vehicle TELEMETRY as a mesh fact, at a
%%% high cadence (default 2s).
%%%
%%% Telemetry is NOT a domain event and NOT from the read model — it is the
%%% live, high-frequency kinematic state held in the fleet brain
%%% (`simulate_fleet:snapshot/0'): each vehicle's current x/y, heading,
%%% battery, and phase. The realm-side consumer plots these as moving dots;
%%% only the sparse milestones become events. Publishing position as a fact
%%% (not an event) is what keeps the J4105s cool — no store writes per move.
%%%
%%% Degrades safely while dark, exactly like the summary emitter.
-module(emit_fleet_telemetry).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([to_fact/1]).   %% exported for tests

-define(DEFAULT_INTERVAL_MS, 2000).

-record(state, {interval :: pos_integer(),
                company  :: binary(),
                topic    :: binary()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Interval = application:get_env(hecate_parksim, telemetry_interval_ms, ?DEFAULT_INTERVAL_MS),
    Company  = list_to_binary(hecate_parksim_service:tenant_id()),
    Topic    = <<"fleet/", Company/binary, "/telemetry">>,
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
            catch macula:publish(Pool, Realm, Topic, Fact),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

%% Live snapshot straight from the fleet brain. The sim may not be up yet
%% (boot race) — fall back to an empty fleet rather than crash.
to_fact(Company) ->
    Vehicles = safe(fun simulate_fleet:snapshot/0, []),
    Rides    = safe(fun simulate_fleet:rides/0, []),
    #{type        => fleet_telemetry,
      company     => Company,
      vehicles    => Vehicles,
      rides       => Rides,
      observed_at => erlang:system_time(millisecond)}.

safe(Fun, Default) ->
    try Fun() of R -> R catch _:_ -> Default end.
