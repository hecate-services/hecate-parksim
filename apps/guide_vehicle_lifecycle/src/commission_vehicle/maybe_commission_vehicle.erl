%%% @doc Handler for `commission_vehicle_v1`.
%%%
%%% Refuses if the vehicle already exists (any phase bit set). Otherwise
%%% emits `vehicle_commissioned_v1`. Returns already-serialised event maps
%%% (the aggregate threads them straight through). Caller supplies
%%% `commissioned_at` (simulated time); defaults to wall-clock.
-module(maybe_commission_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(commission_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(commission_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case commission_vehicle_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_pristine(State) of
                false -> {error, vehicle_already_commissioned};
                true  -> emit(Cmd)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd) ->
    {ok, Ev} = vehicle_commissioned_v1:new(#{
        vehicle_id      => commission_vehicle_v1:get_vehicle_id(Cmd),
        company_id      => commission_vehicle_v1:get_company_id(Cmd),
        battery_pct     => commission_vehicle_v1:get_battery_pct(Cmd),
        x             => commission_vehicle_v1:get_x(Cmd),
        y             => commission_vehicle_v1:get_y(Cmd),
        commissioned_at => coalesce(commission_vehicle_v1:get_commissioned_at(Cmd),
                                    iso8601_now())
    }),
    {ok, [vehicle_commissioned_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(commission_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case commission_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = commission_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        commission_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        commission_vehicle_v1:to_map(Cmd),
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
