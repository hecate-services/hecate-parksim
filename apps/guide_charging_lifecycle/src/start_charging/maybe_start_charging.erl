%%% @doc Handler for `start_charging_v1`.
%%%
%%% Requires the session to be in the REQUESTED phase. Emits
%%% `charging_started_v1', carrying the tariff the scheduler plugged in at.
-module(maybe_start_charging).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(start_charging_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, charging_state:new(<<>>)).

-spec handle(start_charging_v1:t(), #charging_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case start_charging_v1:validate(Cmd) of
        ok ->
            case charging_state:is_requested(State) of
                false -> {error, charge_not_requested};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    Before = coalesce(start_charging_v1:get_battery_pct_before(Cmd),
                      charging_state:battery_pct(State)),
    Tariff = coalesce(start_charging_v1:get_tariff_cents_per_kwh(Cmd),
                      charging_state:tariff_cents_per_kwh(State)),
    {ok, Ev} = charging_started_v1:new(#{
        session_id           => start_charging_v1:get_session_id(Cmd),
        vehicle_id           => coalesce(start_charging_v1:get_vehicle_id(Cmd),
                                         charging_state:vehicle_id(State)),
        company_id           => coalesce(start_charging_v1:get_company_id(Cmd),
                                         charging_state:company_id(State)),
        charger_id           => start_charging_v1:get_charger_id(Cmd),
        battery_pct_before   => Before,
        tariff_cents_per_kwh => Tariff,
        started_at           => coalesce(start_charging_v1:get_started_at(Cmd),
                                         iso8601_now())
    }),
    {ok, [charging_started_v1:to_map(Ev)]}.

-spec dispatch(start_charging_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case start_charging_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = start_charging_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        start_charging, charging_aggregate, charging_aggregate:stream_id(SessionId),
        start_charging_v1:to_map(Cmd),
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
