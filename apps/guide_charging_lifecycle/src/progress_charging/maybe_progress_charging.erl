%%% @doc Handler for `progress_charging_v1`.
%%%
%%% Requires the session to be CHARGING. Emits `charging_progressed_v1' with the
%%% running energy total (derived from state + this milestone's delta when the
%%% caller didn't supply an explicit total).
-module(maybe_progress_charging).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(progress_charging_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, charging_state:new(<<>>)).

-spec handle(progress_charging_v1:t(), #charging_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case progress_charging_v1:validate(Cmd) of
        ok ->
            case charging_state:is_charging(State) of
                false -> {error, charge_not_running};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    Delta = num_or(progress_charging_v1:get_energy_kwh_delta(Cmd), 0),
    Total = coalesce(progress_charging_v1:get_energy_kwh_total(Cmd),
                     round1(charging_state:energy_kwh(State) + Delta)),
    {ok, Ev} = charging_progressed_v1:new(#{
        session_id       => progress_charging_v1:get_session_id(Cmd),
        vehicle_id       => coalesce(progress_charging_v1:get_vehicle_id(Cmd),
                                     charging_state:vehicle_id(State)),
        soc_pct          => progress_charging_v1:get_soc_pct(Cmd),
        energy_kwh_delta => Delta,
        energy_kwh_total => Total,
        progressed_at    => coalesce(progress_charging_v1:get_progressed_at(Cmd),
                                     iso8601_now())
    }),
    {ok, [charging_progressed_v1:to_map(Ev)]}.

-spec dispatch(progress_charging_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case progress_charging_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = progress_charging_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        progress_charging, charging_aggregate, charging_aggregate:stream_id(SessionId),
        progress_charging_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id    => hecate_parksim_service:store_id(),
             adapter     => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

num_or(N, _) when is_number(N) -> N;
num_or(_, Default)             -> Default.

round1(F) -> round(F * 10) / 10.

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
