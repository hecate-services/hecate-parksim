%%% @doc Handler for `initiate_parking_session_v1`.
%%%
%%% Refuses if the session has already been initiated. Otherwise
%%% emits `parking_session_initiated_v1`. The caller supplies
%%% `entered_at` (simulated time from `simulate_clock`); if missing,
%%% the handler defaults to wall-clock.
-module(maybe_initiate_parking_session).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(initiate_parking_session_v1:t()) ->
    {ok, [parking_session_initiated_v1:t()]} | {error, term()}.
handle(Cmd) ->
    handle(Cmd, parking_session_state:new(<<>>)).

-spec handle(initiate_parking_session_v1:t(), #parking_session_state{}) ->
    {ok, [parking_session_initiated_v1:t()]} | {error, term()}.
handle(Cmd, State) ->
    case initiate_parking_session_v1:validate(Cmd) of
        ok ->
            case parking_session_state:is_initiated(State) of
                true  -> {error, session_already_initiated};
                false -> emit(Cmd)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd) ->
    {ok, Event} = parking_session_initiated_v1:new(#{
        session_id => initiate_parking_session_v1:get_session_id(Cmd),
        lot_id     => initiate_parking_session_v1:get_lot_id(Cmd),
        plate      => initiate_parking_session_v1:get_plate(Cmd),
        card_id    => initiate_parking_session_v1:get_card_id(Cmd),
        permit_ref => initiate_parking_session_v1:get_permit_ref(Cmd),
        entered_at => coalesce(initiate_parking_session_v1:get_entered_at(Cmd),
                               iso8601_now())
    }),
    {ok, [Event]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(initiate_parking_session_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case initiate_parking_session_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = initiate_parking_session_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        initiate_parking_session,
        parking_session_aggregate,
        SessionId,
        initiate_parking_session_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{
        store_id    => hecate_parksim_service:store_id(),
        adapter     => reckon_evoq_adapter,
        consistency => eventual
    },
    evoq_command_router:dispatch(EvoqCmd, Opts).

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
