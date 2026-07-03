%%% @doc Handler for `tow_vehicle_v1`. Requires the vehicle DEPLETED
%%% (stranded). Emits `vehicle_towed_v1`; the vehicle is then RETURNING to
%%% the destination facility.
-module(maybe_tow_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(tow_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(tow_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case tow_vehicle_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_depleted(State) of
                false -> {error, vehicle_not_depleted};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = vehicle_towed_v1:new(#{
        vehicle_id              => tow_vehicle_v1:get_vehicle_id(Cmd),
        company_id              => vehicle_state:company_id(State),
        from_x                  => tow_vehicle_v1:get_from_x(Cmd),
        from_y                  => tow_vehicle_v1:get_from_y(Cmd),
        destination_facility_id => tow_vehicle_v1:get_destination_facility_id(Cmd),
        tow_distance_m          => tow_vehicle_v1:get_tow_distance_m(Cmd),
        tow_cents               => tow_vehicle_v1:get_tow_cents(Cmd),
        towed_at                => coalesce(tow_vehicle_v1:get_towed_at(Cmd),
                                            iso8601_now())
    }),
    {ok, [vehicle_towed_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
-spec dispatch(tow_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case tow_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = tow_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        tow_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        tow_vehicle_v1:to_map(Cmd),
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
