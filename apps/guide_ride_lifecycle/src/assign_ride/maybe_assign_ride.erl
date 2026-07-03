%%% @doc Handler for `assign_ride_v1`. Requires the ride to be REQUESTED
%%% (still waiting). Emits `ride_assigned_v1'.
-module(maybe_assign_ride).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(assign_ride_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, ride_state:new(<<>>)).

-spec handle(assign_ride_v1:t(), #ride_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case assign_ride_v1:validate(Cmd) of
        ok ->
            case ride_state:is_requested(State) of
                false -> {error, ride_not_requested};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = ride_assigned_v1:new(#{
        ride_id     => assign_ride_v1:get_ride_id(Cmd),
        company_id => ride_state:company_id(State),
        vehicle_id  => assign_ride_v1:get_vehicle_id(Cmd),
        assigned_at => coalesce(assign_ride_v1:get_assigned_at(Cmd), iso8601_now())
    }),
    {ok, [ride_assigned_v1:to_map(Ev)]}.

-spec dispatch(assign_ride_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case assign_ride_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    RideId = assign_ride_v1:get_ride_id(Cmd),
    EvoqCmd = evoq_command:new(
        assign_ride, ride_aggregate, ride_aggregate:stream_id(RideId),
        assign_ride_v1:to_map(Cmd),
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
