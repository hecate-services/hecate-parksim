%%% @doc Tests for the charge-session SoC milestone builder (the dense progress
%%% stream the sim expands each charge into).
-module(charge_milestones_tests).

-include_lib("eunit/include/eunit.hrl").

socs(Steps)  -> [Soc || {Soc, _D, _T} <- Steps].
totals(Steps) -> [T || {_S, _D, T} <- Steps].

from_low_hits_all_marks_and_full_test() ->
    %% From 20% with 48 kWh total: marks 40/60/80 above 20, plus 100.
    Steps = simulate_fleet:charge_milestones(20, 48.0),
    ?assertEqual([40, 60, 80, 100], socs(Steps)),
    %% Cumulative energy ends at the full amount and is monotonic.
    ?assertEqual(48.0, lists:last(totals(Steps))),
    ?assertEqual(lists:sort(totals(Steps)), totals(Steps)).

deltas_sum_to_total_test() ->
    Steps = simulate_fleet:charge_milestones(30, 42.0),
    SumDelta = lists:sum([D || {_S, D, _T} <- Steps]),
    ?assert(abs(SumDelta - 42.0) < 0.11).   %% within rounding

high_start_only_reaches_full_test() ->
    %% From 85% only the 100 mark remains.
    Steps = simulate_fleet:charge_milestones(85, 9.0),
    ?assertEqual([100], socs(Steps)),
    ?assertEqual(9.0, lists:last(totals(Steps))).

already_full_has_no_steps_test() ->
    ?assertEqual([], simulate_fleet:charge_milestones(100, 0.0)).
