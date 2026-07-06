%%% @doc Handler for `cancel_ride_v1`. A ride that is ASSIGNED or STARTED can be
%%% cancelled (an unassigned ride expires instead; a completed one cannot). Emits
%%% `ride_cancelled_v1', carrying the assigned cab's identity from state.
-module(maybe_cancel_ride).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

handle(Cmd) -> handle(Cmd, ride_state:new(<<>>)).

handle(Cmd, State) ->
    case cancel_ride_v1:validate(Cmd) of
        ok ->
            case ride_state:is_assigned(State) orelse ride_state:is_started(State) of
                false -> {error, ride_not_cancellable};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = ride_cancelled_v1:new(#{
        ride_id     => cancel_ride_v1:get_ride_id(Cmd),
        company_id  => ride_state:company_id(State),
        vehicle_id  => ride_state:vehicle_id(State),
        plate       => ride_state:plate(State),
        reason      => cancel_ride_v1:get_reason(Cmd),
        cancellation_fee_cents => cancel_ride_v1:get_cancellation_fee_cents(Cmd),
        cancelled_at => coalesce(cancel_ride_v1:get_cancelled_at(Cmd), iso8601_now())
    }),
    {ok, [ride_cancelled_v1:to_map(Ev)]}.

dispatch(#{} = Data) ->
    case cancel_ride_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    RideId = cancel_ride_v1:get_ride_id(Cmd),
    EvoqCmd = evoq_command:new(
        cancel_ride, ride_aggregate, ride_aggregate:stream_id(RideId),
        cancel_ride_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}),
    Opts = #{store_id => hecate_parksim_service:store_id(),
             adapter => reckon_evoq_adapter, consistency => eventual},
    evoq_command_router:dispatch(EvoqCmd, Opts).

coalesce(undefined, D) -> D; coalesce(V, _) -> V.
iso8601_now() ->
    {{Y,Mo,D},{H,Mi,S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                   [Y,Mo,D,H,Mi,S])).
