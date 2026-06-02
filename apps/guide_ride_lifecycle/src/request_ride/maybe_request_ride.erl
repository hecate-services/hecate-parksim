%%% @doc Handler for `request_ride_v1`.
%%%
%%% Refuses if the ride already exists (any phase bit set). Otherwise emits
%%% `ride_requested_v1'. Returns already-serialised event maps (the aggregate
%%% threads them straight through). Caller supplies `requested_at' (simulated
%%% time); defaults to wall-clock.
-module(maybe_request_ride).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(request_ride_v1:t()) -> {ok, [map()]} | {error, term()}.
handle(Cmd) -> handle(Cmd, ride_state:new(<<>>)).

-spec handle(request_ride_v1:t(), #ride_state{}) ->
    {ok, [map()]} | {error, term()}.
handle(Cmd, State) ->
    case request_ride_v1:validate(Cmd) of
        ok ->
            case ride_state:is_pristine(State) of
                false -> {error, ride_already_requested};
                true  -> emit(Cmd)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd) ->
    {ok, Ev} = ride_requested_v1:new(#{
        ride_id             => request_ride_v1:get_ride_id(Cmd),
        company_id          => request_ride_v1:get_company_id(Cmd),
        pickup_x            => request_ride_v1:get_pickup_x(Cmd),
        pickup_y            => request_ride_v1:get_pickup_y(Cmd),
        dropoff_x           => request_ride_v1:get_dropoff_x(Cmd),
        dropoff_y           => request_ride_v1:get_dropoff_y(Cmd),
        party_size          => request_ride_v1:get_party_size(Cmd),
        fare_estimate_cents => request_ride_v1:get_fare_estimate_cents(Cmd),
        requested_at        => coalesce(request_ride_v1:get_requested_at(Cmd),
                                        iso8601_now())
    }),
    {ok, [ride_requested_v1:to_map(Ev)]}.

-spec dispatch(request_ride_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case request_ride_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    RideId = request_ride_v1:get_ride_id(Cmd),
    EvoqCmd = evoq_command:new(
        request_ride, ride_aggregate, ride_aggregate:stream_id(RideId),
        request_ride_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id    => hecate_parksim_service:store_id(),
             adapter     => reckon_evoq_adapter,
             consistency => eventual},
    evoq_dispatcher:dispatch(EvoqCmd, Opts).

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
