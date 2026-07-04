%%% @doc Handler for `complete_ride_v1`. Requires the ride to be STARTED.
%%% Emits `ride_completed_v1'.
-module(maybe_complete_ride).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(complete_ride_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, ride_state:new(<<>>)).

-spec handle(complete_ride_v1:t(), #ride_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case complete_ride_v1:validate(Cmd) of
        ok ->
            case ride_state:is_started(State) of
                false -> {error, ride_not_started};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = ride_completed_v1:new(#{
        ride_id      => complete_ride_v1:get_ride_id(Cmd),
        company_id   => ride_state:company_id(State),
        vehicle_id   => ride_state:vehicle_id(State),
        plate        => ride_state:plate(State),
        fare_cents   => complete_ride_v1:get_fare_cents(Cmd),
        tip_cents    => complete_ride_v1:get_tip_cents(Cmd),
        rating       => complete_ride_v1:get_rating(Cmd),
        completed_at => coalesce(complete_ride_v1:get_completed_at(Cmd), iso8601_now())
    }),
    {ok, [ride_completed_v1:to_map(Ev)]}.

-spec dispatch(complete_ride_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case complete_ride_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    RideId = complete_ride_v1:get_ride_id(Cmd),
    EvoqCmd = evoq_command:new(
        complete_ride, ride_aggregate, ride_aggregate:stream_id(RideId),
        complete_ride_v1:to_map(Cmd),
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
