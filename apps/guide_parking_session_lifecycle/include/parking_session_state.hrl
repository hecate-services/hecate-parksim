%%% @doc Parking session aggregate state record.
%%%
%%% Owned by parking_session_state. Used by parking_session_aggregate
%%% and the slice handlers (`maybe_*`) when state-dependent validation
%%% is needed.

-record(parking_session_state, {
    session_id   :: binary() | undefined,
    lot_id       :: binary() | undefined,    %% free-form tag, not enforced
    status_flags = 0 :: non_neg_integer(),
    plate        :: binary() | undefined,
    card_id      :: binary() | undefined,    %% ticket visits — minted card
    permit_ref   :: binary() | undefined,    %% permit visits — covers the whole visit
    entered_at   :: binary() | undefined,
    bay_id       :: binary() | undefined,
    docked_at    :: binary() | undefined,
    undocked_at  :: binary() | undefined,
    paid_at      :: binary() | undefined,
    fee_cents :: non_neg_integer() | undefined,
    archived_at  :: binary() | undefined,
    archive_reason :: binary() | undefined
}).
