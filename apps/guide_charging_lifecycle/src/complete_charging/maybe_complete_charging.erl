%%% @doc Handler for `complete_charging_v1`.
%%%
%%% Requires the session to be CHARGING. Emits `charging_completed_v1',
%%% defaulting the total energy to the accumulated running total on the session.
-module(maybe_complete_charging).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(complete_charging_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, charging_state:new(<<>>)).

-spec handle(complete_charging_v1:t(), #charging_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case complete_charging_v1:validate(Cmd) of
        ok ->
            case charging_state:is_charging(State) of
                false -> {error, charge_not_running};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    Energy = coalesce(complete_charging_v1:get_energy_kwh(Cmd),
                      charging_state:energy_kwh(State)),
    {ok, Ev} = charging_completed_v1:new(#{
        session_id      => complete_charging_v1:get_session_id(Cmd),
        vehicle_id      => coalesce(complete_charging_v1:get_vehicle_id(Cmd),
                                    charging_state:vehicle_id(State)),
        final_soc_pct   => complete_charging_v1:get_final_soc_pct(Cmd),
        energy_kwh      => Energy,
        charge_cycle    => complete_charging_v1:get_charge_cycle(Cmd),
        battery_soh_pct => complete_charging_v1:get_battery_soh_pct(Cmd),
        completed_at    => coalesce(complete_charging_v1:get_completed_at(Cmd),
                                    iso8601_now())
    }),
    {ok, [charging_completed_v1:to_map(Ev)]}.

-spec dispatch(complete_charging_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case complete_charging_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = complete_charging_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        complete_charging, charging_aggregate, charging_aggregate:stream_id(SessionId),
        complete_charging_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id    => hecate_parksim_service:store_id(),
             adapter     => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
