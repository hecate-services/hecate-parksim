%%% @doc Tests for the archive_parking_session handler.
-module(maybe_archive_parking_session_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

mk_cmd(Overrides) ->
    Base = #{<<"session_id">>  => <<"sess-1">>,
             <<"archived_at">> => <<"2026-05-26T10:00:00Z">>,
             <<"reason">>      => undefined},
    {ok, Cmd} = archive_parking_session_v1:from_map(maps:merge(Base, Overrides)),
    Cmd.

empty()     -> parking_session_state:new(<<"sess-1">>).
initiated() ->
    parking_session_state:apply_event(empty(), #{
        event_type => <<"parking_session_initiated">>,
        session_id => <<"sess-1">>, lot_id => <<"l">>, entered_at => <<"t">>}).
paid()      ->
    parking_session_state:apply_event(initiated(), #{
        event_type => <<"payment_captured">>,
        session_id => <<"sess-1">>, amount_cents => 500, paid_at => <<"t">>}).
archived()  ->
    parking_session_state:apply_event(paid(), #{
        event_type => <<"parking_session_archived">>,
        session_id => <<"sess-1">>, archived_at => <<"t">>}).
%% A permit session is settled at entry (permit_ref on the birth slip).
permit_covered() ->
    parking_session_state:apply_event(empty(), #{
        event_type => <<"parking_session_initiated">>,
        session_id => <<"sess-1">>, lot_id => <<"l">>,
        permit_ref => <<"permit-42">>, entered_at => <<"t">>}).

happy_path_test() ->
    {ok, [Ev]} = maybe_archive_parking_session:handle(mk_cmd(#{}), paid()),
    ?assertEqual(<<"sess-1">>, parking_session_archived_v1:get_session_id(Ev)),
    %% fee_cents echoed from state's amount_cents.
    ?assertEqual(500, parking_session_archived_v1:get_fee_cents(Ev)),
    ?assertEqual(<<"2026-05-26T10:00:00Z">>,
                 parking_session_archived_v1:get_archived_at(Ev)).

rejects_when_not_initiated_test() ->
    ?assertEqual({error, session_not_initiated},
                 maybe_archive_parking_session:handle(mk_cmd(#{}), empty())).

rejects_when_not_settled_test() ->
    ?assertEqual({error, session_not_settled},
                 maybe_archive_parking_session:handle(mk_cmd(#{}), initiated())).

permit_covered_archives_without_payment_test() ->
    Cmd = mk_cmd(#{<<"reason">> => <<"permit">>}),
    {ok, [Ev]} = maybe_archive_parking_session:handle(Cmd, permit_covered()),
    ?assertEqual(<<"sess-1">>, parking_session_archived_v1:get_session_id(Ev)),
    ?assertEqual(<<"permit">>, parking_session_archived_v1:get_reason(Ev)).

rejects_when_already_archived_test() ->
    ?assertEqual({error, session_already_archived},
                 maybe_archive_parking_session:handle(mk_cmd(#{}), archived())).

permit_reason_passes_through_test() ->
    Cmd = mk_cmd(#{<<"reason">> => <<"permit">>}),
    {ok, [Ev]} = maybe_archive_parking_session:handle(Cmd, paid()),
    ?assertEqual(<<"permit">>, parking_session_archived_v1:get_reason(Ev)).

handler_defaults_archived_at_when_absent_test() ->
    Cmd = mk_cmd(#{<<"archived_at">> => undefined}),
    {ok, [Ev]} = maybe_archive_parking_session:handle(Cmd, paid()),
    Ts = parking_session_archived_v1:get_archived_at(Ev),
    ?assert(is_binary(Ts)),
    ?assert(byte_size(Ts) >= 20).

state_after_apply_round_trip_test() ->
    {ok, [Ev]} = maybe_archive_parking_session:handle(mk_cmd(#{}), paid()),
    EvMap = parking_session_archived_v1:to_map(Ev),
    S = parking_session_state:apply_event(paid(), EvMap),
    ?assert(parking_session_state:is_archived(S)).
