%%% @doc Tests for the settle_energy handler — the cost + off-peak computation.
-module(maybe_settle_energy_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").

sid() -> <<"veh-1#3">>.

%% A completed session priced at Tariff cents/kWh with Energy kWh drawn.
completed(Energy, Tariff) ->
    S0 = charging_state:apply_event(charging_state:new(sid()), #{
        event_type => <<"charge_requested">>, session_id => sid(),
        vehicle_id => <<"veh-1">>, company_id => <<"op">>,
        battery_pct_before => 20, tariff_cents_per_kwh => Tariff}),
    S1 = charging_state:apply_event(S0, #{
        event_type => <<"charging_started">>, session_id => sid(),
        tariff_cents_per_kwh => Tariff}),
    charging_state:apply_event(S1, #{
        event_type => <<"charging_completed">>, session_id => sid(),
        final_soc_pct => 100, energy_kwh => Energy}).

cmd(Overrides) ->
    {ok, Cmd} = settle_energy_v1:from_map(
        maps:merge(#{<<"session_id">> => sid()}, Overrides)),
    Cmd.

settles_cost_from_state_test() ->
    %% 48 kWh at 16 c/kWh = 768 c, off-peak (<= 22).
    {ok, [Ev]} = maybe_settle_energy:handle(cmd(#{}), completed(48.0, 16)),
    ?assertEqual(<<"energy_settled">>, maps:get(event_type, Ev)),
    ?assertEqual(768, maps:get(cost_cents, Ev)),
    ?assertEqual(true, maps:get(off_peak, Ev)),
    ?assertEqual(48.0, maps:get(energy_kwh, Ev)),
    ?assertEqual(16, maps:get(tariff_cents_per_kwh, Ev)).

peak_price_is_not_off_peak_test() ->
    %% 40 kWh at 38 c/kWh = 1520 c, peak (> 22).
    {ok, [Ev]} = maybe_settle_energy:handle(cmd(#{}), completed(40.0, 38)),
    ?assertEqual(1520, maps:get(cost_cents, Ev)),
    ?assertEqual(false, maps:get(off_peak, Ev)).

rejects_when_not_completed_test() ->
    %% Still charging — cannot settle.
    S = charging_state:apply_event(charging_state:new(sid()), #{
        event_type => <<"charge_requested">>, session_id => sid()}),
    ?assertEqual({error, charge_not_completed},
                 maybe_settle_energy:handle(cmd(#{}), S)).

rejects_when_already_settled_test() ->
    S0 = completed(48.0, 16),
    S1 = charging_state:apply_event(S0, #{
        event_type => <<"energy_settled">>, session_id => sid(),
        cost_cents => 768, off_peak => true}),
    ?assertEqual({error, energy_already_settled},
                 maybe_settle_energy:handle(cmd(#{}), S1)).

command_overrides_win_over_state_test() ->
    %% Explicit energy/tariff on the command take precedence.
    {ok, [Ev]} = maybe_settle_energy:handle(
        cmd(#{<<"energy_kwh">> => 10.0, <<"tariff_cents_per_kwh">> => 30}),
        completed(48.0, 16)),
    ?assertEqual(300, maps:get(cost_cents, Ev)),
    ?assertEqual(false, maps:get(off_peak, Ev)).
