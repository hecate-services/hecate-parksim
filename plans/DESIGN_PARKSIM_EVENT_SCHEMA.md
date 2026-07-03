# DESIGN: Parksim event schema (screaming payloads)

Status: Draft for review (2026-07-03)
Related: DESIGN_PARKSIM_ENTITY_MODEL.md

A deliberate naming + richness pass over every event payload in every domain.
Two goals: every field **screams its business purpose** (no generic
`amount_cents`/`distance_m`), and every event is a **complete, self-contained
fact** (identity + cross-refs + physical snapshot + metrics + money), so the
event stream reads as a rich story and the CCC/payload queries are powerful.

## Principles

1. **Name the purpose, not the type.** `fee_cents` / `fare_cents` beat
   `amount_cents`; `trip_distance_m` beats `distance_m`; `charging_cents`
   beats `cost_cents`. The field says *what it is in the business*, not just
   its unit.
2. **Money is never generic.** Split by purpose AND by direction
   (revenue vs cost), so profit is queryable.
3. **Physical snapshot on every fleet event.** `x`, `y`, `battery_pct` at the
   moment of the event: maps the whole lifecycle and gives a battery
   time-series for free (the sim already holds them).
4. **Self-contained.** Each event carries the ids a consumer needs
   (`vehicle_id`/`company_id`, `ride_id`/`trip_id`, `session_id`/`plate`/
   `lot_id`/`bay_id`) so no replay or join is required.
5. **Symmetry.** A "leave" event carries the same location/identity its
   matching "enter" event did (bay_id on undock/release, lot_id on exit).

## Money vocabulary (banish `amount_cents`)

| Direction | Field | Meaning |
|---|---|---|
| Revenue | `fare_cents` | ride fare (actual) |
| Revenue | `fare_estimate_cents` | ride fare (quoted at request) |
| Revenue | `tip_cents` | passenger tip on a completed ride |
| Revenue | `fee_cents` | parking fee |
| Cost | `charging_cents` | energy cost of a charge (gerund avoids "a charge" = a fee) |
| Cost | `cleaning_cents` | cost of a clean |
| Cost | `maintenance_cents` | cost of scheduled maintenance |
| Cost | `tow_cents` | cost of towing a stranded vehicle |

Profit per vehicle/operator = sum(revenue fields) - sum(cost fields), all
queryable from the stream.

## Fleet vehicle lifecycle

Every event also carries `vehicle_id`, `company_id`, `x`, `y`, `battery_pct`,
and its `<verb>_at` timestamp. Only the distinctive fields are listed; **[+]**
marks new/changed vs today.

| Event | Distinctive payload |
|---|---|
| `vehicle_commissioned` | `model` [+], `home_facility_id` [+], `plate` [+] |
| `vehicle_dispatched` | `ride_id`, `trip_id`, `pickup_x/y`, `dropoff_x/y`, `pickup_distance_m` [+] |
| `passenger_picked_up` | `ride_id`, `trip_id` [+], `wait_s` [+] |
| `passenger_dropped_off` | `ride_id`, `trip_id` [+], `trip_distance_m` [+], `trip_duration_s` [+] |
| `fare_collected` | `ride_id`, `trip_id`, `fare_cents` [+rename], `tip_cents` [+], `surge_multiplier` [+], `payment_method` [+] |
| `vehicle_returning` | `x`/`y` [+], `destination_facility_id` [+rename], `return_reason` [+] (charge\|clean\|maintain\|shift_end) |
| `vehicle_docked_at_facility` | `facility_id`, `bay_id` |
| `battery_charged` | `battery_pct_before` [+], `energy_kwh` [+], `charging_cents` [+], `charge_duration_s` [+] |
| `vehicle_cleaned` | `cleaning_cents` [+], `clean_duration_s` [+] |
| `vehicle_maintained` | `maintenance_cents` [+], `maintenance_duration_s` [+], `km_since_last_maint` [+] |
| `vehicle_released` | `facility_id` [+], `bay_id` [+], `time_at_facility_s` [+] |
| `battery_depleted` | (stranded; x/y = where) |
| `vehicle_towed` **[+ new event]** | `from_x/y`, `destination_facility_id`, `tow_distance_m`, `tow_cents` |

## Rides

Every ride event carries `ride_id`, `company_id`, `<verb>_at`.

| Event | Distinctive payload |
|---|---|
| `ride_requested` | `pickup_x/y`, `dropoff_x/y`, `party_size`, `fare_estimate_cents`, `trip_estimate_m` [+], `requested_via` [+] (app\|street_hail) |
| `ride_assigned` | `company_id` [+], `vehicle_id`, `wait_estimate_s` [+] |
| `ride_started` | `company_id` [+], `vehicle_id` |
| `ride_completed` | `company_id` [+], `vehicle_id`, `fare_cents`, `tip_cents` [+], `trip_distance_m` [+], `trip_duration_s` [+], `rating` [+] (1..5) |
| `ride_expired` | `company_id` [+], `waited_s` [+] |

## Parking

Every parking event carries `session_id`, `plate`, `lot_id`, `<verb>_at`.

| Event | Distinctive payload |
|---|---|
| `parking_session_initiated` | `card_id`, `permit_ref`, `zone` [+], `vehicle_class` [+] (car\|van\|ev) |
| `vehicle_docked` | `bay_id` |
| `vehicle_undocked` | `bay_id` [+], `occupancy_s` [+] |
| `payment_captured` | `fee_cents` [+rename], `payment_method` (card\|permit), `tariff` [+] |
| `parking_session_archived` | `fee_cents`, `duration_s`, `reason` (permit\|paid\|abandoned) |
| `vehicle_entered_lot` (DCB) | `plate`, `lot_id`, `session_id` |
| `vehicle_exited_lot` (DCB) | `plate`, `lot_id`, `session_id` |

## New events / slices needed

- `vehicle_towed_v1` (fleet): a stranded (depleted) vehicle is rescued to a
  facility. New slice: `tow_vehicle` command + `vehicle_towed_v1` event +
  handler, driven by the sim's existing tow timer. Carries `tow_cents`.

## Indexes (CCC payload indexes) for a query-rich demo

Declare payload indexes so the gateway's Payload/Hash queries trace an entity
or aggregate by dimension without scanning:

| Index | Query it unlocks |
|---|---|
| `{payload, vehicle_id}` | trace one cab's whole life |
| `{payload, ride_id}` | trace one ride end to end |
| `{payload, company_id}` | everything for one operator (revenue/cost roll-ups) |
| `{payload, lot_id}` | all activity in one lot |
| `{payload, session_id}` | one parking session |
| `{payload, plate}` | a plate's parking history (already DCB-tagged) |
| `{payload_hash, [lot_id, payment_method]}` | composite: e.g. permit vs paid per lot |
| `{payload_hash, [company_id, return_reason]}` | why cabs go off-service, per operator |

## Data sources (all cheap)

Everything is already in sim state or trivially derived:
- `x`, `y`, `battery_pct`, `trip_m`, `trip_id`, `ride_id`: the `fveh` record.
- costs: from the battery delta (`charging_cents`, `energy_kwh`), service
  durations (`cleaning_cents`, `maintenance_cents`), tow distance (`tow_cents`).
- `tip_cents`: a jittered fraction of `fare_cents`.
- `surge_multiplier`, `rating`, `requested_via`, `vehicle_class`, `zone`,
  `model`: sim picks from small distributions.
- `wait_s`/`waited_s`, durations: request time vs milestone time.

## Implementation order

1. Lock this vocabulary (this doc).
2. Money rename + cost fields (fee/fare/charging/cleaning/maintenance/tow/tip)
   + the audit fixes (bay/facility ids on leave events, company_id on rides).
3. Physical snapshot (x/y/battery_pct) across fleet events.
4. Metrics + categoricals (distances, durations, ratings, surge, classes).
5. `vehicle_towed` slice.
6. Payload index declarations.
7. Projections/read models + tests updated per batch.
