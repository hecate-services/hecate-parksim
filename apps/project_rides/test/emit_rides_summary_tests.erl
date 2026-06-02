%%% @doc Tests the ride-summary fact contract degrades safely when the read
%%% model is unavailable (boot race): every field defaults to 0, never crashes.
-module(emit_rides_summary_tests).
-include_lib("eunit/include/eunit.hrl").

fact_shape_and_safe_defaults_test() ->
    %% No project_rides_store running -> overview/0 throws -> safe defaults.
    F = emit_rides_summary:to_fact(<<"leuven">>),
    ?assertEqual(rides_summary, maps:get(type, F)),
    ?assertEqual(<<"leuven">>, maps:get(company, F)),
    Keys = [total, waiting, active, completed, expired, fares_cents],
    [?assertEqual(0, maps:get(K, F)) || K <- Keys],
    ?assert(is_integer(maps:get(observed_at, F))).
