%%% @doc Handler for `charge_battery_v1`.
%%%
%%% Requires the vehicle to be DOCKED (or already SERVICING — a vehicle can
%%% charge then get cleaned in one visit). Emits `battery_charged_v1`,
%%% defaulting the restored level to a full 100 when the caller didn't
%%% specify one.
-module(maybe_charge_battery).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_vehicle_lifecycle/include/vehicle_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

%% Cost model: a full pack is ~60 kWh; energy runs ~30 cents/kWh. The
%% charging cost is derived from how much the battery was topped up, so it
%% varies per charge and is a real operator expense in the stream.
-define(BATTERY_CAPACITY_KWH, 60).
-define(CHARGE_CENTS_PER_KWH, 30).

-spec handle(charge_battery_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, vehicle_state:new(<<>>)).

-spec handle(charge_battery_v1:t(), #vehicle_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case charge_battery_v1:validate(Cmd) of
        ok ->
            case can_charge(State) of
                false -> {error, vehicle_not_docked};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

can_charge(State) ->
    vehicle_state:is_docked(State) orelse vehicle_state:is_servicing(State).

emit(Cmd, State) ->
    After  = coalesce(charge_battery_v1:get_battery_pct(Cmd), 100),
    Before = num_or(vehicle_state:battery_pct(State), 0),
    EnergyKwh = erlang:max(0, After - Before) / 100 * ?BATTERY_CAPACITY_KWH,
    {ok, Ev} = battery_charged_v1:new(#{
        vehicle_id         => charge_battery_v1:get_vehicle_id(Cmd),
        battery_soh_pct    => charge_battery_v1:get_battery_soh_pct(Cmd),
        charge_cycle       => charge_battery_v1:get_charge_cycle(Cmd),
        plate        => vehicle_state:plate(State),
        company_id         => vehicle_state:company_id(State),
        battery_pct        => After,
        battery_pct_before => Before,
        energy_kwh         => round1(EnergyKwh),
        charging_cents     => round(EnergyKwh * ?CHARGE_CENTS_PER_KWH),
        charged_at         => coalesce(charge_battery_v1:get_charged_at(Cmd),
                                       iso8601_now())
    }),
    {ok, [battery_charged_v1:to_map(Ev)]}.

num_or(N, _) when is_number(N) -> N;
num_or(_, Default)             -> Default.

round1(F) -> round(F * 10) / 10.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(charge_battery_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case charge_battery_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    VehicleId = charge_battery_v1:get_vehicle_id(Cmd),
    EvoqCmd = evoq_command:new(
        charge_battery, vehicle_aggregate, vehicle_aggregate:stream_id(VehicleId),
        charge_battery_v1:to_map(Cmd),
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
