%%% @doc Handler for `undock_vehicle_v1`.
%%%
%%% Requires the session to be DOCKED and not yet UNDOCKED. Emits
%%% `vehicle_undocked_v1`. Payment is independent: it may already have
%%% happened (kiosk) or come later (exit-island), so it isn't checked
%%% here. Caller supplies `undocked_at` (simulated time); defaults to
%%% wall-clock if missing.
-module(maybe_undock_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(undock_vehicle_v1:t()) ->
    {ok, [vehicle_undocked_v1:t()]} | {error, term()}.
handle(Cmd) ->
    handle(Cmd, parking_session_state:new(<<>>)).

-spec handle(undock_vehicle_v1:t(), #parking_session_state{}) ->
    {ok, [vehicle_undocked_v1:t()]} | {error, term()}.
handle(Cmd, State) ->
    case undock_vehicle_v1:validate(Cmd) of
        ok               -> check_state(Cmd, State);
        {error, _} = Err -> Err
    end.

check_state(Cmd, State) ->
    case parking_session_state:is_docked(State) of
        false -> {error, vehicle_not_docked};
        true ->
            case parking_session_state:is_undocked(State) of
                true  -> {error, vehicle_already_undocked};
                false -> emit(Cmd, State)
            end
    end.

emit(Cmd, State) ->
    {ok, Event} = vehicle_undocked_v1:new(#{
        session_id  => undock_vehicle_v1:get_session_id(Cmd),
        plate       => parking_session_state:plate(State),
        lot_id      => parking_session_state:lot_id(State),
        bay_id      => parking_session_state:bay_id(State),
        undocked_at => coalesce(undock_vehicle_v1:get_undocked_at(Cmd), iso8601_now())
    }),
    {ok, [Event]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(undock_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case undock_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = undock_vehicle_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        undock_vehicle,
        parking_session_aggregate,
        SessionId,
        undock_vehicle_v1:to_map(Cmd),
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
