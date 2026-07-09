%%% @doc Handler for `settle_energy_v1`.
%%%
%%% Requires the session COMPLETED and not yet settled. Computes the cost
%%% (energy_kwh x tariff, rounded to cents) and whether it landed in an off-peak
%%% window, then emits `energy_settled_v1'. Energy/tariff default from the
%%% session state, so a bare `settle_energy` with only the id settles correctly.
-module(maybe_settle_energy).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_charging_lifecycle/include/charging_state.hrl").
-include_lib("guide_charging_lifecycle/include/grid_tariff.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(settle_energy_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, charging_state:new(<<>>)).

-spec handle(settle_energy_v1:t(), #charging_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case settle_energy_v1:validate(Cmd) of
        ok -> guard(Cmd, State);
        {error, _} = Err -> Err
    end.

guard(Cmd, State) ->
    Completed = charging_state:is_completed(State),
    Settled   = charging_state:is_settled(State),
    settle(Completed, Settled, Cmd, State).

settle(false, _Settled, _Cmd, _State) -> {error, charge_not_completed};
settle(true, true, _Cmd, _State)      -> {error, energy_already_settled};
settle(true, false, Cmd, State)       -> emit(Cmd, State).

emit(Cmd, State) ->
    Energy = num_or(coalesce(settle_energy_v1:get_energy_kwh(Cmd),
                             charging_state:energy_kwh(State)), 0),
    Tariff = num_or(coalesce(settle_energy_v1:get_tariff_cents_per_kwh(Cmd),
                             charging_state:tariff_cents_per_kwh(State)), 0),
    Cost   = round(Energy * Tariff),
    {ok, Ev} = energy_settled_v1:new(#{
        session_id           => settle_energy_v1:get_session_id(Cmd),
        vehicle_id           => coalesce(settle_energy_v1:get_vehicle_id(Cmd),
                                         charging_state:vehicle_id(State)),
        company_id           => coalesce(settle_energy_v1:get_company_id(Cmd),
                                         charging_state:company_id(State)),
        energy_kwh           => Energy,
        tariff_cents_per_kwh => Tariff,
        cost_cents           => Cost,
        off_peak             => Tariff =< ?OFF_PEAK_MAX_CENTS,
        settled_at           => coalesce(settle_energy_v1:get_settled_at(Cmd),
                                         iso8601_now())
    }),
    {ok, [energy_settled_v1:to_map(Ev)]}.

-spec dispatch(settle_energy_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case settle_energy_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = settle_energy_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        settle_energy, charging_aggregate, charging_aggregate:stream_id(SessionId),
        settle_energy_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id    => hecate_parksim_service:store_id(),
             adapter     => reckon_evoq_adapter,
             consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

num_or(N, _) when is_number(N) -> N;
num_or(_, Default)             -> Default.

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
