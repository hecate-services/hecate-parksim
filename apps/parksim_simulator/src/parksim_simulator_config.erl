%%% @doc Read scenario presets + runtime knobs from sys.config / env vars.
-module(parksim_simulator_config).

-export([shape/0, time_scale/0, seed/0, include_evacuation/0,
         preset/0, lot_variants/0, as_map/0]).

-include("parksim_simulator_scenario.hrl").

shape() ->
    case os:getenv("PARKSIM_SHAPE") of
        false -> application:get_env(hecate_parksim, shape, "city");
        S     -> S
    end.

time_scale() ->
    case os:getenv("PARKSIM_TIME_SCALE") of
        false -> application:get_env(hecate_parksim, time_scale, 1.0);
        S     -> parse_pos_float(S, 1.0)
    end.

%% @doc Parse a positive number from an env string, accepting BOTH
%% integer ("30") and float ("30.0") forms. `list_to_float/1' throws
%% badarg on an integer-form string, which previously crashed the
%% simulated clock — and with it every visit's dwell sleep, so no
%% session ever reached payment/exit. Falls back to Default on
%% anything non-numeric or non-positive.
-spec parse_pos_float(string(), float()) -> float().
parse_pos_float(S, Default) ->
    Parsed = case string:to_float(S) of
                 {F, _} when is_float(F) -> F;
                 _ ->
                     case string:to_integer(S) of
                         {I, _} when is_integer(I) -> float(I);
                         _                         -> Default
                     end
             end,
    case Parsed of
        N when is_number(N), N > 0 -> float(N);
        _                          -> Default
    end.

seed() ->
    case os:getenv("PARKSIM_SEED") of
        false -> application:get_env(hecate_parksim, seed, 0);
        S     -> list_to_integer(S)
    end.

include_evacuation() ->
    application:get_env(hecate_parksim, include_evacuation, false).

%% Returns the active preset.
-spec preset() -> #parksim_preset{}.
preset() ->
    case shape() of
        "demo"   -> demo_preset();
        "city"   -> city_preset();
        "stress" -> stress_preset();
        Other    ->
            error_logger:warning_msg("unknown shape ~p, defaulting to city~n", [Other]),
            city_preset()
    end.

lot_variants() ->
    P = preset(),
    P#parksim_preset.lots.

%% Convenience for the /api/run endpoint.
as_map() ->
    P = preset(),
    #{
        shape              => list_to_binary(shape()),
        time_scale         => time_scale(),
        seed               => seed(),
        include_evacuation => include_evacuation(),
        avg_sessions_per_day => P#parksim_preset.avg_sessions_per_day,
        peak_lambda_per_min  => P#parksim_preset.peak_lambda_per_min,
        permit_roster_size   => P#parksim_preset.permit_roster_size,
        plate_pool_size      => P#parksim_preset.plate_pool_size,
        lots                 => [lot_to_map(L) || L <- P#parksim_preset.lots]
    }.

lot_to_map(#parksim_lot{} = L) ->
    #{
        id            => L#parksim_lot.id,
        display_name  => L#parksim_lot.display_name,
        profile       => L#parksim_lot.profile,
        capacity      => L#parksim_lot.capacity,
        dwell_median_s => L#parksim_lot.dwell_median_s,
        dwell_mu      => L#parksim_lot.dwell_mu,
        dwell_sigma   => L#parksim_lot.dwell_sigma,
        permit_share  => L#parksim_lot.permit_share
    }.

%%--------------------------------------------------------------------
%% Presets (mirror PLAN_PARKSIM_TRAFFIC_MODEL.md §1, §2.3, §3, §6)

grote_markt() ->
    #parksim_lot{
        id            = <<"lot-leuven-grote-markt">>,
        display_name  = <<"Grote Markt">>,
        profile       = city_centre,
        capacity      = 320,
        dwell_median_s = 5400,
        dwell_mu      = math:log(5400),
        dwell_sigma   = 0.85,
        permit_share  = 0.05}.

station() ->
    #parksim_lot{
        id            = <<"lot-leuven-station">>,
        display_name  = <<"Station">>,
        profile       = station,
        capacity      = 560,
        dwell_median_s = 40000,
        dwell_mu      = math:log(40000),
        dwell_sigma   = 0.40,
        permit_share  = 0.15}.

residential() ->
    #parksim_lot{
        id            = <<"lot-leuven-residential">>,
        display_name  = <<"Residential">>,
        profile       = residential,
        capacity      = 180,
        dwell_median_s = 47000,
        dwell_mu      = math:log(47000),
        dwell_sigma   = 0.55,
        permit_share  = 0.70}.

demo_preset() ->
    #parksim_preset{
        name = <<"demo">>,
        lots = [grote_markt()],
        avg_sessions_per_day = 1200,
        peak_lambda_per_min  = 3.0,
        permit_roster_size   = 40,
        plate_pool_size      = 500}.

city_preset() ->
    #parksim_preset{
        name = <<"city">>,
        lots = [grote_markt(), station(), residential()],
        avg_sessions_per_day = 9000,
        peak_lambda_per_min  = 12.0,
        permit_roster_size   = 200,
        plate_pool_size      = 2000}.

stress_preset() ->
    #parksim_preset{
        name = <<"stress">>,
        lots = [grote_markt(), station(), residential(),
                grote_markt(), station(), residential()],
        avg_sessions_per_day = 36000,
        peak_lambda_per_min  = 45.0,
        permit_roster_size   = 800,
        plate_pool_size      = 6000}.
