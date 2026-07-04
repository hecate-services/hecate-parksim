%%% @doc Vehicle (robotaxi) aggregate state record.
%%%
%%% Owned by vehicle_state. Used by vehicle_aggregate and the slice
%%% handlers (`maybe_*`) for state-dependent validation.
%%%
%%% Position fields hold the vehicle's location AT THE LAST MILESTONE
%%% EVENT only — high-frequency movement is telemetry (in-memory in the
%%% fleet sim, streamed as a mesh fact), never event-sourced. battery_pct
%%% is likewise the value recorded at the last event, not live.

-record(vehicle_state, {
    vehicle_id   :: binary() | undefined,
    plate        :: binary() | undefined,    %% registered licence plate
    company_id   :: binary() | undefined,    %% operator/tenant (= TENANT_ID)
    status_flags = 0 :: non_neg_integer(),   %% exactly one phase bit (state machine)

    battery_pct  :: number() | undefined,    %% 0..100, value at last event

    %% Position at last milestone (telemetry carries live position elsewhere).
    x          :: number() | undefined,
    y          :: number() | undefined,

    %% Current trip (set on dispatch, cleared on drop-off).
    ride_id      :: binary() | undefined,
    trip_id      :: binary() | undefined,
    pickup_x   :: number() | undefined,
    pickup_y   :: number() | undefined,
    dropoff_x  :: number() | undefined,
    dropoff_y  :: number() | undefined,

    %% Facility / bay occupancy (set on dock, cleared on release).
    facility_id  :: binary() | undefined,
    bay_id       :: binary() | undefined,
    service_kind :: binary() | undefined,    %% charge | clean | maintain

    %% Lifetime tallies (audit; read models do the real aggregation).
    trips_completed = 0 :: non_neg_integer(),
    fares_cents     = 0 :: non_neg_integer(),

    commissioned_at :: binary() | undefined,
    last_event_at   :: binary() | undefined
}).
