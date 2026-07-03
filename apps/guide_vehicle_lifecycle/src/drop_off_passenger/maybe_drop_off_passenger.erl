%%% @doc Handler for `drop_off_passenger_v1`.
%%%
%%% Requires the vehicle to be ON_TRIP. Emits TWO events in order:
%%% `passenger_dropped_off_v1` (trip done -> cruising) and
%%% `fare_collected_v1` (the fare, tagged with the trip_id read from
%%% current state). A zero fare still emits the fare event (audit trail);
%%% the read model can ignore zero amounts if it wants.
-module(maybe_drop_off_passenger).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(drop_off_passenger_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(drop_off_passenger_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case drop_off_passenger_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_on_trip(State) of
                false -> {error, vehicle_not_on_trip};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    At = coalesce(drop_off_passenger_v1:get_dropped_off_at(Cmd), iso8601_now()),
    CompanyId = vehicle_state:company_id(State),
    RideId = vehicle_state:ride_id(State),
    {ok, Dropped} = passenger_dropped_off_v1:new(#{
        vehicle_id     => drop_off_passenger_v1:get_vehicle_id(Cmd),
        company_id     => CompanyId,
        ride_id        => RideId,
        x            => drop_off_passenger_v1:get_x(Cmd),
        y            => drop_off_passenger_v1:get_y(Cmd),
        dropped_off_at => At
    }),
    {ok, Fare} = fare_collected_v1:new(#{
        vehicle_id   => drop_off_passenger_v1:get_vehicle_id(Cmd),
        company_id   => CompanyId,
        ride_id      => RideId,
        trip_id      => vehicle_state:trip_id(State),
        fare_cents => drop_off_passenger_v1:get_fare_cents(Cmd),
        collected_at => At
    }),
    {ok, [passenger_dropped_off_v1:to_map(Dropped),
          fare_collected_v1:to_map(Fare)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(drop_off_passenger_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case drop_off_passenger_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = drop_off_passenger_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        drop_off_passenger, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        drop_off_passenger_v1:to_map(Cmd),
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
