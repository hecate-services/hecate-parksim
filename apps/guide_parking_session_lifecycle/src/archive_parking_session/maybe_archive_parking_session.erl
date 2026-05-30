%%% @doc Handler for `archive_parking_session_v1`.
%%%
%%% Requires session SETTLED (paid, or covered by a permit) and not yet
%%% ARCHIVED. Echoes `fee_cents` from
%%% the state's `amount_cents` (recorded at payment) — the event
%%% payload is a subset of the dossier per DDD.md.
-module(maybe_archive_parking_session).

-include_lib("evoq/include/evoq.hrl").
-include_lib("guide_parking_session_lifecycle/include/parking_session_state.hrl").

-export([handle/1, handle/2, dispatch/1]).

-spec handle(archive_parking_session_v1:t()) ->
    {ok, [parking_session_archived_v1:t()]} | {error, term()}.
handle(Cmd) ->
    handle(Cmd, parking_session_state:new(<<>>)).

-spec handle(archive_parking_session_v1:t(), #parking_session_state{}) ->
    {ok, [parking_session_archived_v1:t()]} | {error, term()}.
handle(Cmd, State) ->
    case archive_parking_session_v1:validate(Cmd) of
        ok               -> check_state(Cmd, State);
        {error, _} = Err -> Err
    end.

check_state(Cmd, State) ->
    case parking_session_state:is_initiated(State) of
        false -> {error, session_not_initiated};
        true ->
            case parking_session_state:is_archived(State) of
                true  -> {error, session_already_archived};
                false ->
                    %% Settled = paid (ticket) OR covered by a permit.
                    case parking_session_state:is_settled(State) of
                        false -> {error, session_not_settled};
                        true  -> emit(Cmd, State)
                    end
            end
    end.

emit(Cmd, State) ->
    {ok, Event} = parking_session_archived_v1:new(#{
        session_id  => parking_session_state:session_id(State),
        fee_cents   => parking_session_state:amount_cents(State),
        archived_at => coalesce(archive_parking_session_v1:get_archived_at(Cmd),
                                iso8601_now()),
        reason      => archive_parking_session_v1:get_reason(Cmd)
    }),
    {ok, [Event]}.

%%--------------------------------------------------------------------
%% Dispatch wrapper

-spec dispatch(archive_parking_session_v1:t() | map()) ->
    {ok, non_neg_integer(), [map()]} | {error, term()}.
dispatch(#{} = Data) ->
    case archive_parking_session_v1:from_map(Data) of
        {ok, Cmd}      -> dispatch(Cmd);
        {error, _} = E -> E
    end;
dispatch(Cmd) ->
    SessionId = archive_parking_session_v1:get_session_id(Cmd),
    EvoqCmd = evoq_command:new(
        archive_parking_session,
        parking_session_aggregate,
        SessionId,
        archive_parking_session_v1:to_map(Cmd),
        #{timestamp => erlang:system_time(millisecond)}
    ),
    Opts = #{
        store_id    => hecate_parksim_service:store_id(),
        adapter     => reckon_evoq_adapter,
        consistency => strong
    },
    evoq_dispatcher:dispatch(EvoqCmd, Opts).

%%--------------------------------------------------------------------
%% Helpers

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
        [Y, Mo, D, H, Mi, S])).
