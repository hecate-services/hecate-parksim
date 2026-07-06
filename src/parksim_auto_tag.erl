%%% @doc evoq dispatch middleware: promote business-identity payload fields to
%%% cross-stream tags so every domain event is queryable by the entity it
%%% concerns (plate, vehicle, ride, ...).
%%%
%%% Background: reckon_db's `{payload, Key}` index is DCB-only, so aggregate
%%% domain events (which carry these identifiers in their payload) are NOT
%%% payload-indexed. But the base `tags` index IS maintained on every append.
%%% evoq attaches command-metadata `tags` to each emitted event
%%% (evoq_aggregate:with_tags/2), which reckon_evoq writes and reckon_db
%%% indexes. So tagging here makes `by-tags plate:1-ZZZ-829` (or `vehicle:...`,
%%% `ride:...`) return an entity's full cross-stream history — the queryability
%%% that plumbing plate into payloads alone did not provide.
%%%
%%% Registered globally via `application:set_env(evoq, middleware, [?MODULE])`
%%% (see hecate_parksim_app), so it applies to every command with no per-desk
%%% wiring. Additive and fail-safe: it only ever ADDS tags, never halts.
-module(parksim_auto_tag).
-behaviour(evoq_middleware).

-include_lib("evoq/include/evoq.hrl").

-export([before_dispatch/1]).

-ifdef(TEST).
-export([derive_tags/1]).
-endif.

%% Payload field -> tag prefix. A field present in a command's payload becomes
%% a `<<"prefix:value">>' tag on every event that command emits.
-define(TAG_KEYS, [{plate,       <<"plate">>},
                   {vehicle_id,  <<"vehicle">>},
                   {company_id,  <<"company">>},
                   {ride_id,     <<"ride">>},
                   {trip_id,     <<"trip">>},
                   {session_id,  <<"session">>},
                   {lot_id,      <<"lot">>},
                   {facility_id, <<"facility">>},
                   {bay_id,      <<"bay">>}]).

-spec before_dispatch(#evoq_pipeline{}) -> #evoq_pipeline{}.
before_dispatch(#evoq_pipeline{command = Cmd} = Pipeline) ->
    case derive_tags(Cmd#evoq_command.payload) of
        []   -> Pipeline;
        Tags -> Pipeline#evoq_pipeline{command = add_tags(Cmd, Tags)}
    end.

%% @private Merge the derived tags into the command metadata's `tags' list,
%% preserving any already set (e.g. by a desk that tags explicitly).
add_tags(#evoq_command{metadata = Meta} = Cmd, Tags) ->
    Existing = maps:get(tags, Meta, []),
    Cmd#evoq_command{metadata = Meta#{tags => lists:usort(Existing ++ Tags)}}.

-spec derive_tags(map()) -> [binary()].
derive_tags(Payload) ->
    lists:filtermap(
        fun({Key, Prefix}) ->
            case maps:get(Key, Payload, undefined) of
                undefined -> false;
                V ->
                    case to_bin(V) of
                        undefined -> false;
                        Bin       -> {true, <<Prefix/binary, ":", Bin/binary>>}
                    end
            end
        end, ?TAG_KEYS).

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_atom(V), V =/= undefined -> atom_to_binary(V, utf8);
to_bin(V) when is_list(V) -> case io_lib:printable_unicode_list(V) of
                                 true  -> unicode:characters_to_binary(V);
                                 false -> undefined
                             end;
to_bin(_) -> undefined.
