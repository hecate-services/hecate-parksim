%%% @doc Records for the robotaxi fleet simulator.
%%%
%%% A service facility (depot) where vehicles charge / clean / maintain.
-record(facility, {
    id    :: binary(),
    name  :: binary(),
    x   :: number(),
    y   :: number(),
    bays  :: pos_integer(),
    kinds :: [binary()]          %% subset of [<<"charge">>,<<"clean">>,<<"maintain">>]
}).

%%% One robotaxi operator (= one beam node = one mesh publisher). `id' is the
%%% TENANT_ID, kept as the store/stream/topic key; name + color are display.
-record(operator, {
    id         :: binary(),
    name       :: binary(),
    color      :: binary(),
    home       :: binary(),      %% home facility id
    fleet_size :: pos_integer()
}).

%%% A pending ride (in its "requested" state) the fleet brain may assign to an
%%% idle vehicle. A ride is a transaction: source, destination, party, fare.
-record(ride_request, {
    id                  :: binary(),
    pickup              :: {number(), number()},   %% {X, Y}
    dropoff             :: {number(), number()},
    party_size = 1      :: pos_integer(),
    fare_estimate_cents = 0 :: non_neg_integer(),
    created             :: integer()                %% sim unix seconds
}).

%%% In-memory kinematic state of one vehicle in the fleet brain. This is the
%%% high-frequency state the sim owns; only sparse MILESTONES become domain
%%% events. `phase' mirrors the aggregate's exclusive phase. `path' is the
%%% remaining road polyline ahead of the vehicle; `leg' says what milestone
%%% fires when the path is exhausted.
-record(fveh, {
    id          :: binary(),
    plate       :: binary(),     %% registered licence plate (robotaxis have
                                 %% plates too — the real-world vehicle identity)
    vin         :: binary(),     %% vehicle identification number (asset identity,
                                 %% issued once at commission — never changes)
    soh_pct = 100.0 :: number(), %% battery State-of-Health: capacity health, only
                                 %% decreases; a robotaxi's asset value tracks this
    charge_cycles = 0 :: non_neg_integer(), %% full charges — degrades SoH
    phase       :: atom(),       %% commissioned|cruising|dispatched|on_trip
                                 %% |returning|docked|servicing|depleted
    x         :: number(),
    y         :: number(),
    heading     :: number(),     %% degrees, for telemetry
    battery_pct :: number(),

    path = []   :: [{number(), number()}],   %% remaining {X,Y} waypoints
    leg  = none :: none | to_pickup | to_dropoff | to_facility,

    trip_id      :: binary() | undefined,
    ride_id      :: binary() | undefined,   %% the ride aggregate id being served
    pickup       :: {number(), number()} | undefined,
    dropoff      :: {number(), number()} | undefined,
    trip_m = 0.0 :: float(),     %% metres driven on the current trip (for fare)

    cleanliness_pct = 100.0 :: number(),   %% drops per trip; clean resets to 100
    km_since_maint  = 0.0   :: number(),   %% accrues per km; maintain resets to 0
    service_queue   = []    :: [binary()], %% remaining service kinds this visit

    dest_facility :: binary() | undefined,
    dest_bay      :: binary() | undefined,
    service_kind  :: binary() | undefined,
    service_until :: integer() | undefined,  %% sim unix when service completes
    tow_until     :: integer() | undefined,  %% sim unix when a stranded tow lands
    tow_truck_id  :: binary() | undefined,   %% assigned rescue truck
    tow_dispatched = false :: boolean()      %% has the truck been dispatched yet
}).
