%%% @doc Handler for `request_charge_v1`.
%%%
%%% Refuses if the session already exists (any phase bit set). Otherwise emits
%%% `charge_requested_v1'. Caller supplies `requested_at' (simulated time);
%%% defaults to wall-clock.
-module(maybe_request_charge).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(request_charge_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, charging_state:new(<<>>)).

-spec handle(request_charge_v1:t(), #charging_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case request_charge_v1:validate(Cmd) of
        ok ->
            case charging_state:is_pristine(State) of
                false -> {error, charge_already_requested};
                true  -> emit(Cmd)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd) ->
    {ok, Ev} = charge_requested_v1:new(#{
        session_id           => request_charge_v1:get_session_id(Cmd),
        vehicle_id           => request_charge_v1:get_vehicle_id(Cmd),
        company_id           => request_charge_v1:get_company_id(Cmd),
        plate                => request_charge_v1:get_plate(Cmd),
        battery_pct_before   => request_charge_v1:get_battery_pct_before(Cmd),
        target_pct           => request_charge_v1:get_target_pct(Cmd),
        tariff_cents_per_kwh => request_charge_v1:get_tariff_cents_per_kwh(Cmd),
        requested_at         => coalesce(request_charge_v1:get_requested_at(Cmd),
                                         iso8601_now())
    }),
    {ok, [charge_requested_v1:to_map(Ev)]}.

-spec dispatch(request_charge_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case request_charge_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = request_charge_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        request_charge, charging_aggregate, charging_aggregate:stream_id(SessionId),
        request_charge_v1:to_map(Cmd),
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
