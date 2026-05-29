%%% @doc HTTP surface for the parking_sessions read model. Wired into
%%% hecate-parksim's cowboy listener:
%%%   GET /api/sessions/overview      → counts, revenue, by-lot
%%%   GET /api/sessions/recent[?n=N]  → N most-recent sessions
%%%   GET /api/sessions/:id           → one session
-module(query_parking_sessions_api).

-export([init/2]).

init(Req0, [overview] = State) ->
    reply(query_parking_sessions:overview(), Req0, State);
init(Req0, [recent] = State) ->
    N = parse_int(cowboy_req:match_qs([{n, [], <<"50">>}], Req0)),
    reply(query_parking_sessions:recent(N), Req0, State);
init(Req0, [session] = State) ->
    Id = cowboy_req:binding(id, Req0),
    reply(query_parking_sessions:session(Id), Req0, State).

reply({ok, Data}, Req0, State) ->
    {ok, json(200, Data, Req0), State};
reply({error, not_found}, Req0, State) ->
    {ok, json(404, #{error => <<"not_found">>}, Req0), State};
reply({error, Reason}, Req0, State) ->
    {ok, json(400, #{error => to_bin(Reason)}, Req0), State}.

json(Code, Body, Req) ->
    cowboy_req:reply(Code,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(jsonable(Body)), Req).

%% jsx chokes on `undefined` (SQLite NULLs surface as undefined); map it
%% to null, recursively, across maps and lists.
jsonable(undefined)            -> null;
jsonable(M) when is_map(M)     -> maps:map(fun(_K, V) -> jsonable(V) end, M);
jsonable(L) when is_list(L)    -> [jsonable(E) || E <- L];
jsonable(V)                    -> V.

parse_int(#{n := Bin}) ->
    case string:to_integer(Bin) of
        {N, _} when is_integer(N), N > 0 -> N;
        _                                -> 50
    end.

to_bin(B) when is_binary(B) -> B;
to_bin(A) when is_atom(A)   -> atom_to_binary(A, utf8);
to_bin(T)                   -> iolist_to_binary(io_lib:format("~p", [T])).
