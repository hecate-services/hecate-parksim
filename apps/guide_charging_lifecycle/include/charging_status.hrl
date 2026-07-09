%%% @doc Charging status bit flags. The charging session moves through exactly
%%% one lifecycle PHASE at a time (`set_phase/2' clears all phase bits and sets
%%% one); `ENERGY_SETTLED' is an additive flag stamped on the settled session
%%% after completion (it does not change the phase).
-ifndef(CHARGING_STATUS_HRL).
-define(CHARGING_STATUS_HRL, true).

-define(CHARGE_REQUESTED, 1).   %% 2^0 — SoC below threshold, charge asked for
-define(CHARGING,         2).   %% 2^1 — plugged in, SoC climbing (progress*)
-define(CHARGE_COMPLETED, 4).   %% 2^2 — target reached / unplugged
-define(ENERGY_SETTLED,   8).   %% 2^3 — kWh x tariff booked to the ledger

-define(CHARGE_ALL_PHASES,
        [?CHARGE_REQUESTED, ?CHARGING, ?CHARGE_COMPLETED]).

-endif.
