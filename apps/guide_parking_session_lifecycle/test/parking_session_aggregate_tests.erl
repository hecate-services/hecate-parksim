%%% @doc Tests for parking_session_aggregate — execute/2 routing across
%%% all three commands and the unknown/missing catch-alls.
-module(parking_session_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

empty()     -> parking_session_state:new(<<"sess-1">>).
initiated() -> parking_session_state:apply_event(empty(), initiated_ev()).
paid()      -> parking_session_state:apply_event(initiated(), paid_ev()).
archived()  -> parking_session_state:apply_event(paid(), archived_ev()).

initiated_ev() ->
    #{event_type => <<"parking_session_initiated">>,
      session_id => <<"sess-1">>,
      lot_id     => <<"lot-1">>,
      entered_at => <<"prior">>}.

paid_ev() ->
    #{event_type => <<"payment_captured">>,
      session_id => <<"sess-1">>,
      fee_cents => 500,
      paid_at    => <<"prior">>}.

archived_ev() ->
    #{event_type  => <<"parking_session_archived">>,
      session_id  => <<"sess-1">>,
      archived_at => <<"prior">>}.

initiate_payload() ->
    #{command_type => <<"initiate_parking_session">>,
      session_id   => <<"sess-1">>,
      lot_id       => <<"lot-1">>,
      plate        => <<"1-ABC-123">>,
      card_id      => <<"c">>,
      entered_at   => <<"2026-05-26T08:00:00Z">>}.

capture_payload() ->
    #{command_type => <<"capture_payment">>,
      session_id   => <<"sess-1">>,
      fee_cents => 500,
      paid_at      => <<"2026-05-26T09:55:00Z">>}.

archive_payload() ->
    #{command_type => <<"archive_parking_session">>,
      session_id   => <<"sess-1">>,
      archived_at  => <<"2026-05-26T10:00:00Z">>}.

%%--------------------------------------------------------------------
%% init/1 + state_module/0

init_returns_initial_state_test() ->
    {ok, S} = parking_session_aggregate:init(<<"x">>),
    ?assertEqual(<<"x">>, parking_session_state:session_id(S)).

state_module_test() ->
    ?assertEqual(parking_session_state, parking_session_aggregate:state_module()).

%%--------------------------------------------------------------------
%% execute/2 — initiate_parking_session

execute_initiate_on_empty_succeeds_test() ->
    {ok, [Map]} = parking_session_aggregate:execute(empty(), initiate_payload()),
    ?assertEqual(<<"parking_session_initiated">>, maps:get(event_type, Map)),
    ?assertEqual(<<"sess-1">>, maps:get(session_id, Map)),
    ?assertEqual(<<"lot-1">>,  maps:get(lot_id, Map)).

execute_initiate_already_initiated_test() ->
    ?assertEqual({error, session_already_initiated},
                 parking_session_aggregate:execute(initiated(), initiate_payload())).

execute_initiate_missing_lot_id_test() ->
    P = maps:remove(lot_id, initiate_payload()),
    ?assertEqual({error, missing_lot_id},
                 parking_session_aggregate:execute(empty(), P)).

%%--------------------------------------------------------------------
%% execute/2 — capture_payment

execute_capture_on_initiated_succeeds_test() ->
    {ok, [Map]} = parking_session_aggregate:execute(initiated(), capture_payload()),
    ?assertEqual(<<"payment_captured">>, maps:get(event_type, Map)),
    ?assertEqual(500, maps:get(fee_cents, Map)).

execute_capture_on_empty_rejects_test() ->
    ?assertEqual({error, session_not_initiated},
                 parking_session_aggregate:execute(empty(), capture_payload())).

execute_capture_already_paid_rejects_test() ->
    ?assertEqual({error, session_already_paid},
                 parking_session_aggregate:execute(paid(), capture_payload())).

execute_capture_invalid_amount_test() ->
    P = (capture_payload())#{fee_cents := -1},
    ?assertEqual({error, invalid_fee_cents},
                 parking_session_aggregate:execute(initiated(), P)).

%%--------------------------------------------------------------------
%% execute/2 — archive_parking_session

execute_archive_on_paid_succeeds_test() ->
    {ok, [Map]} = parking_session_aggregate:execute(paid(), archive_payload()),
    ?assertEqual(<<"parking_session_archived">>, maps:get(event_type, Map)),
    %% fee_cents echoed from state's fee_cents (recorded at payment).
    ?assertEqual(500, maps:get(fee_cents, Map)).

execute_archive_on_empty_rejects_test() ->
    ?assertEqual({error, session_not_initiated},
                 parking_session_aggregate:execute(empty(), archive_payload())).

execute_archive_unsettled_rejects_test() ->
    ?assertEqual({error, session_not_settled},
                 parking_session_aggregate:execute(initiated(), archive_payload())).

execute_archive_already_archived_rejects_test() ->
    ?assertEqual({error, session_already_archived},
                 parking_session_aggregate:execute(archived(), archive_payload())).

%%--------------------------------------------------------------------
%% Unknown / malformed payloads

execute_unknown_command_test() ->
    ?assertEqual({error, {unhandled_command, <<"poof">>}},
                 parking_session_aggregate:execute(
                   empty(), #{command_type => <<"poof">>})).

execute_missing_command_type_test() ->
    ?assertEqual({error, missing_command_type},
                 parking_session_aggregate:execute(empty(), #{})).

%%--------------------------------------------------------------------
%% apply/2 — state-first arg order

apply_callback_arg_order_test() ->
    S0 = empty(),
    S1 = parking_session_aggregate:apply(S0, initiated_ev()),
    ?assert(parking_session_state:is_initiated(S1)),
    S2 = parking_session_aggregate:apply(S1, paid_ev()),
    ?assert(parking_session_state:is_paid(S2)).
