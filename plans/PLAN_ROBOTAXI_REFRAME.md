# Plan: Reframe Parksim as a Robotaxi Fleet Simulator

**Status:** Built + live. Routing/map simplified — see amendment below.
**Date:** 2026-05-30
**Repo:** `codeberg.org/hecate-services/hecate-parksim`

> **Amendment — 2026-05-31: imaginary grid city (OSRM + Leaflet removed).**
> The original "real Leuven streets via per-node OSRM sidecar" approach
> (decisions #5–#7, §6.0/6.2, §6.7/6.8) was **superseded**. The demo city is
> now an imaginary **6×6 checkerboard** (intersections 0..6); routing is a pure
> in-process Manhattan staircase (`route_leg`), with **no OSRM container, no map
> data, no HTTP**. The realm map is **inline SVG** (no Leaflet, no CARTO tiles)
> — which also removed the external-CDN failure mode that froze the map. Net:
> a whole sidecar, a multi-GB graph, and two CDN dependencies deleted; the
> federation story (4 operators, one city, live mesh telemetry) is unchanged.
> Sections below are kept for the historical record; where they say OSRM /
> real roads / Leaflet, read "grid router / SVG". The operator TENANT_IDs
> (`leuven/brussels/ghent/antwerp`) and the mesh station topology are NOT the
> cab city and did NOT change.

---

## 1. The reframe in one sentence

Parksim stops being a passive parking counter (anonymous cars arrive, pay,
leave) and becomes a living **robotaxi fleet simulator**: ~48 self-driving
vehicles, owned by **4 competing operators**, cruising one shared imaginary
**6×6 grid city**, picking up passengers, collecting fares, draining battery,
and docking into facilities to **charge / clean / maintain** — all rendered on
a live map the realm assembles from the 4 operators' mesh feeds.

---

## 2. Locked decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Vehicle is the aggregate** (`guide_vehicle_lifecycle`). Trips are events on the vehicle's stream, not a separate Trip aggregate. | One lifecycle named; no passenger-side bookings to model. Trip-as-aggregate stays a future option. |
| 2 | **4 operators, one city.** Each operator = one beam node = one mesh publisher, owns ~12 vehicles + its depot(s). `company_id` = `TENANT_ID`. | Clean ownership boundary per node; "4 companies share one city" reads as a real market; organic resilience story (node down → that company greys out). |
| 3 | **Fleet ~48 total, 12/company.** | User target ~50, divided cleanly across 4 nodes. |
| 4 | **Position is telemetry, NOT a domain event.** Milestones are events. | 50 vehicles × position/sec would be a write storm into ReckonDB (the CPU-pin shape). Milestones are sparse (~1 event/sec fleet-wide). |
| 5 | ~~OSRM road routing, one container per node~~ → **REVERSED 2026-05-31: imaginary 6×6 grid, in-process Manhattan router.** Cabs drive a `?GRID_N×?GRID_N` checkerboard (intersections 0..6); `route_leg` computes a staircase path with pure arithmetic — no sidecar, no graph, no HTTP. | The OSRM sidecar was a multi-GB graph + a whole container per Celeron beam, and it bought realism the demo doesn't need (the point is mesh federation, not cartography). A grid is self-contained, deterministic, and lighter; it also let the realm map drop Leaflet/CARTO (the CDN that had been freezing the map). |
| 6 | **Demand hotspots** are a handful of named grid intersections (`fleet_config:hotspots/0`) with weights. (Originally floated as GTFS-seeded; not needed for a synthetic grid.) | Robotaxi = on-demand point-to-point; on a grid the origins/destinations are just intersections. |
| 7 | ~~Routing infra first~~ → the sim's kinematics run against the grid router directly; physics (battery/fare per km) unchanged via a metres-per-block scale (`?UNIT_M`). | No infra to stand up first; one block = 150 m keeps the km-based economics sensible. |

---

## 3. Domain–event vs telemetry split (the load-bearing principle)

| Kind | Examples | Storage | Frequency |
|------|----------|---------|-----------|
| **Domain events** (event-sourced) | `vehicle_commissioned`, `vehicle_dispatched`, `passenger_picked_up`, `passenger_dropped_off` + `fare_collected`, `vehicle_returned`, `vehicle_docked`, `vehicle_serviced`, `vehicle_released`, `battery_depleted` | ReckonDB streams (one per vehicle) | sparse (~1/sec fleet-wide) |
| **Telemetry** (NOT events) | lat/lng, heading, battery %, speed, phase | in-memory in the sim; streamed as a **mesh fact** | high (~1–2 s/vehicle) |
| **Integration facts** (mesh) | per-operator fleet summary; per-vehicle telemetry | mesh topics, consumed by realm | summary 5 s; telemetry 1–2 s |

The simulator is the **fleet brain** (kinematics + dispatch policy). The
**aggregate** enforces business rules (no trip under X% battery; no dock
without a free bay) and writes the audit trail. **Projections** build read
models. The **mesh** carries telemetry + summary to the realm. Position
never touches the store.

---

## 4. The vehicle lifecycle

```
commissioned → cruising → dispatched → on-trip → (fare) → cruising …
                  │ (battery low OR service due)
                  ▼
              returning → docked → servicing → released → cruising
                  │ (battery hits 0 first)
                  ▼
              depleted (stranded → rescue/tow → released)
```

**Status bit flags** (per house rule — integers, `evoq_bit_flags`):

```erlang
-define(VEH_COMMISSIONED, 1).    %% 2^0 — joined the fleet
-define(VEH_CRUISING,     2).    %% 2^1 — idle, available, roaming
-define(VEH_DISPATCHED,   4).    %% 2^2 — assigned a fare, heading to pickup
-define(VEH_ON_TRIP,      8).    %% 2^3 — passenger aboard, meter running
-define(VEH_RETURNING,   16).    %% 2^4 — heading to a facility
-define(VEH_DOCKED,      32).    %% 2^5 — occupying a bay
-define(VEH_SERVICING,   64).    %% 2^6 — charge | clean | maintain in progress
-define(VEH_DEPLETED,   128).    %% 2^7 — battery 0, stranded
```

### Desks (vertical slices) in `guide_vehicle_lifecycle`

| Desk | Command → Event |
|------|-----------------|
| `commission_vehicle` | → `vehicle_commissioned_v1` (joins fleet, full battery, at depot) |
| `dispatch_vehicle` | → `vehicle_dispatched_v1` (assigned a fare, heading to pickup) |
| `pick_up_passenger` | → `passenger_picked_up_v1` (trip starts, meter on) |
| `drop_off_passenger` | → `passenger_dropped_off_v1` + `fare_collected_v1` |
| `dock_vehicle` | → `vehicle_docked_v1` (took a bay) |
| `service_vehicle` | → `vehicle_serviced_v1` (`kind`: charge \| clean \| maintain) |
| `release_vehicle` | → `vehicle_released_v1` (bay freed, back to cruising) |
| `deplete_battery` | → `battery_depleted_v1` (stranded — the failure mode) |

Bay occupancy is a **projection** fed by dock/release events (the global
fleet brain allocates bays — no distributed-allocation race). This reuses
the capacity logic already built for parking lots (`lot_in_progress` →
`bays_occupied`).

---

## 5. Migration map — reuse vs rewrite

All **infrastructure stays** (hecate_om mesh client, reckon_db store, evoq
dispatch, CI/deploy, the realm consumer shell). We swap the *domain*.

| Today | Becomes | Reuse |
|-------|---------|-------|
| `guide_parking_session_lifecycle` | `guide_vehicle_lifecycle` | pattern + dock/release verbs |
| `capture_payment` desk | `collect_fare` (→ `drop_off_passenger`) | rename |
| `simulate_arrivals` (NHPP Lewis–Shedler) | `simulate_demand` (ride requests) | **thinning math reused verbatim** |
| `simulate_visit` (per-visit FSM) | per-vehicle FSM inside `simulate_fleet` | logic reused |
| `parksim_simulator_config` (city lots) | `fleet_config` (city geometry + facilities + fleet roster) | restructured |
| `project_parking_sessions` | `project_fleet` | restructured |
| `query_parking_sessions` | `query_fleet` | restructured |
| `emit_city_summary` | `emit_fleet_summary` + `emit_fleet_telemetry` | extended (telemetry is new) |
| `scavenge_aged_sessions` | drop (vehicles are persistent, not aged out) | removed |

**Net-new code:** the in-memory kinematics engine (`simulate_fleet`) + the
telemetry mesh fact. That is the real new work.

---

## 6. Build order

> Routing is in-process, so there is no step-0 infra — the sim runs against
> the grid router directly. (Originally this section opened with an OSRM
> sidecar; that was removed 2026-05-31.)

### 6.0 Routing — in-process grid router (`route_leg`)
- The city is a `?GRID_N×?GRID_N` checkerboard (default 6×6): intersections at
  integer grid coordinates `0..6`, streets along every lattice line. No map
  data, no `.osm.pbf`, no preprocessing, no sidecar container.
- `route_leg:route(From, To)` returns the **Manhattan staircase** of
  intersections between two points (alternating axis so cabs spread across
  interior streets) plus the leg distance in metres. `dist/2` is euclidean
  grid distance × `?UNIT_M` (150 m/block); `interpolate/3` is a linear lerp.
  All pure arithmetic.
- **Sovereign by construction:** no map data, no external service, no API keys
  — strictly more "We are Europe" than the OSRM/OSM route ever was.
- **Demand hotspots:** named grid intersections with weights
  (`fleet_config:hotspots/0`).

### 6.1 Domain — `guide_vehicle_lifecycle`
- 8 desks (§4), each: command `_v1`, event `_v1`, `maybe_*` handler, dispatch wrapper.
- `vehicle_aggregate` + `vehicle_state` (bit-flag status, battery %, position, current trip, assigned bay).
- Consistency: **eventual** (sequential dispatches in one process read their own writes — the lesson from the parking revert; do NOT use strong).

### 6.2 Router — `route_leg` (pure, in-process)
- `route_leg:route(From, To)` → `#{polyline, distance_m, duration_s, source}`
  where the polyline is the grid staircase (waypoints ahead). No HTTP, no
  fallback path needed — it cannot fail. See §6.0.

### 6.3 Simulator — `simulate_fleet` (the brain)
- Per-operator (reads `company_id` = `TENANT_ID`). Owns ~12 vehicles.
- In-memory kinematic state per vehicle: position, heading, speed, battery, phase, current **road polyline** (from `route_leg`), current bay.
- **Tick loop** (e.g. 1 s sim-time, scaled): advance each vehicle along its polyline; drain battery ∝ real road distance covered; on polyline-exhaustion fire the milestone command into the aggregate.
- **Dispatch policy:** idle (`cruising`) vehicle + open ride request → pick pickup hotspot → `route_leg` to pickup → on arrival `pick_up_passenger` → `route_leg` to dropoff → `drop_off_passenger` + fare. Battery low or service due → `route_leg` to nearest facility with a free bay → `dock_vehicle` → `service_vehicle` (duration by kind) → `release_vehicle`.
- **Demand** via `simulate_demand` (NHPP thinning reused): ride requests per minute follow a day/night profile; origins biased to hotspots.
- **Battery 0 mid-leg** → `deplete_battery` (stranded); simple rescue after a delay → tow to facility → service → release.

### 6.4 Config — `fleet_config`
- A handful of **facilities** (depots) with bay counts and service kinds, on grid intersections (Central `{3,3}`, Westside `{1,5}`, Eastside `{5,1}`).
- **4 operators** with names + colors + home depot + roster size.
- Demand hotspots (hand-placed first; GTFS-seeded optionally).
- Vehicle/economics params: cruise speed, battery capacity, drain rate, fare model (base + per-km + per-min), service durations.

### 6.5 Projection + query — `project_fleet`, `query_fleet`
- Read models: vehicles (current phase, battery, position-at-last-event, lifetime trips/fares/energy), facilities (bay occupancy), operator rollup (active/charging/stranded, trips today, gross fares, energy kWh, net).
- HTTP read API on the existing edge port (replaces `/api/sessions/*`).

### 6.6 Mesh publishers
- `emit_fleet_summary` (5 s): per-operator rollup fact → `fleet/<company>/summary`.
- `emit_fleet_telemetry` (1–2 s): array of `{vehicle_id, lat, lng, heading, battery, phase}` → `fleet/<company>/telemetry`. **Term in, CBOR on the wire — never JSON-encode the payload.**
- Optional: publish the active polyline for a clicked vehicle so the realm can draw its live route.

### 6.7 Realm consumer + map (`macula-realm` ClankerCab slice)
- Subscribe `fleet/+/summary` and `fleet/+/telemetry` for the 4 operators.
- **Inline SVG map** of the 6×6 grid (`ClankerCabMap` hook): streets + depots drawn once, ~48 cab markers colored **by company**, glyph by phase, gliding along streets via a CSS transform transition. **Zero external runtime deps** — no Leaflet, no map tiles. Live counters per company + city total.

### 6.8 Deploy
- Same path: docker-compose on beam00–03, one operator per node via `TENANT_ID` (= company). No sidecars — parksim is the only service (the OSRM container was removed; `deploy-parksim.sh` uses `--remove-orphans` to tear down old ones). Map `company_id` → node: beam00..03 = the 4 operators.

### Done = 4 companies' cabs visibly driving the grid city on the realm map, taking fares, charging at depots, occasional strandings; node-down greys a company out.

---

## 8. Why this is a better Macula demo

- **Living map** beats bar charts: motion sells the mesh.
- **Federated edge → mesh → realm** intact and richer: 4 operators, one
  assembled city.
- **Resilience, organic and true:** node outage greys a company's fleet on
  the map; recovery resumes it. (Replaces the deleted scripted war-scenario.)
- **Springboard to the other workload classes:** on-board LLM passenger Q&A
  (LLM serving); federated demand prediction across operators (federated AI).
- **Sovereign stack:** self-contained grid + inline SVG, no map data, no
  external service, no API keys — on "We are Europe."

---

## 9. Open follow-ups (not blocking the build)

- Company names + colors (propose 4 Belgian-flavored operators).
- `@parksim_url` / map URL wiring in the realm demo (carried over from the
  prior dashboard task).
- Cross-operator vehicle handoff as a later "wow" (a cab crossing into
  another node's coverage).
- ~~`lat/lng → x/y` rename~~ **DONE 2026-05-31:** the position fields are now
  `x`/`y` (grid units) across the brain, events, commands, read model,
  telemetry, and the realm map — no geographic misnomers remain.
- **Stale README:** current `README.md` claims parksim is a *client*
  simulator (fires RPCs, owns no state). The code actually owns the domain
  (aggregates + stores). Rewrite the README for the robotaxi reframe.
