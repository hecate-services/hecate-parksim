%%% @doc Handler for `deplete_battery_v1`.
%%%
%%% A vehicle can only deplete while it's actually moving under its own
%%% power — DISPATCHED, ON_TRIP, or RETURNING. Refuses if already DEPLETED
%%% (idempotent) or parked/servicing (can't run flat sitting in a bay).
%%% Emits `battery_depleted_v1`.
-module(maybe_deplete_battery).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(deplete_battery_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(deplete_battery_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case deplete_battery_v1:validate(Cmd) of
        ok ->
            case vehicle_state:is_depleted(State) of
                true  -> {error, vehicle_already_depleted};
                false ->
                    case is_moving(State) of
                        false -> {error, vehicle_not_moving};
                        true  -> emit(Cmd)
                    end
            end;
        {error, _} = Err -> Err
    end.

%% Drawing power on the road: heading to a pickup, carrying a passenger, or
%% returning to a facility.
is_moving(State) ->
    vehicle_state:is_dispatched(State)
        orelse vehicle_state:is_on_trip(State)
        orelse vehicle_state:is_returning(State).

emit(Cmd) ->
    {ok, Ev} = battery_depleted_v1:new(#{
        vehicle_id  => deplete_battery_v1:get_vehicle_id(Cmd),
        x         => deplete_battery_v1:get_x(Cmd),
        y         => deplete_battery_v1:get_y(Cmd),
        depleted_at => coalesce(deplete_battery_v1:get_depleted_at(Cmd),
                                iso8601_now())
    }),
    {ok, [battery_depleted_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(deplete_battery_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case deplete_battery_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = deplete_battery_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        deplete_battery, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        deplete_battery_v1:to_map(Cmd),
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
