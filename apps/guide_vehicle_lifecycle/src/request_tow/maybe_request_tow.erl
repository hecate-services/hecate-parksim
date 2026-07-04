%%% @doc Handler for `request_tow_v1'. Requires the vehicle DEPLETED. Emits
%%% `tow_requested_v1' (the vehicle stays stranded until a truck arrives).
-module(maybe_request_tow).
-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").
-export([handle/1, handle/2, dispatch/1]).
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).
handle(Cmd, State) ->
    case request_tow_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_depleted(State) of
                false -> {error, vehicle_not_depleted};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.
emit(Cmd, State) ->
    {ok, Ev} = tow_requested_v1:new(#{
        vehicle_id   => request_tow_v1:get_vehicle_id(Cmd),
        plate        => vehicle_state:plate(State),
        company_id   => vehicle_state:company_id(State),
        x            => request_tow_v1:get_x(Cmd),
        y            => request_tow_v1:get_y(Cmd),
        requested_at => coalesce(request_tow_v1:get_requested_at(Cmd), iso8601_now())}),
    {ok, [tow_requested_v1:to_map(Ev)]}.
dispatch(#{} = Data) ->
    case request_tow_v1:from_map(Data) of {ok, Cmd} -> dispatch(Cmd); {error,_}=E -> E end;
dispatch(Cmd) ->
    Id = request_tow_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(request_tow, vehicle_aggregate, vehicle_aggregate:stream_id(Id), request_tow_v1:to_map(Cmd), #{timestamp => erlang:system_time(millisecond)}),
    evoq_command_router:dispatch(EvoqCmd, #{store_id => hecate_parksim_service:store_id(), adapter => reckon_evoq_adapter, consistency => eventual}).
coalesce(undefined, D) -> D; coalesce(V, _) -> V.
iso8601_now() ->
    {{Y,Mo,D},{H,Mi,S}} = calendar:system_time_to_universal_time(erlang:system_time(second), second),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",[Y,Mo,D,H,Mi,S])).
