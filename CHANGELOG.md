# Changelog

All notable changes to **hecate-parksim-simulator** are documented here.

## [Unreleased]

## [0.4.4] - 2026-07-03

### Changed

- Rebuild against **reckon_db 5.5.5**, which cures the store-cluster
  split-brain on simultaneous cold boot (election over store-runners +
  persistent coordinator reconcile). The fleet now forms clean N-member
  clusters on its own; the external `converge-parksim.sh` becomes a
  belt-and-suspenders repair rather than a requirement.

### Added

- **Distinct vehicle-service facts.** Split the parameterized
  `vehicle_serviced_v1{kind}` into first-class events: `battery_charged_v1`
  (new `charge_battery` slice), `vehicle_cleaned_v1` (`clean_vehicle`), and
  `vehicle_maintained_v1` (`maintain_vehicle`); retired `service_vehicle` /
  `vehicle_serviced`. The simulator now emits an event for every serviced
  kind in a visit (queued kinds were previously silent).

### Fixed

- Parking DCB occupancy: `vehicle_exited_lot` now carries `lot_id` (was
  asymmetric with `vehicle_entered_lot`); fixed orphan exits (conditional
  entry vs. unconditional exit under contention with a fail-open caller now
  only proceeds on a successful claim); widened the truncated per-plate
  state read.

## [0.3.0] - 2026-06-24

### Added

- **Payload enrichment (Options A–D)**

  *Option A — Parking session denormalization.* `vehicle_docked_v1`,
  `vehicle_undocked_v1`, `payment_captured_v1`, and
  `parking_session_archived_v1` now carry `plate` and `lot_id` so
  every tail event is self-contained without replaying back to
  `session_initiated_v1`. `payment_captured_v1` additionally carries
  `payment_method` (`"card"` or `"permit"` derived from the aggregate
  state). `parking_session_archived_v1` carries `duration_s` (seconds
  from entry to archive).

  *Option B — ride\_id threading.* `vehicle_dispatched_v1`,
  `passenger_picked_up_v1`, `passenger_dropped_off_v1`, and
  `fare_collected_v1` now carry the `ride_id` of the active ride.
  `ride_started_v1` and `ride_completed_v1` carry `vehicle_id`.
  `vehicle_state` tracks `ride_id` and propagates it through the
  dispatch → pickup → dropoff lifecycle.

  *Option C — company\_id on all vehicle lifecycle events.*
  `vehicle_dispatched_v1`, `passenger_picked_up_v1`,
  `passenger_dropped_off_v1`, `fare_collected_v1`,
  `vehicle_returning_v1`, `vehicle_docked_at_facility_v1`,
  `vehicle_serviced_v1`, `vehicle_released_v1`, and
  `battery_depleted_v1` now carry `company_id` (the operator identity
  set at commissioning, read from aggregate state at emit time).

  *Option D — Bay uniqueness via DCB.* New `vehicle_bay_dcb` module
  enforces the invariant that two vehicles cannot claim the same
  facility bay simultaneously. `maybe_dock_at_facility` calls
  `vehicle_bay_dcb:claim_bay/4` before emitting; `maybe_release_vehicle`
  calls `vehicle_bay_dcb:release_bay/3` after the vehicle departs.
  Uses `append_if_no_tag_matches` with tag `bay:<facility_id>:<bay_id>`.

- **Store indexes.** `hecate_parksim_service:ensure_store/0` now
  declares `[tags, event_type]` indexes on the reckon-db store, making
  tag-based DCB reads (used by both `parking_session_dcb` and
  `vehicle_bay_dcb`) index-backed rather than full-scan.

### Changed

- `simulate_fleet_core`: `dispatch_vehicle`, `pick_up_passenger`,
  `drop_off_passenger`, `return_vehicle`, `dock_at_facility`,
  `service_vehicle`, `release_vehicle`, and `deplete_battery` effects
  now include `company_id` and/or `ride_id` in their payloads so the
  command handlers can propagate them without needing aggregate state
  lookups.

## [0.2.0] - 2026-05-31

### Changed

- **Robotaxi / ClankerCab reframe** (170e0f3). Reframed the simulator as a
  federated autonomous-cab fleet: `guide_vehicle_lifecycle`, `project_fleet`,
  `query_fleet`, `simulate_fleet` emitting per-operator
  `fleet/<tenant>/{summary,telemetry}` facts on the `io.macula` mesh — the
  source the realm-side ClankerCab LiveView consumes. (Parking-session apps
  retained alongside.)
- **Physical-device-first rebuild** (PLAN_PARKSIM_LANE_EQUIPMENT.md §7).
  The simulator now emulates the lane *hardware* instead of firing
  logical session commands. Retired the `simulate_sessions` app;
  added `simulate_visit` (the per-visit walk) with three device-stimulus
  emitters: `simulate_entry_island`, `simulate_payment_terminal`,
  `simulate_exit_island`. A visit carries a physical credential
  (minted `card_id` for ticket visits, or a `permit_ref` for permit
  visits) threaded through every device call.
- `simulate_arrivals` now decides ticket vs permit per arrival from the
  lot's `permit_share` and starts a `simulate_visit`.
- `simulate_lots` `open_lot` now declares the lot's lane-equipment
  inventory inline (one entry island, one exit island, one terminal) so
  the equipment divisions' commission PMs fan out.
- Added entry-island / exit-island / payment-terminal capability
  constants.

## [0.1.0] - 2026-05-19

### Added

- Initial scaffold. Replaces the retired Go driver
  (`hecate-parksim-driver`) with an Erlang sibling that speaks the
  same wire (mesh) as everything else in the family.
- Umbrella with five sub-apps: `parksim_simulator` (mesh wrapper +
  capability constants + scenario presets + plate pool),
  `simulate_clock`, `simulate_arrivals`, `simulate_sessions`,
  `simulate_lots`, `simulate_pricing`.
- Cowboy admin surface (`/health`, `/api/run`, `/api/event`,
  `/api/evacuate`) on port 8473.
- `dry_run` mode logs mesh calls instead of dispatching — default
  true so the simulator works against an empty mesh.
- Three preset shapes (`demo` / `city` / `stress`) per
  `PLAN_PARKSIM_TRAFFIC_MODEL.md` §1.
- NHPP arrivals via Lewis–Shedler thinning; lognormal dwell;
  categorical payment outcomes matching §4.1; weekly maintenance
  windows, daily sensor calibrations, 2-hourly sweeps; optional
  evacuation drill at sim-hour 4.
