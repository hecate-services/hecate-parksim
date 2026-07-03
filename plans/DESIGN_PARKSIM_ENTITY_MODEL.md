# DESIGN: Parksim entity model

Status: Draft (2026-07-03)
Owner: this session
Related: PLAN_ROBOTAXI_REFRAME.md, PLAN_PARKSIM_MESH_CITIZEN.md

## Why this doc exists

A quality audit of the parksim simulator surfaced logical errors in the
parking side (asymmetric and unpaired occupancy events). The errors are
symptoms of a deeper structural issue: the simulator keeps an ad-hoc model
of the world that runs in parallel with, and drifts from, the event-sourced
domain. This doc records the audit, the fixes already applied, and a staged
plan for the "living entity" rework, with an honest account of the trade-offs
so the big decisions are made deliberately.

## The core smell: two models of one fact

A parking visit is currently represented twice, from two different code
paths, on every visit:

1. Domain lifecycle (aggregate desks in `guide_parking_session_lifecycle`):
   `parking_session_initiated` then `vehicle_docked` then `vehicle_undocked`
   then `payment_captured` then `parking_session_archived`.
2. DCB occupancy guard (`parking_session_dcb`): `vehicle_entered_lot` on
   claim, `vehicle_exited_lot` on release.

Two sources of truth for "a car is in a lot" means they can and do disagree.
Every audited defect lives in the gap between them.

## Audit findings

### Fixed in commit a88c5d6 (the concrete bugs)

- F1. `vehicle_exited_lot` had no `lot_id` while `vehicle_entered_lot` did.
  `release_entry/3` was never passed the lot id. Fixed: `release_entry/4`
  threads `LotId`, exit payload is now symmetric with entry.
- F2. One `entered`, many `exited`. `claim_entry` appends the entry
  CONDITIONALLY (optimistic concurrency, bounded retries) on the shared
  `_dcb` stream; `release_entry` appends the exit UNCONDITIONALLY. The caller
  then "failed open" on any non-`already_parked` error and ran the full
  lifecycle including the release, so under contention it emitted exits with
  no matching entry. Fixed: proceed only on a successful `ok` claim; skip the
  visit on transient/contention errors (no half-lifecycle).
- F3. `read_plate_state` truncated the per-plate DCB history at
  `batch_size => 200`. Plates come from a reused pool (500 to 6000), so a
  plate's DCB history grows two events per visit without bound; the oldest-200
  window mis-reads the current park state, which makes the conditional claim
  fail forever (feeding F2). Mitigated by widening the read. Proper fix is
  structural (below).

### Still open (deliberately deferred to the rework)

- O1. Bays collide. `pick_bay` picks a random bay id with no occupancy
  tracking (the code comment admits it), so two sessions can hold the same
  bay. `parking_bay` has no state and no capacity enforcement.
- O2. Unbounded DCB history per plate. F3 is a mitigation, not a cure: the
  `_dcb` tag stream still grows without bound and every claim reads a widening
  window (O(history) per claim). Needs compaction or a proper membership read
  model.
- O3. Abandonment starves the plate pool. About 0.7% of visits abandon and
  never release the DCB claim (intentional: the car is still physically
  there), so that plate is `already_parked` forever. Over a long run the pool
  slowly drains. Needs an eventual reclaim (tow/reaper) or an unbounded/unique
  plate supply.
- O4. Duplicate representation. The domain lifecycle and the DCB guard both
  model occupancy. This is the root of F1 and F2 and should collapse to one
  model with the invariant enforced in the domain.

## The design principle

The living entity that matters is the event-sourced aggregate, not a
simulator process. Event sourcing already gives entities identity, state, and
enforceable invariants: an aggregate command handler can refuse an illegal
transition, which makes whole classes of bug impossible by construction. A
`parking_session` that enforces "you cannot exit a session that never
entered" cannot produce F2, no matter what the simulator does.

So the target shape is:

- The domain owns invariants. Occupancy (a plate is in at most one lot; a bay
  holds at most one session; a lot does not exceed capacity) becomes a domain
  concern enforced by aggregates and/or a single DCB, not a simulator-side
  afterthought plus a parallel guard.
- The simulator generates plausible intent (commands) and drives the domain.
  It does not maintain a second model of truth and does not "fail open" into
  emitting events the domain would have rejected.

## The actor question, weighed

The proposal is to make vehicle, parking_lot, parking_facility, parking_bay,
passenger, driver into living processes (gen_servers). The instinct is sound
but "everything is a gen_server" is a trap. Judge each entity on lifetime,
cardinality, and whether an actor enforces an invariant a value cannot.

| Entity | Actor? | Rationale |
|--------|--------|-----------|
| parking_lot, parking_facility, parking_bay | Yes | Long-lived and BOUNDED (a few lots, tens of bays each: hundreds of processes, trivial on BEAM). A bay actor enforces single-occupancy; a lot actor owns its bays and capacity. Directly eliminates O1 and the double-booking class. |
| parking visit / session | Already a process | `simulate_visit` already spawns one process per visit. Keep it, but have it drive the aggregate rather than the parallel DCB. |
| vehicle (robotaxi) | Optional | 48 cabs as actors reads well in a demo. But `simulate_fleet_core` is a deterministic, seed-replayable, cleanly unit-tested pure core. Actor-izing trades that asset away for concurrency not needed at this scale. Decide on demo value, not dogma. |
| passenger, driver, individual ride | No | High-churn transients (thousands per hour). A passenger has no long-lived autonomous behaviour; it is a `ride_requested` -> matched -> `ride_completed` flow. Processes here buy churn and a matchmaking-registry problem for no invariant gain. A robotaxi has no separate driver. |

### Costs a full actor-soup rewrite imposes

- Determinism loss. Concurrent actors with timers produce non-deterministic
  ordering and timing; the reproducible seed-driven core tests go away. That
  reproducibility is a real asset for a demo you want to re-run identically.
- Coordination machinery. Process registries (pid to entity id), discovery,
  supervision trees, inter-actor protocols.
- Failover rehydration. The fleet is leader-gated and per-tenant sharded; on
  leader failover every entity process dies and must be rebuilt from events.
  A pure core rehydrates by replaying into a map; an actor city must respawn
  and restore each actor.
- Timeline risk. A big rewrite right before a demo, and it does not by itself
  produce better events than a correct model does.

## Staged plan

1. Fix the concrete bugs. DONE (commit a88c5d6): F1, F2, F3.
2. Collapse to one model. Make bay/lot occupancy a domain invariant. Options,
   in preference order:
   a. A `parking_lot` (and `parking_bay`) aggregate or DCB that owns
      occupancy, and retire the separate `parking_session_dcb` guard so there
      is one enforcement point. The session lifecycle references it.
   b. If keeping DCB, make entry and exit symmetric and conditional on the
      same consistency boundary, and add compaction so history is bounded
      (closes O2). Reaper for stale claims (closes O3).
3. Selectively actor-ize the bounded, long-lived infrastructure. Lots,
   facilities, bays as owned processes (or aggregate-backed services) that
   enforce capacity and single-occupancy (closes O1). Keep transients as
   events. Decide vehicle-as-actor on its own merits.

Resist the big-bang "everything is a gen_server." The actual defects are a
duplicated model and fail-open writes, both fixable directly. Actors are a
tool to apply where they enforce an invariant a value cannot, not a default.

## Decision log

| Date | Decision |
|------|----------|
| 2026-07-03 | F1/F2/F3 fixed directly in the DCB layer (commit a88c5d6). |
| 2026-07-03 | Rework framed as: invariants belong in the event-sourced domain; the simulator drives it. Actors adopted selectively for bounded, long-lived entities (lots/facilities/bays), not for transients (passengers/rides). Pending owner sign-off before step 2. |
