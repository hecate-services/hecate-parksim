%%% @doc eunit tests for the rides read model.
%%%
%%% Drives ride-lifecycle events (in the shape the projection forwards) through
%%% project_rides_store against a throwaway on-disk SQLite db, then asserts the
%%% read-model rollups. Pure read-model test — no event store, no simulator.
-module(project_rides_store_tests).
-include_lib("eunit/include/eunit.hrl").

rides_read_model_test() ->
    Db = tmpdb(),
    {ok, Pid} = project_rides_store:start_link(#{db_path => Db}),
    try
        %% r1: full lifecycle (completed, fare 610).
        R1 = <<"req-1">>,
        [ok = project_rides_store:apply_event(E) || E <- [
            ev(<<"ride_requested">>, R1, #{company_id => <<"leuven">>,
                pickup_x => 3, pickup_y => 3, dropoff_x => 5, dropoff_y => 1,
                party_size => 2, fare_estimate_cents => 540}),
            ev(<<"ride_assigned">>, R1, #{vehicle_id => <<"leuven-taxi-1">>}),
            ev(<<"ride_started">>, R1, #{}),
            ev(<<"ride_completed">>, R1, #{fare_cents => 610})
        ]],

        %% r2: requested then expired (abandoned).
        R2 = <<"req-2">>,
        [ok = project_rides_store:apply_event(E) || E <- [
            ev(<<"ride_requested">>, R2, #{company_id => <<"leuven">>,
                pickup_x => 1, pickup_y => 1, dropoff_x => 2, dropoff_y => 2,
                party_size => 1, fare_estimate_cents => 300}),
            ev(<<"ride_expired">>, R2, #{})
        ]],

        %% r3: still waiting.
        R3 = <<"req-3">>,
        ok = project_rides_store:apply_event(
            ev(<<"ride_requested">>, R3, #{company_id => <<"ghent">>,
                pickup_x => 4, pickup_y => 4, dropoff_x => 0, dropoff_y => 0,
                party_size => 3, fare_estimate_cents => 720})),

        Ov = project_rides_store:overview(),
        ?assertEqual(3,    maps:get(total, Ov)),
        ?assertEqual(1,    maps:get(completed, Ov)),
        ?assertEqual(1,    maps:get(expired, Ov)),
        ?assertEqual(1,    maps:get(waiting, Ov)),         %% r3 still requested
        ?assertEqual(0,    maps:get(in_progress, Ov)),
        ?assertEqual(610,  maps:get(fares_cents, Ov)),
        ?assertEqual(0.5,  maps:get(completion_rate, Ov)), %% 1 completed / (1+1)

        By = project_rides_store:by_company(),
        Leuven = hd([M || #{company_id := <<"leuven">>} = M <- By]),
        ?assertEqual(1, maps:get(completed, Leuven)),
        ?assertEqual(1, maps:get(expired, Leuven)),
        ?assertEqual(610, maps:get(fares_cents, Leuven)),

        Rides = project_rides_store:rides(),
        ?assertEqual(3, length(Rides)),
        R1Row = hd([M || #{ride_id := <<"req-1">>} = M <- Rides]),
        ?assertEqual(<<"completed">>, maps:get(status, R1Row)),
        ?assertEqual(2, maps:get(party_size, R1Row))
    after
        gen_server:stop(Pid),
        file:delete(Db)
    end.

%%--------------------------------------------------------------------

ev(Type, RideId, Fields) ->
    Fields#{event_type => Type, ride_id => RideId}.

tmpdb() ->
    N = erlang:unique_integer([positive]),
    filename:join("/tmp", "rides_test_" ++ integer_to_list(N) ++ ".db").
