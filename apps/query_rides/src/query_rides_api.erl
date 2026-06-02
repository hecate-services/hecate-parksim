%%% @doc HTTP API for the rides read model (cowboy handler, JSON).
%%%
%%% Routes (see query_rides_app for dispatch):
%%%   GET /api/rides/overview   — rollup (waiting/active/completed/expired,
%%%                               completion rate, fares)
%%%   GET /api/rides            — every ride's current status + endpoints
%%%   GET /api/rides/companies  — per-operator completed/expired/fares
%%%   GET /api/rides/recent     — recent rides
%%%   GET /health               — liveness
-module(query_rides_api).

-export([init/2]).

init(Req0, overview = State) ->
    reply_json(Req0, 200, query_rides:overview(), State);
init(Req0, rides = State) ->
    reply_json(Req0, 200, query_rides:rides(), State);
init(Req0, companies = State) ->
    reply_json(Req0, 200, query_rides:by_company(), State);
init(Req0, recent = State) ->
    reply_json(Req0, 200, query_rides:recent(limit_param(Req0)), State);
init(Req0, health = State) ->
    reply_json(Req0, 200, #{status => <<"ok">>}, State).

%%--------------------------------------------------------------------

reply_json(Req0, Code, Body, State) ->
    Req = cowboy_req:reply(Code,
        #{<<"content-type">> => <<"application/json">>},
        jsx:encode(jsonable(Body)), Req0),
    {ok, Req, State}.

limit_param(Req) ->
    #{limit := L} = cowboy_req:match_qs([{limit, [], <<"50">>}], Req),
    binary_to_integer(L).

jsonable(M) when is_map(M)  -> maps:map(fun(_, V) -> jsonable(V) end, M);
jsonable(L) when is_list(L) -> [jsonable(X) || X <- L];
jsonable(V) -> V.
