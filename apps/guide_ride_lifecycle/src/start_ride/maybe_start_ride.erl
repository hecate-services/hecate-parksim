%%% @doc Handler for `start_ride_v1`. Requires the ride to be ASSIGNED.
%%% Emits `ride_started_v1'.
-module(maybe_start_ride).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(start_ride_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, ride_state:new(<<>>)).

-spec handle(start_ride_v1:t(), #ride_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case start_ride_v1:validate(Cmd) of
        ok ->
            case ride_state:is_assigned(State) of
                false -> {error, ride_not_assigned};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = ride_started_v1:new(#{
        ride_id    => start_ride_v1:get_ride_id(Cmd),
        vehicle_id => ride_state:vehicle_id(State),
        started_at => coalesce(start_ride_v1:get_started_at(Cmd), iso8601_now())
    }),
    {ok, [ride_started_v1:to_map(Ev)]}.

-spec dispatch(start_ride_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case start_ride_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    RideId = start_ride_v1:get_ride_id(Cmd),
    EvoqCmd = evoq_command:new(
        start_ride, ride_aggregate, ride_aggregate:stream_id(RideId),
        start_ride_v1:to_map(Cmd),
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
