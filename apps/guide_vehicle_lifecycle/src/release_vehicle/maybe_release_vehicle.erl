%%% @doc Handler for `release_vehicle_v1`.
%%%
%%% Requires the vehicle to be SERVICING or DOCKED (docked-but-not-yet-
%%% serviced is allowed to leave, e.g. a false alarm). Emits
%%% `vehicle_released_v1`, flipping it back to CRUISING.
%%%
%%% Bay DCB release is called by the caller (`simulate_fleet.erl`) after
%%% the command succeeds, following the same pattern as `parking_session_dcb`
%%% in `simulate_visit`.
-module(maybe_release_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(release_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(release_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case release_vehicle_v1:validate(Cmd) of
        ok ->
            case can_release(State) of
                false -> {error, vehicle_not_in_facility};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

can_release(State) ->
    vehicle_state:is_servicing(State) orelse vehicle_state:is_docked(State).

emit(Cmd, State) ->
    {ok, Ev} = vehicle_released_v1:new(#{
        vehicle_id  => release_vehicle_v1:get_vehicle_id(Cmd),
        company_id  => vehicle_state:company_id(State),
        released_at => coalesce(release_vehicle_v1:get_released_at(Cmd),
                                iso8601_now())
    }),
    {ok, [vehicle_released_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(release_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case release_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = release_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        release_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        release_vehicle_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id    => hecate_parksim_service:store_id(),
             adapter     => reckon_evoq_adapter,
             consistency => eventual},
    evoq_dispatcher:dispatch(EvoqCmd, Opts).

%%--------------------------------------------------------------------
coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
