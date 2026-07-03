%%% @doc Handler for `clean_vehicle_v1`. Requires the vehicle DOCKED (or
%%% already SERVICING — a clean can follow a charge in one visit). Emits
%%% `vehicle_cleaned_v1`.
-module(maybe_clean_vehicle).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(clean_vehicle_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(clean_vehicle_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case clean_vehicle_v1:validate(Cmd) of
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
    {ok, Ev} = vehicle_cleaned_v1:new(#{
        vehicle_id => clean_vehicle_v1:get_vehicle_id(Cmd),
        company_id => vehicle_state:company_id(State),
        cleaned_at => coalesce(clean_vehicle_v1:get_cleaned_at(Cmd), iso8601_now())
    }),
    {ok, [vehicle_cleaned_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
-spec dispatch(clean_vehicle_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case clean_vehicle_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = clean_vehicle_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        clean_vehicle, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        clean_vehicle_v1:to_map(Cmd),
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
