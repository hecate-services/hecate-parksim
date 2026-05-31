%%% @doc Handler for `dispatch_vehicle_v1`.
%%%
%%% Requires the vehicle to be AVAILABLE (commissioned or cruising) and to
%%% have enough charge to take a fare (>= ?MIN_DISPATCH_BATTERY_PCT). A
%%% too-flat or busy vehicle is refused — the fleet brain will route a
%%% low-battery one to a facility instead. Emits `vehicle_dispatched_v1`.
-module(maybe_dispatch_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-define(MIN_DISPATCH_BATTERY_PCT, 15).

-export([handle/1, handle/2, dispatch/1]).

-spec handle(dispatch_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(dispatch_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case dispatch_vehicle_v1:validate(Cmd) of
        ok               -> check_state(Cmd, State);
        {error, _} = Err -> Err
    end.

check_state(Cmd, State) ->
    case vehicle_state:is_available(State) of
        false -> {error, vehicle_not_available};
        true  ->
            case has_charge(State) of
                false -> {error, battery_too_low};
                true  -> emit(Cmd)
            end
    end.

has_charge(State) ->
    case vehicle_state:battery_pct(State) of
        undefined -> true;  %% unknown -> let the sim decide
        Pct       -> Pct >= ?MIN_DISPATCH_BATTERY_PCT
    end.

emit(Cmd) ->
    {ok, Ev} = vehicle_dispatched_v1:new(#{
        vehicle_id    => dispatch_vehicle_v1:get_vehicle_id(Cmd),
        trip_id       => dispatch_vehicle_v1:get_trip_id(Cmd),
        pickup_x    => dispatch_vehicle_v1:get_pickup_x(Cmd),
        pickup_y    => dispatch_vehicle_v1:get_pickup_y(Cmd),
        dropoff_x   => dispatch_vehicle_v1:get_dropoff_x(Cmd),
        dropoff_y   => dispatch_vehicle_v1:get_dropoff_y(Cmd),
        dispatched_at => coalesce(dispatch_vehicle_v1:get_dispatched_at(Cmd),
                                  iso8601_now())
    }),
    {ok, [vehicle_dispatched_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(dispatch_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case dispatch_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = dispatch_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        dispatch_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        dispatch_vehicle_v1:to_map(Cmd),
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
