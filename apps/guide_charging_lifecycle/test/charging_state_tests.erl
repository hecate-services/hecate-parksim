%%% @doc Tests for the charging-session state machine.
-module(charging_state_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").
-include_lib("guide_charging_lifecycle/include/charging_status.hrl").

sid() -> <<"veh-1#3">>.
empty() -> charging_state:new(sid()).

requested() ->
    charging_state:apply_event(empty(), #{
        event_type => <<"charge_requested">>, session_id => sid(),
        vehicle_id => <<"veh-1">>, company_id => <<"op">>,
        battery_pct_before => 20, target_pct => 100,
        tariff_cents_per_kwh => 16, requested_at => <<"t0">>}).

charging() ->
    charging_state:apply_event(requested(), #{
        event_type => <<"charging_started">>, session_id => sid(),
        charger_id => <<"bay-1">>, battery_pct_before => 20,
        tariff_cents_per_kwh => 16, started_at => <<"t1">>}).

progressed() ->
    charging_state:apply_event(charging(), #{
        event_type => <<"charging_progressed">>, session_id => sid(),
        soc_pct => 60, energy_kwh_delta => 24.0, energy_kwh_total => 24.0,
        progressed_at => <<"t2">>}).

completed() ->
    charging_state:apply_event(progressed(), #{
        event_type => <<"charging_completed">>, session_id => sid(),
        final_soc_pct => 100, energy_kwh => 48.0, completed_at => <<"t3">>}).

settled() ->
    charging_state:apply_event(completed(), #{
        event_type => <<"energy_settled">>, session_id => sid(),
        cost_cents => 768, off_peak => true, settled_at => <<"t4">>}).

new_is_pristine_test() ->
    ?assert(charging_state:is_pristine(empty())),
    ?assertNot(charging_state:is_requested(empty())).

requested_sets_before_and_target_test() ->
    S = requested(),
    ?assert(charging_state:is_requested(S)),
    ?assertNot(charging_state:is_charging(S)),
    ?assertEqual(20, charging_state:battery_pct(S)),      %% seeded from before
    ?assertEqual(100, charging_state:target_pct(S)),
    ?assertEqual(16, charging_state:tariff_cents_per_kwh(S)).

started_moves_to_charging_phase_test() ->
    S = charging(),
    ?assert(charging_state:is_charging(S)),
    ?assertNot(charging_state:is_requested(S)).   %% phase is exclusive

progress_accumulates_energy_and_soc_test() ->
    S = progressed(),
    ?assert(charging_state:is_charging(S)),        %% still charging
    ?assertEqual(60, charging_state:battery_pct(S)),
    ?assertEqual(24.0, charging_state:energy_kwh(S)).

completed_is_terminal_phase_test() ->
    S = completed(),
    ?assert(charging_state:is_completed(S)),
    ?assertNot(charging_state:is_charging(S)),
    ?assertEqual(48.0, charging_state:energy_kwh(S)),
    ?assertEqual(100, charging_state:battery_pct(S)).

settled_is_additive_keeps_completed_test() ->
    S = settled(),
    ?assert(charging_state:is_settled(S)),
    ?assert(charging_state:is_completed(S)),        %% additive, not a phase change
    ?assertEqual(?CHARGE_COMPLETED bor ?ENERGY_SETTLED,
                 charging_state:status_flags(S)).

unknown_event_is_ignored_test() ->
    S = charging(),
    ?assertEqual(S, charging_state:apply_event(S, #{event_type => <<"nope">>})).
