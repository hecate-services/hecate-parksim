%%% @doc eunit tests for the robotaxi fleet read model.
%%%
%%% Drives vehicle-lifecycle events (in the shape the projection forwards)
%%% through project_fleet_store against a throwaway on-disk SQLite db, then
%%% asserts the read-model rollups. Pure read-model test — no event store,
%%% no mesh, no simulator.
-module(project_fleet_store_tests).
-include_lib("eunit/include/eunit.hrl").

%% A full lifecycle for one vehicle + a stranded second vehicle.
fleet_read_model_test() ->
    Db = tmpdb(),
    {ok, Pid} = project_fleet_store:start_link(#{db_path => Db}),
    try
        V = <<"leuven-taxi-1">>,
        [ok = project_fleet_store:apply_event(E) || E <- [
            ev(<<"vehicle_commissioned">>, V, #{company_id => <<"leuven">>,
                battery_pct => 100.0, x => 50.88, y => 4.70}),
            ev(<<"vehicle_dispatched">>, V, #{}),
            ev(<<"passenger_picked_up">>, V, #{x => 50.879, y => 4.701}),
            ev(<<"passenger_dropped_off">>, V, #{x => 50.876, y => 4.700}),
            ev(<<"fare_collected">>, V, #{fare_cents => 1450}),
            ev(<<"vehicle_returning">>, V, #{facility_id => <<"depot-centrum">>}),
            ev(<<"vehicle_docked_at_facility">>, V, #{facility_id => <<"depot-centrum">>,
                bay_id => <<"b1">>, x => 50.881, y => 4.70}),
            ev(<<"battery_charged">>, V, #{battery_pct => 100.0})
        ]],

        V2 = <<"leuven-taxi-2">>,
        [ok = project_fleet_store:apply_event(E) || E <- [
            ev(<<"vehicle_commissioned">>, V2, #{company_id => <<"leuven">>,
                battery_pct => 100.0, x => 50.88, y => 4.70}),
            ev(<<"vehicle_dispatched">>, V2, #{}),
            ev(<<"battery_depleted">>, V2, #{x => 50.87, y => 4.69})
        ]],

        Ov = project_fleet_store:overview(),
        ?assertEqual(2,    maps:get(total, Ov)),
        ?assertEqual(1,    maps:get(servicing, Ov)),       %% v1 charging
        ?assertEqual(1,    maps:get(charging, Ov)),
        ?assertEqual(1,    maps:get(depleted, Ov)),        %% v2 stranded
        ?assertEqual(0,    maps:get(dispatched, Ov)),      %% v2 moved on to depleted
        ?assertEqual(1,    maps:get(trips, Ov)),
        ?assertEqual(1450, maps:get(revenue_cents, Ov)),

        Vs = project_fleet_store:vehicles(),
        ?assertEqual(2, length(Vs)),
        V1Row = hd([R || R <- Vs, maps:get(vehicle_id, R) =:= V]),
        ?assertEqual(<<"servicing">>, maps:get(phase, V1Row)),
        ?assertEqual(1450, maps:get(fares_cents, V1Row)),
        ?assertEqual(1, maps:get(trips, V1Row)),

        Fac = project_fleet_store:by_facility(),
        ?assertEqual([#{facility_id => <<"depot-centrum">>, vehicles => 1}], Fac),

        Recent = project_fleet_store:recent(5),
        ?assert(length(Recent) >= 3)
    after
        gen_server:stop(Pid),
        file:delete(Db)
    end.

%% Phase is exclusive: each transition replaces the prior phase bit.
exclusive_phase_test() ->
    Db = tmpdb(),
    {ok, Pid} = project_fleet_store:start_link(#{db_path => Db}),
    try
        V = <<"x">>,
        project_fleet_store:apply_event(
            ev(<<"vehicle_commissioned">>, V, #{company_id => <<"l">>,
               battery_pct => 100.0, x => 50.0, y => 4.0})),
        ?assertEqual(<<"commissioned">>, phase_of(V)),
        project_fleet_store:apply_event(ev(<<"vehicle_dispatched">>, V, #{})),
        ?assertEqual(<<"dispatched">>, phase_of(V)),
        project_fleet_store:apply_event(
            ev(<<"battery_charged">>, V, #{battery_pct => 100.0})),
        %% must be ONLY servicing now — not dispatched|servicing
        ?assertEqual(<<"servicing">>, phase_of(V))
    after
        gen_server:stop(Pid),
        file:delete(Db)
    end.

%%--------------------------------------------------------------------

ev(Type, Id, Extra) ->
    maps:merge(#{event_type => Type, vehicle_id => Id}, Extra).

phase_of(Id) ->
    [R] = [X || X <- project_fleet_store:vehicles(), maps:get(vehicle_id, X) =:= Id],
    maps:get(phase, R).

tmpdb() ->
    Dir = filename:basedir(user_cache, "hecate-parksim-test"),
    ok = filelib:ensure_dir(filename:join(Dir, "x")),
    filename:join(Dir, "fleet_test_" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".db").
