%%% @doc Tests for the fleet asset-register folding.
-module(project_assets_store_tests).
-include_lib("eunit/include/eunit.hrl").
-define(A, project_assets_store).

setup() ->
    Db = "/tmp/hecate-parksim-test/assets-" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".db",
    {ok, Pid} = ?A:start_link(#{db_path => Db}),
    Pid.
cleanup(Pid) -> gen_server:stop(Pid).

asset_lifecycle_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
        ok = ?A:apply_event(#{event_type => <<"vehicle_commissioned">>,
                              vehicle_id => <<"v1">>, vin => <<"5YJABC">>,
                              plate => <<"1-AAA-001">>, model => <<"robotaxi-mk3">>,
                              company_id => <<"leuven">>, battery_soh_pct => 100.0,
                              commissioned_at => <<"t0">>}),
        %% two charges age the pack + advance cycles
        ok = ?A:apply_event(#{event_type => <<"battery_charged">>, vehicle_id => <<"v1">>,
                              battery_soh_pct => 99.9, charge_cycle => 1, charged_at => <<"t1">>}),
        ok = ?A:apply_event(#{event_type => <<"battery_charged">>, vehicle_id => <<"v1">>,
                              battery_soh_pct => 99.8, charge_cycle => 2, charged_at => <<"t2">>}),
        %% a completed trip + a tow
        ok = ?A:apply_event(#{event_type => <<"passenger_dropped_off">>, vehicle_id => <<"v1">>,
                              dropped_off_at => <<"t3">>}),
        ok = ?A:apply_event(#{event_type => <<"vehicle_towed">>, vehicle_id => <<"v1">>,
                              towed_at => <<"t4">>}),
        A = ?A:asset(<<"v1">>),
        H = ?A:fleet_health(),
        [?_assertEqual(<<"5YJABC">>, maps:get(vin, A)),
         ?_assertEqual(<<"1-AAA-001">>, maps:get(plate, A)),
         ?_assertEqual(99.8, maps:get(battery_soh_pct, A)),
         ?_assertEqual(2, maps:get(charge_cycles, A)),
         ?_assertEqual(1, maps:get(trips, A)),
         ?_assertEqual(1, maps:get(tows, A)),
         ?_assertEqual(1, maps:get(fleet_size, H)),
         ?_assertEqual(99.8, maps:get(min_battery_soh_pct, H))]
     end}.
