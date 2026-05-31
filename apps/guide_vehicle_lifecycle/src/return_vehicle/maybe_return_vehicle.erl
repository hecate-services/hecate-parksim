%%% @doc Handler for `return_vehicle_v1`.
%%%
%%% Requires the vehicle to be AVAILABLE (commissioned or cruising) — you
%%% can only pull a vehicle off the market if it isn't mid-trip. Emits
%%% `vehicle_returning_v1`, flipping it to RETURNING.
-module(maybe_return_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(return_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(return_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case return_vehicle_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_available(State) of
                false -> {error, vehicle_not_available};
                true  -> emit(Cmd)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd) ->
    {ok, Ev} = vehicle_returning_v1:new(#{
        vehicle_id   => return_vehicle_v1:get_vehicle_id(Cmd),
        facility_id  => return_vehicle_v1:get_facility_id(Cmd),
        returning_at => coalesce(return_vehicle_v1:get_returning_at(Cmd),
                                 iso8601_now())
    }),
    {ok, [vehicle_returning_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(return_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case return_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = return_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        return_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        return_vehicle_v1:to_map(Cmd),
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
