%%% @doc Smoke tests for scenario presets.
-module(parksim_simulator_config_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("parksim_simulator/include/parksim_simulator_scenario.hrl").

city_has_three_lots_test() ->
    application:set_env(hecate_parksim, shape, "city"),
    application:set_env(hecate_parksim, time_scale, 1.0),
    application:set_env(hecate_parksim, seed, 0),
    P = parksim_simulator_config:preset(),
    ?assertEqual(3, length(P#parksim_preset.lots)),
    ?assertEqual(<<"city">>, P#parksim_preset.name).

unknown_shape_falls_back_to_city_test() ->
    application:set_env(hecate_parksim, shape, "nope"),
    P = parksim_simulator_config:preset(),
    ?assertEqual(<<"city">>, P#parksim_preset.name).

demo_preset_test() ->
    application:set_env(hecate_parksim, shape, "demo"),
    P = parksim_simulator_config:preset(),
    ?assertEqual(1, length(P#parksim_preset.lots)).

stress_preset_test() ->
    application:set_env(hecate_parksim, shape, "stress"),
    P = parksim_simulator_config:preset(),
    ?assertEqual(6, length(P#parksim_preset.lots)).

%% Regression: PARKSIM_TIME_SCALE="30" (integer form) must parse, not
%% crash. list_to_float/1 threw badarg on it, killing every visit's
%% dwell sleep so no session ever reached payment/exit.
time_scale_integer_string_test() ->
    os:putenv("PARKSIM_TIME_SCALE", "30"),
    ?assertEqual(30.0, parksim_simulator_config:time_scale()),
    os:unsetenv("PARKSIM_TIME_SCALE").

time_scale_float_string_test() ->
    os:putenv("PARKSIM_TIME_SCALE", "1.5"),
    ?assertEqual(1.5, parksim_simulator_config:time_scale()),
    os:unsetenv("PARKSIM_TIME_SCALE").

time_scale_garbage_falls_back_to_one_test() ->
    os:putenv("PARKSIM_TIME_SCALE", "fast"),
    ?assertEqual(1.0, parksim_simulator_config:time_scale()),
    os:putenv("PARKSIM_TIME_SCALE", "0"),
    ?assertEqual(1.0, parksim_simulator_config:time_scale()),
    os:unsetenv("PARKSIM_TIME_SCALE").

time_scale_unset_uses_app_env_test() ->
    os:unsetenv("PARKSIM_TIME_SCALE"),
    application:set_env(hecate_parksim, time_scale, 1.0),
    ?assertEqual(1.0, parksim_simulator_config:time_scale()).
