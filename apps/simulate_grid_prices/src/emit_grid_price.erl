%%% @doc Emits this region's grid price as an integration FACT on the Macula
%%% mesh, on a cadence, and feeds it to the local charging scheduler.
%%%
%%% The provider half of the charging federation. The price follows the
%%% simulated day (overnight trough -> shoulder -> daytime peak), with a small
%%% deterministic per-region offset so the regional view is not uniform. The
%%% fact is an explicit, stable public contract — NOT a bridge of internal
%%% events; the topic is `energy/<region>/grid_price'.
%%%
%%% Two deliveries per tick:
%%%   - ALWAYS cast the price to the local `on_grid_price_changed_schedule_charging'
%%%     PM (the mesh does not loop a node's own publish back to it, so the
%%%     operative tariff must be delivered in-process);
%%%   - on the store's Ra LEADER only, publish the fact to the mesh, so the mesh
%%%     sees one publisher per region and peers assemble the regional view.
%%%
%%% Mesh access degrades safely: while the service is dark the publish is simply
%%% skipped; the local scheduler keeps working from the in-process price.
-module(emit_grid_price).
-behaviour(gen_server).

-include_lib("guide_charging_lifecycle/include/grid_tariff.hrl").

-export([start_link/0]).
-export([price_now/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DEFAULT_INTERVAL_MS, 10000).
-define(SECONDS_PER_DAY, 86400).

-record(state, {interval :: pos_integer(),
                region   :: binary(),
                topic    :: binary()}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc The current regional price fact (also useful for tests / inspection).
-spec price_now() -> map().
price_now() ->
    Region = list_to_binary(hecate_parksim_service:tenant_id()),
    build_fact(Region).

init([]) ->
    Interval = application:get_env(hecate_parksim, grid_price_interval_ms, ?DEFAULT_INTERVAL_MS),
    Region   = list_to_binary(hecate_parksim_service:tenant_id()),
    Topic    = <<"energy/", Region/binary, "/grid_price">>,
    erlang:send_after(Interval, self(), tick),
    {ok, #state{interval = Interval, region = Region, topic = Topic}}.

handle_info(tick, #state{interval = Interval, region = Region} = S) ->
    Fact = build_fact(Region),
    %% Local scheduler always gets this region's price (no mesh loopback).
    catch on_grid_price_changed_schedule_charging:note_local_price(Fact),
    %% Only the leader publishes the fact to the mesh.
    case hecate_parksim_service:is_leader() of
        true  -> _ = publish(S, Fact);
        false -> ok
    end,
    erlang:send_after(Interval, self(), tick),
    {noreply, S};
handle_info(_Msg, S) ->
    {noreply, S}.

handle_call(_Req, _From, S) -> {reply, ok, S}.
handle_cast(_Msg, S)        -> {noreply, S}.

%%--------------------------------------------------------------------

publish(#state{topic = Topic}, Fact) ->
    case {hecate_om:macula_client(), hecate_om_identity:realm()} of
        {{ok, Pool}, {ok, Realm}} ->
            %% Pass the map as a term — the V2 mesh wire is CBOR; never
            %% json-encode a publish payload.
            catch macula:publish(Pool, Realm, Topic, Fact),
            ok;
        _DarkOrNoRealm ->
            ok
    end.

%% The public integration-fact contract: region, price, window, validity.
build_fact(Region) ->
    Hour   = sim_hour_of_day(),
    {Window, Base} = band_for(Hour),
    Cents  = Base + region_offset(Region),
    #{type        => grid_price_changed,
      region      => Region,
      cents       => Cents,
      window      => Window,
      hour        => Hour,
      valid_until => erlang:system_time(millisecond) + 60000,
      observed_at => erlang:system_time(millisecond)}.

%% Simulated hour-of-day (0..23). Real time is compressed by the sim `scale',
%% so the tariff visibly cycles through a full day within a demo.
sim_hour_of_day() ->
    Scale   = max(1, round(simulate_clock:scale())),
    SimSecs = (simulate_clock:now_unix() * Scale) rem ?SECONDS_PER_DAY,
    SimSecs div 3600.

%% Three-band tariff: overnight trough, shoulders, daytime/evening peak.
band_for(H) when H >= 23; H < 7   -> {<<"off_peak">>, ?OFFPEAK_CENTS_PER_KWH};
band_for(H) when H >= 7,  H < 10  -> {<<"peak">>,     ?PEAK_CENTS_PER_KWH};
band_for(H) when H >= 17, H < 22  -> {<<"peak">>,     ?PEAK_CENTS_PER_KWH};
band_for(_H)                      -> {<<"shoulder">>, ?SHOULDER_CENTS_PER_KWH}.

%% Deterministic per-region offset in [-2, +3] cents, so regions differ.
region_offset(Region) ->
    <<B, _/binary>> = crypto:hash(md5, Region),
    (B rem 6) - 2.
