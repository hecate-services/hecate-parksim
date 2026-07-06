%%% @doc Spec tests for the ride aggregate: the happy-path lifecycle
%%% (request -> assign -> start -> complete), the expire branch, and the
%%% precondition rejections at each step.
-module(ride_aggregate_spec_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

%% Fold a handler's emitted events into state.
apply_all(State, Events) ->
    lists:foldl(fun(Ev, S) -> ride_state:apply_event(S, Ev) end, State, Events).

req() ->
    {ok, C} = request_ride_v1:new(#{ride_id => <<"r1">>, company_id => <<"leuven">>,
                                    pickup_x => 3, pickup_y => 3,
                                    dropoff_x => 5, dropoff_y => 1,
                                    party_size => 2, fare_estimate_cents => 540}),
    C.

requested_state() ->
    {ok, Evs} = maybe_request_ride:handle(req(), ride_state:new(<<"r1">>)),
    apply_all(ride_state:new(<<"r1">>), Evs).

assigned_state() ->
    {ok, C} = assign_ride_v1:new(#{ride_id => <<"r1">>, vehicle_id => <<"leuven-taxi-1">>}),
    {ok, Evs} = maybe_assign_ride:handle(C, requested_state()),
    apply_all(requested_state(), Evs).

started_state() ->
    {ok, C} = start_ride_v1:new(#{ride_id => <<"r1">>}),
    {ok, Evs} = maybe_start_ride:handle(C, assigned_state()),
    apply_all(assigned_state(), Evs).

request_births_a_requested_ride_test() ->
    S = requested_state(),
    ?assert(ride_state:is_requested(S)),
    ?assertEqual(<<"leuven">>, ride_state:company_id(S)),
    ?assertEqual(2, ride_state:party_size(S)),
    ?assertEqual(540, ride_state:fare_estimate_cents(S)).

request_on_existing_ride_is_rejected_test() ->
    ?assertEqual({error, ride_already_requested},
                 maybe_request_ride:handle(req(), requested_state())).

assign_moves_requested_to_assigned_test() ->
    S = assigned_state(),
    ?assert(ride_state:is_assigned(S)),
    ?assertEqual(<<"leuven-taxi-1">>, ride_state:vehicle_id(S)).

assign_on_pristine_is_rejected_test() ->
    {ok, C} = assign_ride_v1:new(#{ride_id => <<"r1">>, vehicle_id => <<"v">>}),
    ?assertEqual({error, ride_not_requested},
                 maybe_assign_ride:handle(C, ride_state:new(<<"r1">>))).

start_moves_assigned_to_started_test() ->
    ?assert(ride_state:is_started(started_state())).

start_on_requested_is_rejected_test() ->
    {ok, C} = start_ride_v1:new(#{ride_id => <<"r1">>}),
    ?assertEqual({error, ride_not_assigned},
                 maybe_start_ride:handle(C, requested_state())).

complete_moves_started_to_completed_test() ->
    {ok, C} = complete_ride_v1:new(#{ride_id => <<"r1">>, fare_cents => 610}),
    {ok, Evs} = maybe_complete_ride:handle(C, started_state()),
    S = apply_all(started_state(), Evs),
    ?assert(ride_state:is_completed(S)),
    ?assertEqual(610, ride_state:fare_cents(S)).

complete_on_assigned_is_rejected_test() ->
    {ok, C} = complete_ride_v1:new(#{ride_id => <<"r1">>, fare_cents => 1}),
    ?assertEqual({error, ride_not_started},
                 maybe_complete_ride:handle(C, assigned_state())).

expire_moves_requested_to_expired_test() ->
    {ok, C} = expire_ride_v1:new(#{ride_id => <<"r1">>}),
    {ok, Evs} = maybe_expire_ride:handle(C, requested_state()),
    S = apply_all(requested_state(), Evs),
    ?assert(ride_state:is_expired(S)).

expire_on_assigned_is_rejected_test() ->
    {ok, C} = expire_ride_v1:new(#{ride_id => <<"r1">>}),
    ?assertEqual({error, ride_not_requested},
                 maybe_expire_ride:handle(C, assigned_state())).

completed_state() ->
    {ok, C} = complete_ride_v1:new(#{ride_id => <<"r1">>, fare_cents => 610}),
    {ok, Evs} = maybe_complete_ride:handle(C, started_state()),
    apply_all(started_state(), Evs).

cancel_moves_assigned_to_cancelled_test() ->
    {ok, C} = cancel_ride_v1:new(#{ride_id => <<"r1">>, reason => <<"rider_no_show">>,
                                   cancellation_fee_cents => 250}),
    {ok, Evs} = maybe_cancel_ride:handle(C, assigned_state()),
    S = apply_all(assigned_state(), Evs),
    ?assert(ride_state:is_cancelled(S)),
    %% the cancelled event carries the assigned cab's identity from state
    ?assertMatch([#{vehicle_id := <<"leuven-taxi-1">>}], Evs).

cancel_on_completed_is_rejected_test() ->
    {ok, C} = cancel_ride_v1:new(#{ride_id => <<"r1">>, reason => <<"x">>,
                                   cancellation_fee_cents => 1}),
    ?assertEqual({error, ride_not_cancellable},
                 maybe_cancel_ride:handle(C, completed_state())).

refund_reduces_fare_and_keeps_completed_test() ->
    {ok, C} = issue_refund_v1:new(#{ride_id => <<"r1">>, refund_cents => 200,
                                    reason => <<"fare_dispute">>}),
    {ok, Evs} = maybe_issue_refund:handle(C, completed_state()),
    S = apply_all(completed_state(), Evs),
    ?assert(ride_state:is_completed(S)),
    ?assertEqual(610 - 200, ride_state:fare_cents(S)).

refund_on_started_is_rejected_test() ->
    {ok, C} = issue_refund_v1:new(#{ride_id => <<"r1">>, refund_cents => 1,
                                    reason => <<"x">>}),
    ?assertEqual({error, ride_not_completed},
                 maybe_issue_refund:handle(C, started_state())).

stream_id_is_compliant_test() ->
    Sid = ride_aggregate:stream_id(<<"r1">>),
    ?assertMatch(<<"ride-", _/binary>>, Sid),
    ?assertEqual(37, byte_size(Sid)).   %% "ride-" (5) + 32 hex
