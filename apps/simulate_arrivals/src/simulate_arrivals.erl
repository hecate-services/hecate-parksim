%%% @doc Per-lot arrivals worker. Generates vehicle arrival timestamps
%%% via a non-homogeneous Poisson process (Lewis-Shedler thinning) and
%%% spawns a session process at each arrival.
-module(simulate_arrivals).
-behaviour(gen_server).

-export([start_link/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include_lib("parksim_simulator/include/parksim_simulator_scenario.hrl").

-record(state, {
    lot       :: #parksim_lot{},
    plates    :: parksim_simulator_plates:pool(),
    base_rate :: float(),    %% λ_base in arrivals per minute
    profile   :: profile(),
    rng       :: rand:state()
}).

-type profile() :: city_centre | station | residential.

start_link(Name, Lot, Plates, Idx) ->
    gen_server:start_link({local, Name}, ?MODULE, [Lot, Plates, Idx], []).

init([Lot, Plates, Idx]) ->
    Preset = parksim_simulator_config:preset(),
    %% Spread base rate evenly across lots; the peak factor (~1.8) is
    %% absorbed by the profile so PeakLambda corresponds to peak hour.
    NumLots = length(Preset#parksim_preset.lots),
    BaseRate = (Preset#parksim_preset.peak_lambda_per_min / 1.8) / NumLots,
    Seed = parksim_simulator_config:seed() + Idx * 101,
    Rng  = rand:seed_s(exsss, {Seed, Seed, Seed}),
    State = #state{
        lot       = Lot,
        plates    = Plates,
        base_rate = BaseRate,
        profile   = Lot#parksim_lot.profile,
        rng       = Rng
    },
    self() ! tick,
    {ok, State}.

handle_call(_Msg, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)         -> {noreply, State}.

handle_info(tick, State) ->
    %% Follow-the-leader: only the Ra leader of the tenant store
    %% generates arrivals. Followers re-check on a slow cadence
    %% (no busy-loop) so failover activates near-instantly.
    case hecate_parksim_service:is_leader() of
        true ->
            NewState = fire_one(State),
            self() ! tick,
            {noreply, NewState};
        false ->
            erlang:send_after(5000, self(), tick),
            {noreply, State}
    end;
handle_info(_Other, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

%%--------------------------------------------------------------------
%% NHPP — Lewis–Shedler thinning

fire_one(State) ->
    Now = erlang:system_time(second),
    {GapSec, State1} = sample_gap(Now, State),
    simulate_clock:sleep_simulated(GapSec * 1000),
    {Plate, Rng1} = parksim_simulator_plates:draw(
        State1#state.rng, State1#state.plates),
    PlateValue = maps:get(value, Plate),
    {U, Rng2} = rand:uniform_s(Rng1),
    Lot = State1#state.lot,
    case lot_full(Lot) of
        true ->
            %% Lot at capacity — the car is turned away (no session). This
            %% bounds occupancy: parked-now sits around capacity with
            %% turnover instead of growing without limit.
            State1#state{rng = Rng2};
        false ->
            Credential = decide_credential(
                U, Lot#parksim_lot.permit_share, PlateValue),
            {ok, _} = simulate_visit:start_visit(#{
                lot        => Lot,
                plate      => PlateValue,
                credential => Credential
            }),
            State1#state{rng = Rng2}
    end.

%% Live occupancy from the read model (non-archived sessions for this lot).
%% Fail OPEN if the read model isn't reachable yet (early boot) — admit
%% rather than stall the simulation.
lot_full(#parksim_lot{id = LotId, capacity = Cap}) ->
    case catch project_parking_sessions_store:lot_in_progress(LotId) of
        {ok, N} when is_integer(N) -> N >= Cap;
        _                          -> false
    end.

%% A fraction of arrivals (the lot's permit_share) are permit holders;
%% the rest take a ticket. Permit visits carry a permit_ref derived from
%% the plate (server-side validity is a documented TODO on the islands).
decide_credential(U, PermitShare, Plate) when U < PermitShare ->
    {permit, <<"permit-", Plate/binary>>};
decide_credential(_U, _PermitShare, _Plate) ->
    ticket.

%% Sample the next inter-arrival gap (in seconds) by thinning. We
%% compute λ_max over a 6-hour lookahead and accept candidate gaps
%% with probability λ(t)/λ_max.
sample_gap(StartUnixS, State) ->
    LambdaMax = lambda_max(StartUnixS, State),
    sample_gap_loop(StartUnixS, 0.0, LambdaMax, State, 0).

sample_gap_loop(_StartUnixS, Acc, _LambdaMax, State, N) when N > 10000 ->
    %% Safety bail — should never happen for sane rates.
    {round(Acc), State};
sample_gap_loop(StartUnixS, Acc, LambdaMax, State, N) ->
    {U, S1}  = rand:uniform_s(State#state.rng),
    U2       = max(U, 1.0e-12),
    GapMin   = -math:log(U2) / LambdaMax,
    Acc1     = Acc + GapMin * 60.0,                 %% minutes -> seconds
    CandidateUnix = StartUnixS + round(Acc1),
    LambdaT  = lambda(CandidateUnix, State),
    {Accept, S2} = rand:uniform_s(S1),
    case Accept =< LambdaT / LambdaMax of
        true  -> {round(Acc1), State#state{rng = S2}};
        false -> sample_gap_loop(StartUnixS, Acc1, LambdaMax,
                                 State#state{rng = S2}, N + 1)
    end.

%% λ(t) in arrivals per minute.
lambda(UnixS, #state{base_rate = Base, profile = Prof}) ->
    Base * hour_factor(UnixS, Prof) * weekday_factor(UnixS).

lambda_max(StartUnixS, State) ->
    %% Sample λ across 24 quarter-hour points covering 6 hours.
    Samples = [lambda(StartUnixS + I * 900, State) || I <- lists:seq(0, 23)],
    Max = lists:max([0.0001 | Samples]),
    Max * 1.25.

hour_factor(UnixS, Profile) ->
    {{_Y, _Mo, _D}, {H, _Mi, _S}} =
        calendar:system_time_to_universal_time(UnixS, second),
    profile_hour(Profile, H).

weekday_factor(UnixS) ->
    {Date, _} = calendar:system_time_to_universal_time(UnixS, second),
    DOW = calendar:day_of_the_week(Date), %% 1=Mon..7=Sun
    weekday(DOW).

weekday(1) -> 1.0;
weekday(2) -> 1.0;
weekday(3) -> 1.0;
weekday(4) -> 1.0;
weekday(5) -> 1.1;
weekday(6) -> 0.7;
weekday(7) -> 0.5.

%% Hour factor tables — mirror the profiles in §2.
profile_hour(city_centre, H) -> element(H + 1, city_centre_hours());
profile_hour(station,     H) -> element(H + 1, station_hours());
profile_hour(residential, H) -> element(H + 1, residential_hours()).

city_centre_hours() ->
    {0.05, 0.05, 0.05, 0.05, 0.05, 0.05,
     0.30,
     1.80, 1.80,
     0.90, 0.90, 0.90,
     1.20, 1.20,
     1.10, 1.10, 1.10,
     1.50, 1.50,
     0.80, 0.80, 0.80,
     0.30, 0.30}.

station_hours() ->
    {0.10, 0.10, 0.10, 0.10, 0.20, 0.40,
     0.80,
     1.30, 1.30, 1.20, 1.20, 1.20,
     1.30, 1.30, 1.30, 1.30, 1.30,
     1.40, 1.30, 1.20, 1.00, 0.80,
     0.50, 0.30}.

residential_hours() ->
    {1.40, 1.40, 1.40, 1.40, 1.40, 1.40,
     1.30,
     0.30, 0.30,
     0.20, 0.20, 0.20,
     0.20, 0.20,
     0.30, 0.30, 0.40,
     0.80, 1.20,
     1.40, 1.40, 1.40,
     1.40, 1.40}.
