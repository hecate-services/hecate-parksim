%%% @doc Ride-demand generator for the robotaxi fleet.
%%%
%%% Each tick, draws the number of NEW ride requests from a Poisson with a
%%% day/night intensity (the same bimodal commuter curve the parking
%%% `simulate_arrivals' uses), then samples a weighted pickup and dropoff
%%% hotspot for each. Pure given an rng + sim time: returns the requests and
%%% the advanced rng.
%%%
%%% (A per-tick Poisson count is the homogeneous-interval equivalent of the
%%% Lewis-Shedler thinning used per-lot in the parking sim — same NHPP, just
%%% counted over the fixed tick window instead of sampling inter-arrival gaps.)
-module(simulate_demand).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([requests/4]).

%% Daily rhythm peaks (hour of day) — matches simulate_arrivals.
-define(PEAK_MORNING, 8.5).
-define(PEAK_EVENING, 17.5).

%% @doc Requests arising in a tick of `TickSimSecs' simulated seconds at
%% `SimUnix', given the operator's `PeakPerMin' peak rate. Returns the new
%% requests (with ids derived from SimUnix + index) and the advanced rng.
-spec requests(integer(), number(), number(), rand:state()) ->
    {[#ride_request{}], rand:state()}.
requests(SimUnix, TickSimSecs, PeakPerMin, Rng0) ->
    Lambda = lambda_at(PeakPerMin, SimUnix),           %% requests/min now
    Mean   = Lambda * (TickSimSecs / 60.0),            %% expected this tick
    {N, Rng1} = poisson(Mean, Rng0),
    lists:foldl(
        fun(I, {Acc, R}) ->
            {Pickup, R1}  = sample_hotspot(R),
            {Dropoff, R2} = sample_hotspot(R1),
            Req = #ride_request{
                id      = req_id(SimUnix, I),
                pickup  = Pickup,
                dropoff = Dropoff,
                created = SimUnix},
            {[Req | Acc], R2}
        end, {[], Rng1}, lists:seq(1, N)).

%%--------------------------------------------------------------------
%% Intensity (bimodal commuter curve)

lambda_at(PeakPerMin, SimUnix) ->
    Hour = hour_of_day(SimUnix),
    Morning = math:exp(-0.5 * math:pow((Hour - ?PEAK_MORNING) / 1.5, 2)),
    Evening = math:exp(-0.5 * math:pow((Hour - ?PEAK_EVENING) / 1.5, 2)),
    PeakPerMin * (0.15 + 0.85 * (Morning + Evening)).

hour_of_day(SimUnix) ->
    (SimUnix rem 86400) / 3600.0.

%%--------------------------------------------------------------------
%% Poisson sampling (Knuth) — fine for the small means we see per tick.

poisson(Mean, Rng) when Mean =< 0.0 -> {0, Rng};
poisson(Mean, Rng) ->
    L = math:exp(-Mean),
    poisson_loop(L, 0, 1.0, Rng).

poisson_loop(L, K, P0, Rng0) ->
    {U, Rng1} = rand:uniform_s(Rng0),
    P = P0 * U,
    case P =< L of
        true  -> {K, Rng1};
        false -> poisson_loop(L, K + 1, P, Rng1)
    end.

%%--------------------------------------------------------------------
%% Weighted hotspot sampling

sample_hotspot(Rng0) ->
    Hs = fleet_config:hotspots(),
    Total = lists:sum([W || {_, _, _, W} <- Hs]),
    {U, Rng1} = rand:uniform_s(Rng0),
    Target = U * Total,
    {pick(Hs, Target), Rng1}.

pick([{_Name, X, Y, W} | Rest], Target) ->
    case Target =< W of
        true  -> {X, Y};
        false -> pick(Rest, Target - W)
    end;
pick([], _Target) ->
    fleet_config:city_centre().

req_id(SimUnix, I) ->
    iolist_to_binary(["req-", integer_to_list(SimUnix), "-", integer_to_list(I)]).
