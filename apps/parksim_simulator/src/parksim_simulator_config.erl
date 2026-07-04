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

%% A lot. dwell_median is the median parking duration (s). Capacity bounds
%% occupancy (the arrivals worker turns cars away when full). Dwells are
%% moderated for the demo so lots visibly cycle rather than staying full.
lot(Id, Name, Profile, Cap, DwellMedianS, Sigma, PermitShare) ->
    #parksim_lot{
        id             = Id,
        display_name   = Name,
        profile        = Profile,
        capacity       = Cap,
        dwell_median_s = DwellMedianS,
        dwell_mu       = math:log(DwellMedianS),
        dwell_sigma    = Sigma,
        permit_share   = PermitShare}.

%% Per-city landmark facilities (real parking landmarks per Belgian city),
%% with distinct capacities. The `city' shape resolves to the tenant's set.
leuven_lots() ->
    [lot(<<"lot-leuven-grote-markt">>, <<"Grote Markt">>,  city_centre, 250, 5400,  0.85, 0.05),
     lot(<<"lot-leuven-ladeuze">>,     <<"Ladeuzeplein">>, city_centre, 500, 7200,  0.80, 0.10),
     lot(<<"lot-leuven-bruul">>,       <<"Bruul">>,        city_centre, 350, 5400,  0.85, 0.08),
     lot(<<"lot-leuven-sint-jacob">>,  <<"Sint-Jacob">>,   residential, 300, 10800, 0.55, 0.45),
     lot(<<"lot-leuven-station">>,     <<"Station">>,      station,     450, 14400, 0.45, 0.15)].

brussels_lots() ->
    [lot(<<"lot-brussels-grand-place">>, <<"Grand-Place">>,  city_centre, 350, 5400,  0.85, 0.05),
     lot(<<"lot-brussels-sablon">>,      <<"Sablon">>,       city_centre, 300, 6000,  0.80, 0.08),
     lot(<<"lot-brussels-louise">>,      <<"Louise">>,       city_centre, 550, 7200,  0.80, 0.10),
     lot(<<"lot-brussels-midi">>,        <<"Brussel-Zuid">>, station,     700, 14400, 0.45, 0.15),
     lot(<<"lot-brussels-atomium">>,     <<"Atomium">>,      residential, 450, 9000,  0.60, 0.20)].

ghent_lots() ->
    [lot(<<"lot-ghent-korenmarkt">>,   <<"Korenmarkt">>,        city_centre, 300, 5400,  0.85, 0.05),
     lot(<<"lot-ghent-vrijdagmarkt">>, <<"Vrijdagmarkt">>,      city_centre, 350, 6000,  0.80, 0.08),
     lot(<<"lot-ghent-gravensteen">>,  <<"Gravensteen">>,       city_centre, 250, 5400,  0.85, 0.05),
     lot(<<"lot-ghent-sint-pieters">>, <<"Gent-Sint-Pieters">>, station,     600, 14400, 0.45, 0.15),
     lot(<<"lot-ghent-dampoort">>,     <<"Dampoort">>,          station,     400, 12000, 0.50, 0.12)].

antwerp_lots() ->
    [lot(<<"lot-antwerp-groenplaats">>, <<"Groenplaats">>,        city_centre, 450, 5400,  0.85, 0.05),
     lot(<<"lot-antwerp-meir">>,        <<"Meir">>,               city_centre, 500, 6000,  0.80, 0.08),
     lot(<<"lot-antwerp-centraal">>,    <<"Antwerpen-Centraal">>, station,     650, 14400, 0.45, 0.15),
     lot(<<"lot-antwerp-het-steen">>,   <<"Het Steen">>,          city_centre, 250, 5400,  0.85, 0.05),
     lot(<<"lot-antwerp-eilandje">>,    <<"Eilandje (MAS)">>,     residential, 400, 9000,  0.60, 0.20)].

city_lots(<<"brussels">>) -> brussels_lots();
city_lots(<<"ghent">>)    -> ghent_lots();
city_lots(<<"antwerp">>)  -> antwerp_lots();
city_lots(_Leuven)        -> leuven_lots().

%% The tenant/city this instance simulates (TENANT_ID; lowercased).
tenant() ->
    case os:getenv("TENANT_ID") of
        false -> <<"leuven">>;
        ""    -> <<"leuven">>;
        S     -> list_to_binary(string:lowercase(S))
    end.

demo_preset() ->
    #parksim_preset{
        name = <<"demo">>,
        lots = [hd(leuven_lots())],
        avg_sessions_per_day = 1200,
        peak_lambda_per_min  = 3.0,
        permit_roster_size   = 40,
        plate_pool_size      = 500}.

city_preset() ->
    #parksim_preset{
        name = <<"city">>,
        lots = city_lots(tenant()),
        avg_sessions_per_day = 9000,
        peak_lambda_per_min  = 7.0,
        permit_roster_size   = 200,
        plate_pool_size      = 2000}.

stress_preset() ->
    #parksim_preset{
        name = <<"stress">>,
        lots = leuven_lots() ++ brussels_lots(),
        avg_sessions_per_day = 36000,
        peak_lambda_per_min  = 45.0,
        permit_roster_size   = 800,
        plate_pool_size      = 6000}.
