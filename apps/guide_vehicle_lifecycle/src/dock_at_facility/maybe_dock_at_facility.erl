%%% @doc Handler for `dock_at_facility_v1`.
%%%
%%% Requires the vehicle to be RETURNING (heading to a facility). A depleted
%%% (stranded) vehicle can also dock — it's been towed in — so RETURNING or
%%% DEPLETED both qualify. Emits `vehicle_docked_at_facility_v1`.
%%%
%%% Bay uniqueness (DCB) is enforced by the caller (`simulate_fleet.erl`)
%%% before dispatching this command, following the same pattern as
%%% `parking_session_dcb` in `simulate_visit`.
%%% (`_at_facility` disambiguates from the parking-session `maybe_dock_vehicle`.)
-module(maybe_dock_at_facility).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(dock_at_facility_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(dock_at_facility_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case dock_at_facility_v1:validate(Cmd) of
        ok ->
            case can_dock(State) of
                false -> {error, vehicle_not_returning};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

%% Returning normally, or towed in after depletion.
can_dock(State) ->
    vehicle_state:is_returning(State) orelse vehicle_state:is_depleted(State).

emit(Cmd, State) ->
    {ok, Ev} = vehicle_docked_at_facility_v1:new(#{
        vehicle_id  => dock_at_facility_v1:get_vehicle_id(Cmd),
        company_id  => vehicle_state:company_id(State),
        facility_id => dock_at_facility_v1:get_facility_id(Cmd),
        bay_id      => dock_at_facility_v1:get_bay_id(Cmd),
        x           => dock_at_facility_v1:get_x(Cmd),
        y           => dock_at_facility_v1:get_y(Cmd),
        docked_at   => coalesce(dock_at_facility_v1:get_docked_at(Cmd), iso8601_now())
    }),
    {ok, [vehicle_docked_at_facility_v1:to_map(Ev)]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(dock_at_facility_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case dock_at_facility_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = dock_at_facility_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        dock_at_facility, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        dock_at_facility_v1:to_map(Cmd),
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
