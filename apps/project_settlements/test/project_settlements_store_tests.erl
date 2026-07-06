%%% @doc Tests for the operator-ledger folding + settlement summary.
-module(project_settlements_store_tests).
-include_lib("eunit/include/eunit.hrl").

-define(S, project_settlements_store).

setup() ->
    Db = "/tmp/hecate-parksim-test/settle-" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".db",
    {ok, Pid} = ?S:start_link(#{db_path => Db, operator => <<"leuven">>}),
    Pid.

cleanup(Pid) -> gen_server:stop(Pid).

settlement_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
        %% revenue: ride fare 250 + tip 38, parking fee 400
        ok = ?S:apply_event(#{event_type => <<"ride_completed">>, ride_id => <<"r1">>,
                              fare_cents => 250, tip_cents => 38, completed_at => <<"t1">>}),
        ok = ?S:apply_event(#{event_type => <<"payment_captured">>, session_id => <<"s1">>,
                              fee_cents => 400, paid_at => <<"t2">>}),
        %% cost: energy 120, tow 5000
        ok = ?S:apply_event(#{event_type => <<"battery_charged">>, vehicle_id => <<"v1">>,
                              charging_cents => 120, charged_at => <<"t3">>}),
        ok = ?S:apply_event(#{event_type => <<"vehicle_towed">>, vehicle_id => <<"v2">>,
                              tow_cents => 5000, towed_at => <<"t4">>}),
        %% a zero-amount event adds no entry
        ok = ?S:apply_event(#{event_type => <<"ride_completed">>, ride_id => <<"r2">>,
                              fare_cents => 0, tip_cents => 0, completed_at => <<"t5">>}),
        #{revenue_cents := Rev, cost_cents := Cost, net_cents := Net, entries := N} =
            ?S:settlement(),
        [?_assertEqual(250 + 38 + 400, Rev),
         ?_assertEqual(120 + 5000, Cost),
         ?_assertEqual(Rev - Cost, Net),
         %% ride_fare + ride_tip + parking_fee + energy_cost + tow_cost = 5 entries
         ?_assertEqual(5, N)]
     end}.

by_kind_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
        ok = ?S:apply_event(#{event_type => <<"battery_charged">>, vehicle_id => <<"v1">>,
                              charging_cents => 100, charged_at => <<"t">>}),
        ok = ?S:apply_event(#{event_type => <<"battery_charged">>, vehicle_id => <<"v2">>,
                              charging_cents => 50, charged_at => <<"t">>}),
        Kinds = ?S:by_kind(),
        Energy = [E || #{kind := <<"energy_cost">>} = E <- Kinds],
        [?_assertMatch([#{amount_cents := 150, count := 2, direction := <<"debit">>}], Energy)]
     end}.
