%%% @doc Charging-session aggregate state record.
-ifndef(CHARGING_STATE_HRL).
-define(CHARGING_STATE_HRL, true).

-record(charging_state, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,   %% operator paying for energy
    plate                :: binary() | undefined,
    status_flags = 0     :: non_neg_integer(),
    charger_id           :: binary() | undefined,   %% bay/charger serving the session
    battery_pct_before   :: number() | undefined,
    battery_pct          :: number() | undefined,   %% latest SoC (progress/complete)
    target_pct           :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,    %% stamped at start (grid price)
    energy_kwh = 0.0     :: number(),                %% accumulated over progress
    cost_cents           :: non_neg_integer() | undefined,  %% at settle
    off_peak             :: boolean() | undefined,   %% tariff window at settle
    requested_at         :: binary() | undefined,
    started_at           :: binary() | undefined,
    completed_at         :: binary() | undefined,
    settled_at           :: binary() | undefined,
    last_event_at        :: binary() | undefined
}).

-endif.
