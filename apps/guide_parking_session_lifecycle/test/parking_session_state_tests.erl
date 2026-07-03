%%% @doc Tests for parking_session_state — event folding + helpers.
-module(parking_session_state_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_status.hrl").

empty()    -> parking_session_state:new(<<"sess-1">>).

apply_each(Evs, S0) ->
    lists:foldl(fun(E, A) -> parking_session_state:apply_event(A, E) end, S0, Evs).

initiated_ev() ->
    #{event_type => <<"parking_session_initiated">>,
      session_id => <<"sess-1">>,
      lot_id     => <<"lot-1">>,
      plate      => <<"1-ABC-123">>,
      card_id    => <<"card-deadbeef">>,
      entered_at => <<"2026-05-26T08:00:00Z">>}.

paid_ev() ->
    #{event_type   => <<"payment_captured">>,
      session_id   => <<"sess-1">>,
      fee_cents => 500,
      paid_at      => <<"2026-05-26T09:55:00Z">>}.

archived_ev() ->
    #{event_type  => <<"parking_session_archived">>,
      session_id  => <<"sess-1">>,
      archived_at => <<"2026-05-26T10:00:00Z">>,
      reason      => undefined}.

%%--------------------------------------------------------------------
%% Initial state

initial_state_test() ->
    S = parking_session_state:new(<<"s">>),
    ?assertEqual(<<"s">>, parking_session_state:session_id(S)),
    ?assertEqual(0, parking_session_state:status_flags(S)),
    ?assertNot(parking_session_state:is_initiated(S)),
    ?assertNot(parking_session_state:is_paid(S)),
    ?assertNot(parking_session_state:is_archived(S)).

%%--------------------------------------------------------------------
%% Fold: initiated

apply_initiated_sets_fields_test() ->
    S = parking_session_state:apply_event(empty(), initiated_ev()),
    ?assert(parking_session_state:is_initiated(S)),
    ?assertEqual(<<"lot-1">>,      parking_session_state:lot_id(S)),
    ?assertEqual(<<"1-ABC-123">>,  parking_session_state:plate(S)),
    ?assertEqual(<<"card-deadbeef">>, parking_session_state:card_id(S)),
    ?assertEqual(<<"2026-05-26T08:00:00Z">>, parking_session_state:entered_at(S)).

%%--------------------------------------------------------------------
%% Fold: paid

apply_paid_sets_amount_test() ->
    S = apply_each([initiated_ev(), paid_ev()], empty()),
    ?assert(parking_session_state:is_initiated(S)),
    ?assert(parking_session_state:is_paid(S)),
    ?assertNot(parking_session_state:is_archived(S)),
    ?assertEqual(500, parking_session_state:fee_cents(S)),
    ?assertEqual(<<"2026-05-26T09:55:00Z">>, parking_session_state:paid_at(S)).

%%--------------------------------------------------------------------
%% Fold: archived

apply_archived_sets_flag_test() ->
    S = apply_each([initiated_ev(), paid_ev(), archived_ev()], empty()),
    ?assert(parking_session_state:is_initiated(S)),
    ?assert(parking_session_state:is_paid(S)),
    ?assert(parking_session_state:is_archived(S)),
    ?assertEqual(<<"2026-05-26T10:00:00Z">>, parking_session_state:archived_at(S)).

archived_preserves_initiated_and_paid_bits_test() ->
    %% Bit-flag model is additive.
    S = apply_each([initiated_ev(), paid_ev(), archived_ev()], empty()),
    ?assert(parking_session_state:has_status(S, ?SESSION_INITIATED)),
    ?assert(parking_session_state:has_status(S, ?SESSION_PAID)),
    ?assert(parking_session_state:has_status(S, ?SESSION_ARCHIVED)).

%%--------------------------------------------------------------------
%% Unknown event safety

unknown_event_returns_state_unchanged_test() ->
    Before = parking_session_state:apply_event(empty(), initiated_ev()),
    After  = parking_session_state:apply_event(Before, #{event_type => <<"some_unknown">>}),
    ?assertEqual(Before, After).
