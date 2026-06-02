%%% @doc Query facade for the rides read model.
%%%
%%% Thin pass-through to the projection store (QRY reads the same SQLite the
%%% PRJ side writes). A separate module gives a stable query API independent
%%% of storage details.
-module(query_rides).

-export([overview/0, rides/0, by_company/0, recent/1]).

overview()    -> project_rides_store:overview().
rides()       -> project_rides_store:rides().
by_company()  -> project_rides_store:by_company().
recent(Limit) -> project_rides_store:recent(Limit).
