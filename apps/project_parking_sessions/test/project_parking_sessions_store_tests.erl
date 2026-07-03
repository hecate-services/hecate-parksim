%%% @doc Store tests against a real temp SQLite DB — exercises the
%%% upsert path, bitwise-flag overview, and get/recent.
-module(project_parking_sessions_store_tests).

-include_lib("eunit/include/eunit.hrl").

setup() ->
    Tmp = filename:join("/tmp",
        "parksim_prj_test_" ++ integer_to_list(erlang:unique_integer([positive]))),
    os:putenv("HECATE_DATA_DIR", Tmp),
    os:putenv("TENANT_ID", "test"),
    {ok, Pid} = project_parking_sessions_store:start_link(),
    {Pid, Tmp}.

cleanup({Pid, Tmp}) ->
    gen_server:stop(Pid),
    os:cmd("rm -rf " ++ Tmp),
    ok.

ev(Type, Fields) -> Fields#{event_type => Type}.

%% A completed ticket session A (5 events) and an in-progress B (2).
seed() ->
    S = project_parking_sessions_store,
    A = <<"sess-A">>, B = <<"sess-B">>,
    ok = S:apply_event(ev(<<"parking_session_initiated">>,
            #{session_id => A, lot_id => <<"lot-x">>, plate => <<"1-AAA-1">>, entered_at => <<"t1">>})),
    ok = S:apply_event(ev(<<"vehicle_docked">>,
            #{session_id => A, bay_id => <<"lot-x-bay-3">>, docked_at => <<"t2">>})),
    ok = S:apply_event(ev(<<"payment_captured">>,
            #{session_id => A, fee_cents => 500, paid_at => <<"t3">>})),
    ok = S:apply_event(ev(<<"vehicle_undocked">>, #{session_id => A, undocked_at => <<"t4">>})),
    ok = S:apply_event(ev(<<"parking_session_archived">>, #{session_id => A, archived_at => <<"t5">>})),
    ok = S:apply_event(ev(<<"parking_session_initiated">>,
            #{session_id => B, lot_id => <<"lot-x">>, plate => <<"2-BBB-2">>, entered_at => <<"t6">>})),
    ok = S:apply_event(ev(<<"vehicle_docked">>,
            #{session_id => B, bay_id => <<"lot-x-bay-9">>, docked_at => <<"t7">>})),
    ok.

store_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(_) ->
        seed(),
        ok = project_parking_sessions_store:flush_now(),  %% writes are async; drain first
        {ok, O} = project_parking_sessions_store:overview(),
        {ok, A} = project_parking_sessions_store:get(<<"sess-A">>),
        Missing = project_parking_sessions_store:get(<<"nope">>),
        {ok, Recent} = project_parking_sessions_store:recent(10),
        [ ?_assertEqual(2, maps:get(total, O)),
          ?_assertEqual(1, maps:get(archived, O)),
          ?_assertEqual(1, maps:get(paid, O)),
          ?_assertEqual(2, maps:get(docked, O)),
          ?_assertEqual(1, maps:get(in_progress, O)),
          ?_assertEqual(500, maps:get(revenue_cents, O)),
          ?_assertEqual([#{lot_id => <<"lot-x">>, sessions => 2}], maps:get(by_lot, O)),
          ?_assertEqual(500, maps:get(fee_cents, A)),
          ?_assertEqual(<<"lot-x-bay-3">>, maps:get(bay_id, A)),
          ?_assertEqual(<<"t5">>, maps:get(archived_at, A)),
          ?_assertEqual({error, not_found}, Missing),
          ?_assertEqual(2, length(Recent)) ]
     end}.
