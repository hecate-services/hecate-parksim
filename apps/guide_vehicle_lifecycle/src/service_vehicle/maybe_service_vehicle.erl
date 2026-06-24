%%% @doc Handler for `service_vehicle_v1`.
%%%
%%% Requires the vehicle to be DOCKED (or already SERVICING — a vehicle can
%%% receive more than one service in a single dock, e.g. charge then clean).
%%% Emits `vehicle_serviced_v1`. For a charge with no explicit battery_pct,
%%% the event defaults the restored level to 100 (state module applies it).
-module(maybe_service_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(service_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(service_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case service_vehicle_v1:validate(Cmd) of
        ok ->
            case can_service(State) of
                false -> {error, vehicle_not_docked};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

can_service(State) ->
    vehicle_state:is_docked(State) orelse vehicle_state:is_servicing(State).

emit(Cmd, State) ->
    Kind = service_vehicle_v1:get_kind(Cmd),
    %% A charge restores the battery; default to a full top-up if the caller
    %% didn't specify a level. clean/maintain leave the battery alone.
    Battery = case {Kind, service_vehicle_v1:get_battery_pct(Cmd)} of
        {<<"charge">>, undefined} -> 100;
        {_,            Pct}       -> Pct
    end,
    {ok, Ev} = vehicle_serviced_v1:new(#{
        vehicle_id   => service_vehicle_v1:get_vehicle_id(Cmd),
        company_id   => vehicle_state:company_id(State),
        service_kind => Kind,
        battery_pct  => Battery,
        serviced_at  => coalesce(service_vehicle_v1:get_serviced_at(Cmd),
                                 iso8601_now())
    }),
    {ok, [vehicle_serviced_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(service_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case service_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = service_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        service_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        service_vehicle_v1:to_map(Cmd),
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
