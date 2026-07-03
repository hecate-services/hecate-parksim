%%% @doc Tests for the capture_payment handler.
-module(maybe_capture_payment_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

mk_cmd(Overrides) ->
    Base = #{<<"session_id">>   => <<"sess-1">>,
             <<"fee_cents">> => 500,
             <<"paid_at">>      => <<"2026-05-26T09:55:00Z">>},
    {ok, Cmd} = capture_payment_v1:from_map(maps:merge(Base, Overrides)),
    Cmd.

empty()     -> parking_session_state:new(<<"sess-1">>).
initiated() ->
    parking_session_state:apply_event(empty(), #{
        event_type => <<"parking_session_initiated">>,
        session_id => <<"sess-1">>, lot_id => <<"l">>, entered_at => <<"t">>}).
paid()      ->
    parking_session_state:apply_event(initiated(), #{
        event_type => <<"payment_captured">>,
        session_id => <<"sess-1">>, fee_cents => 500, paid_at => <<"t">>}).

happy_path_test() ->
    {ok, [Ev]} = maybe_capture_payment:handle(mk_cmd(#{}), initiated()),
    ?assertEqual(<<"sess-1">>, payment_captured_v1:get_session_id(Ev)),
    ?assertEqual(500,          payment_captured_v1:get_fee_cents(Ev)),
    ?assertEqual(<<"2026-05-26T09:55:00Z">>, payment_captured_v1:get_paid_at(Ev)).

rejects_when_not_initiated_test() ->
    ?assertEqual({error, session_not_initiated},
                 maybe_capture_payment:handle(mk_cmd(#{}), empty())).

rejects_when_already_paid_test() ->
    ?assertEqual({error, session_already_paid},
                 maybe_capture_payment:handle(mk_cmd(#{}), paid())).

rejects_missing_fee_cents_test() ->
    Cmd = mk_cmd(#{<<"fee_cents">> => undefined}),
    ?assertEqual({error, missing_fee_cents},
                 maybe_capture_payment:handle(Cmd, initiated())).

rejects_negative_fee_cents_test() ->
    Cmd = mk_cmd(#{<<"fee_cents">> => -1}),
    ?assertEqual({error, invalid_fee_cents},
                 maybe_capture_payment:handle(Cmd, initiated())).

handler_defaults_paid_at_when_absent_test() ->
    Cmd = mk_cmd(#{<<"paid_at">> => undefined}),
    {ok, [Ev]} = maybe_capture_payment:handle(Cmd, initiated()),
    Ts = payment_captured_v1:get_paid_at(Ev),
    ?assert(is_binary(Ts)),
    ?assert(byte_size(Ts) >= 20).
