%%% @doc Handler for `issue_refund_v1`. Only a COMPLETED ride can be refunded.
%%% Emits `refund_issued_v1' (a financial adjustment; the ride stays completed).
-module(maybe_issue_refund).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_ride_lifecycle/include/ride_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

handle(Cmd) -> handle(Cmd, ride_state:new(<<>>)).

handle(Cmd, State) ->
    case issue_refund_v1:validate(Cmd) of
        ok ->
            case ride_state:is_completed(State) of
                false -> {error, ride_not_completed};
                true  -> emit(Cmd, State)
            end;
        {error, _} = Err -> Err
    end.

emit(Cmd, State) ->
    {ok, Ev} = refund_issued_v1:new(#{
        ride_id     => issue_refund_v1:get_ride_id(Cmd),
        company_id  => ride_state:company_id(State),
        refund_cents => issue_refund_v1:get_refund_cents(Cmd),
        reason      => issue_refund_v1:get_reason(Cmd),
        refunded_at => coalesce(issue_refund_v1:get_refunded_at(Cmd), iso8601_now())
    }),
    {ok, [refund_issued_v1:to_map(Ev)]}.

dispatch(#{} = Data) ->
    case issue_refund_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    RideId = issue_refund_v1:get_ride_id(Cmd),
    EvoqCmd = evoq_command:new(
        issue_refund, ride_aggregate, ride_aggregate:stream_id(RideId),
        issue_refund_v1:to_map(Cmd),
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
