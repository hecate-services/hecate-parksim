%%% @doc QRY desks over the parking_sessions read model. Pure reads;
%%% all computation already happened in the projection.
-module(query_parking_sessions).

-export([overview/0, session/1, recent/1]).

%% @doc Aggregate overview — counts, revenue, by-lot. Milliseconds,
%% straight from the indexed SQLite read model (no event-store scan).
-spec overview() -> {ok, map()} | {error, term()}.
overview() -> project_parking_sessions_store:overview().

-spec session(binary()) -> {ok, map()} | {error, not_found | term()}.
session(Id) when is_binary(Id) -> project_parking_sessions_store:get(Id);
session(_) -> {error, missing_id}.

-spec recent(pos_integer()) -> {ok, [map()]} | {error, term()}.
recent(Limit) when is_integer(Limit), Limit > 0 ->
    project_parking_sessions_store:recent(Limit);
recent(_) -> {error, invalid_limit}.
