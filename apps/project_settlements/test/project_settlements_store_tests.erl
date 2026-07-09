%%% @doc Tests for the operator-ledger folding + settlement summary.
-module(project_settlements_store_tests).
-include_lib("eunit/include/eunit.hrl").

-define(S, project_settlements_store).

setup() ->
    %% `unique_integer` only resets per BEAM run, so the same filename recurs
    %% across separate eunit invocations and the store would REOPEN a stale DB
    %% (it opens, never truncates) — leaking a prior run's rows into this one.
    %% Make the path unique across runs (nanosecond time) and delete any stale
    %% file before opening, so every fixture starts on an empty ledger.
    Db = "/tmp/hecate-parksim-test/settle-"
         ++ integer_to_list(erlang:system_time(nanosecond))
         ++ "-" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".db",
    _ = file:delete(Db),
    {ok, Pid} = ?S:start_link(#{db_path => Db, operator => <<"leuven">>}),
    Pid.

cleanup(Pid) -> catch gen_server:stop(Pid).

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

exceptions_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
        %% a cancellation fee is revenue (credit) despite no trip
        ok = ?S:apply_event(#{event_type => <<"ride_cancelled">>, ride_id => <<"r1">>,
                              cancellation_fee_cents => 250, cancelled_at => <<"t1">>}),
        %% a refund reverses fare (debit)
        ok = ?S:apply_event(#{event_type => <<"refund_issued">>, ride_id => <<"r2">>,
                              refund_cents => 180, refunded_at => <<"t2">>}),
        #{revenue_cents := Rev, cost_cents := Cost, net_cents := Net} = ?S:settlement(),
        Kinds = ?S:by_kind(),
        Fee  = [E || #{kind := <<"cancellation_fee">>} = E <- Kinds],
        Ref  = [E || #{kind := <<"refund">>} = E <- Kinds],
        [?_assertEqual(250, Rev),
         ?_assertEqual(180, Cost),
         ?_assertEqual(250 - 180, Net),
         ?_assertMatch([#{amount_cents := 250, direction := <<"credit">>}], Fee),
         ?_assertMatch([#{amount_cents := 180, direction := <<"debit">>}], Ref)]
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
