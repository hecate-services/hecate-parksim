%%% @doc Ride aggregate state record.
-ifndef(RIDE_STATE_HRL).
-define(RIDE_STATE_HRL, true).

-record(ride_state, {
    ride_id             :: binary() | undefined,
    company_id          :: binary() | undefined,   %% operator whose queue it's in
    status_flags = 0    :: non_neg_integer(),
    pickup_x            :: number() | undefined,
    pickup_y            :: number() | undefined,
    dropoff_x           :: number() | undefined,
    dropoff_y           :: number() | undefined,
    party_size          :: pos_integer() | undefined,
    fare_estimate_cents :: non_neg_integer() | undefined,
    fare_cents          :: non_neg_integer() | undefined,  %% final, at completion
    vehicle_id          :: binary() | undefined,   %% assigned cab
    requested_at        :: binary() | undefined,
    last_event_at       :: binary() | undefined
}).

-endif.
