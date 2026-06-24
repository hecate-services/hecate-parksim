%%% @doc Handler for `capture_payment_v1`.
%%%
%%% Requires session to be INITIATED, not yet PAID. Caller supplies
%%% `paid_at` (simulated time); defaults to wall-clock if missing.
-module(maybe_capture_payment).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(capture_payment_v1:t()) ->
    {ok, [payment_captured_v1:t()]} | {error, term()}.
handle(Cmd) ->
    handle(Cmd, parking_session_state:new(<<>>)).

-spec handle(capture_payment_v1:t(), #parking_session_state{}) ->
    {ok, [payment_captured_v1:t()]} | {error, term()}.
handle(Cmd, State) ->
    case capture_payment_v1:validate(Cmd) of
        ok               -> check_state(Cmd, State);
        {error, _} = Err -> Err
    end.

check_state(Cmd, State) ->
    case parking_session_state:is_initiated(State) of
        false -> {error, session_not_initiated};
        true ->
            case parking_session_state:is_paid(State) of
                true  -> {error, session_already_paid};
                false -> emit(Cmd, State)
            end
    end.

emit(Cmd, State) ->
    PaymentMethod = case parking_session_state:permit_ref(State) of
        undefined -> <<"card">>;
        _Ref      -> <<"permit">>
    end,
    {ok, Event} = payment_captured_v1:new(#{
        session_id     => capture_payment_v1:get_session_id(Cmd),
        amount_cents   => capture_payment_v1:get_amount_cents(Cmd),
        plate          => parking_session_state:plate(State),
        lot_id         => parking_session_state:lot_id(State),
        payment_method => PaymentMethod,
        paid_at        => coalesce(capture_payment_v1:get_paid_at(Cmd),
                                   iso8601_now())
    }),
    {ok, [Event]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(capture_payment_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case capture_payment_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = capture_payment_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        capture_payment,
        parking_session_aggregate,
        SessionId,
        capture_payment_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{
        store_id    => hecate_parksim_service:store_id(),
        adapter     => reckon_evoq_adapter,
        consistency => eventual
    },
    evoq_dispatcher:dispatch(EvoqCmd, Opts).

%%--------------------------------------------------------------------
%% Helpers

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
        [Y, Mo, D, H, Mi, S])).
