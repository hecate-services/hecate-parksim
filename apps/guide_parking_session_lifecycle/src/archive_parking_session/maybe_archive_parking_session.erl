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
    ArchivedAt = coalesce(archive_parking_session_v1:get_archived_at(Cmd),
                          iso8601_now()),
    DurationS  = duration_s(parking_session_state:entered_at(State), ArchivedAt),
    {ok, Event} = parking_session_archived_v1:new(#{
        session_id  => parking_session_state:session_id(State),
        fee_cents   => parking_session_state:amount_cents(State),
        plate       => parking_session_state:plate(State),
        lot_id      => parking_session_state:lot_id(State),
        duration_s  => DurationS,
        archived_at => ArchivedAt,
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
        consistency => eventual
    },
    evoq_dispatcher:dispatch(EvoqCmd, Opts).

%%--------------------------------------------------------------------
%% Helpers

-define(UNIX_EPOCH_GREGORIAN, 62167219200).

duration_s(EnteredAt, ArchivedAt) when is_binary(EnteredAt), is_binary(ArchivedAt) ->
    max(0, iso8601_to_unix(ArchivedAt) - iso8601_to_unix(EnteredAt));
duration_s(_, _) -> undefined.

iso8601_to_unix(<<Y:4/binary, "-", Mo:2/binary, "-", D:2/binary, "T",
                  H:2/binary, ":", Mi:2/binary, ":", S:2/binary, _/binary>>) ->
    DT = {{binary_to_integer(Y), binary_to_integer(Mo), binary_to_integer(D)},
          {binary_to_integer(H), binary_to_integer(Mi), binary_to_integer(S)}},
    calendar:datetime_to_gregorian_seconds(DT) - ?UNIX_EPOCH_GREGORIAN;
iso8601_to_unix(_) -> 0.

coalesce(undefined, Default) -> Default;
coalesce(Value, _Default)    -> Value.

iso8601_now() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(
        erlang:system_time(second), second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
        [Y, Mo, D, H, Mi, S])).
