%%% @doc CMD-level domain spec for the robotaxi vehicle aggregate.
%%%
%%% First consumer of evoq-testkit. Layer A (pure) drives the full vehicle
%%% lifecycle as a command sequence, asserting after each command: the exact
%%% events emitted (and no others), no failure (or the expected rejection),
%%% and the resulting phase. Layer B replays the same happy path through the
%%% real dispatcher against mem-evoq, proving the events persist under a
%%% reckon-db-valid stream id.
%%%
%%% Payloads mirror exactly what the fleet brain (simulate_fleet_core)
%%% dispatches in production, so they exercise the real command path.
-module(vehicle_aggregate_spec_tests).
-include_lib("eunit/include/eunit.hrl").

-define(AGG, vehicle_aggregate).

%% A valid reckon-db stream id (Layer A ignores the format; Layer B needs it).
sid() -> vehicle_aggregate:stream_id(<<"leuven-taxi-1">>).
vid() -> <<"leuven-taxi-1">>.

%% Production-shaped payloads (from simulate_fleet_core effects).
commission_payload() ->
    #{vehicle_id => vid(), company_id => <<"leuven">>,
      battery_pct => 100.0, lat => 50.8798, lng => 4.7005}.
dispatch_payload() ->
    #{vehicle_id => vid(), trip_id => <<"trip-1">>,
      pickup_lat => 50.8788, pickup_lng => 4.7011,
      dropoff_lat => 50.8814, dropoff_lng => 4.7155}.
pickup_payload()  -> #{vehicle_id => vid(), lat => 50.8788, lng => 4.7011}.
dropoff_payload() -> #{vehicle_id => vid(), fare_cents => 850,
                       lat => 50.8814, lng => 4.7155}.
return_payload()  -> #{vehicle_id => vid(), facility_id => <<"depot-centrum">>}.
dock_payload()    -> #{vehicle_id => vid(), facility_id => <<"depot-centrum">>,
                       bay_id => <<"depot-centrum-bay-1">>,
                       lat => 50.8810, lng => 4.7005}.
service_payload() -> #{vehicle_id => vid(), kind => <<"charge">>,
                       battery_pct => 100.0}.
release_payload() -> #{vehicle_id => vid()}.
deplete_payload() -> #{vehicle_id => vid(), lat => 50.88, lng => 4.70}.

%%====================================================================
%% Layer A — the full happy-path lifecycle as one command sequence
%%====================================================================

full_lifecycle_test() ->
    E = fun(T) -> evoq_aggregate_spec:expect([T]) end,
    ok = evoq_aggregate_spec:run(?AGG, sid(), [
        {commission_vehicle, commission_payload(), E(<<"vehicle_commissioned">>),
              fun vehicle_state:is_commissioned/1},
        {dispatch_vehicle, dispatch_payload(), E(<<"vehicle_dispatched">>),
              fun vehicle_state:is_dispatched/1},
        {pick_up_passenger, pickup_payload(), E(<<"passenger_picked_up">>),
              fun vehicle_state:is_on_trip/1},
        %% drop_off is the canonical multi-event desk: dropped_off + fare.
        {drop_off_passenger, dropoff_payload(),
              evoq_aggregate_spec:expect([<<"passenger_dropped_off">>,
                                          <<"fare_collected">>]),
              fun vehicle_state:is_cruising/1},
        {return_vehicle, return_payload(), E(<<"vehicle_returning">>),
              fun vehicle_state:is_returning/1},
        {dock_at_facility, dock_payload(), E(<<"vehicle_docked_at_facility">>),
              fun vehicle_state:is_docked/1},
        {service_vehicle, service_payload(), E(<<"vehicle_serviced">>),
              fun vehicle_state:is_servicing/1},
        {release_vehicle, release_payload(), E(<<"vehicle_released">>),
              fun vehicle_state:is_cruising/1}
    ]).

%%====================================================================
%% Layer A — deplete path (the branch the is_in_motion fix unblocked)
%%====================================================================

deplete_while_dispatched_test() ->
    ok = evoq_aggregate_spec:run(?AGG, sid(), [
        {commission_vehicle, commission_payload(),
              evoq_aggregate_spec:expect([<<"vehicle_commissioned">>]),
              evoq_aggregate_spec:unchanged()},
        {dispatch_vehicle, dispatch_payload(),
              evoq_aggregate_spec:expect([<<"vehicle_dispatched">>]),
              fun vehicle_state:is_dispatched/1},
        {deplete_battery, deplete_payload(),
              evoq_aggregate_spec:expect([<<"battery_depleted">>]),
              fun vehicle_state:is_depleted/1}
    ]).

%%====================================================================
%% Layer A — precondition rejections (every guard a command enforces)
%%====================================================================

commission_twice_rejected_test() ->
    ok = evoq_aggregate_spec:run(?AGG, sid(), [
        {commission_vehicle, commission_payload(),
              evoq_aggregate_spec:expect([<<"vehicle_commissioned">>]),
              evoq_aggregate_spec:unchanged()},
        {commission_vehicle, commission_payload(),
              evoq_aggregate_spec:expect_error(vehicle_already_commissioned),
              evoq_aggregate_spec:unchanged()}
    ]).

pickup_when_not_dispatched_rejected_test() ->
    ok = evoq_aggregate_spec:run(?AGG, sid(), [
        {pick_up_passenger, pickup_payload(),
              evoq_aggregate_spec:expect_error(vehicle_not_dispatched),
              evoq_aggregate_spec:unchanged()}
    ]).

dropoff_when_not_on_trip_rejected_test() ->
    %% commissioned -> dispatched, then drop_off (still only dispatched).
    ok = evoq_aggregate_spec:run(?AGG, sid(), [
        {commission_vehicle, commission_payload(),
              evoq_aggregate_spec:expect([<<"vehicle_commissioned">>]),
              evoq_aggregate_spec:unchanged()},
        {dispatch_vehicle, dispatch_payload(),
              evoq_aggregate_spec:expect([<<"vehicle_dispatched">>]),
              evoq_aggregate_spec:unchanged()},
        {drop_off_passenger, dropoff_payload(),
              evoq_aggregate_spec:expect_error(vehicle_not_on_trip),
              evoq_aggregate_spec:unchanged()}
    ]).

dispatch_when_pristine_rejected_test() ->
    ok = evoq_aggregate_spec:run(?AGG, sid(), [
        {dispatch_vehicle, dispatch_payload(),
              evoq_aggregate_spec:expect_error(vehicle_not_available),
              evoq_aggregate_spec:unchanged()}
    ]).

%%====================================================================
%% Stream-id guard: the parksim bug, as a permanent regression test
%%====================================================================

stream_id_is_reckon_valid_test() ->
    %% vehicle_aggregate:stream_id/1 must produce a reckon-db-valid id —
    %% the human vehicle id alone (leuven-taxi-1) does NOT, which is exactly
    %% the bug that silently dropped every fleet event.
    ok = evoq_cmd_case:assert_valid_stream_id(vehicle_aggregate:stream_id(vid())),
    ?assertError({invalid_stream_id, _, _, _},
                 evoq_cmd_case:assert_valid_stream_id(vid())).

%%====================================================================
%% Layer B — the happy path actually PERSISTS through real dispatch
%%====================================================================

lifecycle_persists_test() ->
    evoq_cmd_case:with_mem_store(fun(StoreId) ->
        Sid = sid(),
        Scenario = [{commission_vehicle, commission_payload()},
                    {dispatch_vehicle,   dispatch_payload()},
                    {pick_up_passenger,  pickup_payload()},
                    {drop_off_passenger, dropoff_payload()}],
        ok = evoq_cmd_case:dispatch_all(?AGG, Sid, Scenario, StoreId),
        evoq_cmd_case:assert_stream(StoreId, Sid,
            [<<"vehicle_commissioned">>, <<"vehicle_dispatched">>,
             <<"passenger_picked_up">>,
             <<"passenger_dropped_off">>, <<"fare_collected">>])
    end).
