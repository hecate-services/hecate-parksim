%%% @doc Handler for `pick_up_passenger_v1`.
%%%
%%% Requires the vehicle to be DISPATCHED (en route to a pickup). Emits
%%% `passenger_picked_up_v1`, flipping the vehicle to ON_TRIP.
-module(maybe_pick_up_passenger).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(pick_up_passenger_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(pick_up_passenger_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case pick_up_passenger_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_dispatched(State) of
                false -> {error, vehicle_not_dispatched};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = passenger_picked_up_v1:new(#{
        vehicle_id   => pick_up_passenger_v1:get_vehicle_id(Cmd),
        plate        => vehicle_state:plate(State),
        company_id   => vehicle_state:company_id(State),
        ride_id      => vehicle_state:ride_id(State),
        x          => pick_up_passenger_v1:get_x(Cmd),
        y          => pick_up_passenger_v1:get_y(Cmd),
        picked_up_at => coalesce(pick_up_passenger_v1:get_picked_up_at(Cmd),
                                 iso8601_now())
    }),
    {ok, [passenger_picked_up_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(pick_up_passenger_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case pick_up_passenger_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = pick_up_passenger_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        pick_up_passenger, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        pick_up_passenger_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id    => hecate_parksim_service:store_id(),
             adapter     => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

%%--------------------------------------------------------------------
coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
