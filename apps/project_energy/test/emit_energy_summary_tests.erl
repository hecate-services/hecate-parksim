%%% @doc Tests for the energy-summary integration-fact contract.
-module(emit_energy_summary_tests).

-include_lib("eunit/include/eunit.hrl").

%% With no store/PM running the fact must still be well-formed (safe defaults),
%% so a boot-time tick never crashes the emitter.
fact_is_well_formed_without_backends_test() ->
    F = emit_energy_summary:to_fact(<<"leuven">>),
    ?assertEqual(energy_summary, maps:get(type, F)),
    ?assertEqual(<<"leuven">>, maps:get(company, F)),
    ?assertEqual(0, maps:get(sessions, F)),
    ?assertEqual(0, maps:get(cost_cents, F)),
    ?assertEqual(null, maps:get(grid_cents, F)),   %% no price signal yet
    ?assert(is_integer(maps:get(observed_at, F))).

fact_has_the_public_contract_keys_test() ->
    F = emit_energy_summary:to_fact(<<"ghent">>),
    Keys = [type, company, sessions, settled, energy_kwh, cost_cents,
            off_peak_sessions, off_peak_pct, avg_tariff_cents,
            grid_cents, grid_off_peak, observed_at],
    lists:foreach(fun(K) -> ?assert(maps:is_key(K, F)) end, Keys).
