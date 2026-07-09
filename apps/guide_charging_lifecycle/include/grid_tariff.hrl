%%% @doc Shared grid-tariff constants for the charging domain. The producer
%%% (`simulate_grid_prices') drives the curve; the process manager
%%% (`on_grid_price_changed_schedule_charging') uses the defer threshold; the
%%% settle handler uses the off-peak threshold + capacity. One source of truth so
%%% producer, scheduler and ledger agree on what "off-peak" and "expensive" mean.
-ifndef(GRID_TARIFF_HRL).
-define(GRID_TARIFF_HRL, true).

%% Regional grid price band (cents per kWh), by sim-clock window.
-define(PEAK_CENTS_PER_KWH,     38).   %% daytime / evening demand peak
-define(SHOULDER_CENTS_PER_KWH, 26).   %% morning / late-evening shoulder
-define(OFFPEAK_CENTS_PER_KWH,  16).   %% overnight trough

%% A session priced at or below this counts as charged in an off-peak window.
-define(OFF_PEAK_MAX_CENTS, 22).

%% The scheduler defers a non-critical charge when the price is above this and
%% the battery is not yet critically low (see the process manager).
-define(CHARGE_DEFER_ABOVE_CENTS, 30).

%% A usable pack is ~60 kWh (mirrors the legacy charge cost model).
-define(BATTERY_CAPACITY_KWH, 60).

-endif.
