%%% @doc Ride status bit flags. A ride is always in exactly one lifecycle
%%% phase; `set_phase/2' clears all phase bits and sets one.
-ifndef(RIDE_STATUS_HRL).
-define(RIDE_STATUS_HRL, true).

-define(RIDE_REQUESTED, 1).    %% 2^0 — a rider is waiting, no cab yet
-define(RIDE_ASSIGNED,  2).    %% 2^1 — a cab is on its way to the pickup
-define(RIDE_STARTED,   4).    %% 2^2 — passenger aboard, en route to dropoff
-define(RIDE_COMPLETED, 8).    %% 2^3 — dropped off, fare collected
-define(RIDE_EXPIRED,  16).    %% 2^4 — rider gave up before a cab arrived
-define(RIDE_CANCELLED, 32).   %% 2^5 — cancelled after assignment (rider/operator)

-define(RIDE_ALL_PHASES,
        [?RIDE_REQUESTED, ?RIDE_ASSIGNED, ?RIDE_STARTED,
         ?RIDE_COMPLETED, ?RIDE_EXPIRED, ?RIDE_CANCELLED]).

-endif.
