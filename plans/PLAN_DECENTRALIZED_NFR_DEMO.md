# PLAN — Demonstrating Decentralized vs Centralized Event-Store NFRs

**Status:** Phase 1 shipped (2026-07-08) — scorecard (reckon-gateway 0.30.0) +
[RUNBOOK_DECENTRALIZED_NFR_DEMO.md](RUNBOOK_DECENTRALIZED_NFR_DEMO.md).
Phase 2 shipped (2026-07-09) — charging-as-a-decentralized-process
(hecate-parksim 0.5.0): `guide_charging_lifecycle` + `project_energy` +
`simulate_grid_prices` + `on_grid_price_changed_schedule_charging` PM.
**Purpose:** Use parksim as a living proof that a *decentralized* event store
(reckon_db in the Macula mesh) optimizes for a fundamentally different set of
non-functional requirements than a *centralized* one (EventStoreDB, Kafka) — and
that "few events/s" is the tool correctly matched to the problem, not a weakness.

The deliverable is the **framing** made measurable and demoable. The code exists
only to prove the thesis. The motivation prose feeds
`reckon-db-org/reckon-ecosystem/publications/POST_DRAFT_reckon_vs_eventstoredb.md`.

---

## 1. Thesis

Centralized event stores benchmark **throughput** because the central cluster
*is* the scarce resource: everything funnels through it, and the only way to
scale is to make it bigger. events/s defines the product because throughput is
the bottleneck.

A decentralized store has **no center, hence no central throughput ceiling**.
Each node handles only its *local* load (a parking facility: ~2 events/s — the
entire workload of that node). Throughput stops being the metric. What becomes
scarce, and therefore what must be engineered and measured, shifts to:

- **Autonomy** — the node keeps working when cut off (a central store's
  producers just block / the store is unavailable).
- **Sovereignty** — data stays at its origin; only explicit *integration facts*
  travel (a central store sends 100% to the middle).
- **Convergence** — how fast/reliably facts propagate across the mesh and
  reconcile after a partition.
- **Trust without authority** — verifiable provenance with no operator to
  trust (tamper-evident hash-chain).
- **Self-healing** — any node dies, the system recovers unattended.
- **Footprint** — runs on a J4105 mini-PC at the edge, not a datacenter.

Measuring a decentralized store by central throughput is a **category error** —
rating a sailboat by engine horsepower. reckon_db is *already* built for the
decentralized profile: Raft-per-store (consensus for safety, not speed), offline
operation, the domain-events-vs-integration-facts boundary, tamper-evidence,
continuous self-healing (`reckon_db_store_healer`, 5.8+). Every one of those is
a choice that trades throughput away to buy a decentralized NFR.

## 2. Honest trade-offs (the demo must say this)

The claim is **not** "decentralized is better." It is: *the two topologies
optimize different NFRs, and the problem dictates the choice.*

- **Per-append latency is worse.** A Raft quorum round-trip per write is slower
  than appending to one central log. Consensus-safety + partition-tolerance are
  bought with write latency.
- **Operational complexity is real.** N autonomous clusters + convergence is
  harder to run than one central thing (see this repo's split-brain history:
  the boot-race re-formation bug fixed in reckon_db 5.11.0).
- **No global total order.** Aggregate throughput scales *past* any central
  cluster (a million edge nodes × 10 events/s = 10M/s, no central bottleneck) —
  **but** it is a million independent partial-order streams, not one ordered
  log. A globally-ordered firehose is a job for a centralized store.

Right tool for: edge / federated / multi-owner / sovereign. Wrong tool for:
central-firehose-to-analytics / global total order / max single-stream throughput.

## 3. The reframe

The parksim dashboard currently leads with **Fleet Event Ingest (events/s)** — a
*centralized* yardstick on which parksim looks weak. The demonstration replaces
that hero metric with the **decentralized scorecard**, where parksim is strong
and a central store is *structurally incapable*.

| NFR | Centralized store | reckon_db / Macula |
|---|---|---|
| Headline metric | throughput (events/s) | autonomy · sovereignty · convergence |
| Scaling | grow the central cluster | add autonomous nodes (federate) |
| Partition | producers blocked, store unavailable | each node keeps serving locally |
| Data location | all events at the center | events stay at origin; only *facts* travel |
| Right-to-erasure | chase copies through the pipeline | erase locally — it's gone |
| Trust | trust the operator | tamper-evident chain, no central authority |
| Failure domain | central cluster = SPOF | any node dies, self-heals |
| Footprint | datacenter | J4105 at the edge |
| Governance | one owner / jurisdiction | plural, sovereign, commons |
| **Price paid** | — | higher per-append latency; harder ops |

The last row is what makes it credible. The demo's job: make each row concrete
and measurable via the running fleet.

---

## 4. Phase 1 — Make the NFRs visible (no new domain code)

Shortest path to *motivating* the difference. Uses the existing ride process.

### 4a. "Decentralization Scorecard" panel (reckon-gateway)
Replace the throughput-as-hero framing in the admin dashboard with a scorecard.
Per tenant / per node, surfaced via the SSE `status` snapshot:

- **Partition state** — is this edge still serving while disconnected from the
  mesh/gateway? (boolean + duration). Source: the edge tracks last-mesh-contact;
  the gateway can also observe reachability.
- **Data-locality ratio** — domain events kept local vs integration facts
  published. Source: counters on the edge (events appended) vs facts emitted to
  the mesh. Expresses "how little leaves the node."
- **Self-heal** — `heal_count`, `last_heal_at` (already in
  `reckon_db_cluster:health_check/1`; already rendered as ORPHAN badges — promote
  to a first-class scorecard number).
- **Convergence latency** — fact-published → seen-by-all-peers (needs a probe
  fact + timestamps; can reuse the mesh torture harness pattern).
- **Footprint** — RSS MB/node + on-disk store size (extend
  `reckon_db_resource_monitor` with process/store size, or read from
  `reckon_db_cluster` stats).

Files: `reckon_gateway_http_health.erl` (collect), `reckon_gateway_http_sse.erl`
(`status.scorecard`), `priv/static/admin/index.html` (a "Decentralization"
card). Keep the events/s meter but demote it from hero to a footnote.

**Delivered v1 (reckon-gateway 0.30.0, 2026-07-08):** the scorecard is built
*entirely from the existing SSE snapshot* — no new endpoint, no reckon-db bump.
Four tiles: **sovereign stores** (independent Raft clusters), **quorate +
weakest `can_lose`** (fault tolerance), **edge footprint** (on-disk event data
across `nodes[]` + mean CPU), **facts-only egress** (sovereignty boundary).
Fleet Event Ingest demoted to a footnoted meter. Each tile shows the "vs
central" contrast. **Deferred** (documented follow-ups, need new counters/probe):
live partition-state boolean, data-locality *ratio* (events-local vs
facts-emitted counters on the edge), convergence-latency probe, and promoting
`heal_count`/`last_heal_at` from the ORPHAN badge into a scorecard number.

### 4b. Demo runbook (`plans/` + a script under macula-demo/infrastructure)
Scripted, repeatable scenarios that a viewer watches on the dashboard:

1. **Partition autonomy.** Cut one tenant's mesh link (block the edge↔gateway
   route). Show rides + charging keep committing on the isolated 3-node edge
   (quorum intact, events accumulating). Reconnect → facts converge; the world
   catches up. *A central store cannot do this — the disconnected producer is
   dead.*
2. **Sovereignty.** Show ride/rider PII (pickup/dropoff, rider id) stays in the
   edge store and NEVER crosses to the mesh — only aggregate demand facts do.
   Then right-to-erasure: erase a rider locally, prove there is no central copy
   to chase. (Ties directly to the NLnet right-to-erasure brief.)
3. **Self-heal.** Kill a beam node; watch the store return to 3/3 unattended.
   (Already demonstrated; formalize as a runbook step.)

Deliverable of Phase 1: the scorecard + runbook = the core "decentralized vs
centralized" motivation, achievable on today's processes.

---

## 5. Phase 2 — The richer process as the vehicle (density + federation NFR)

Answers "why so few events/s" by modeling a denser, real process, and adds the
one NFR Phase 1 can't show: **federated coordination with no central controller.**

**Delivered (hecate-parksim 0.5.0, 2026-07-09).** All four pieces below shipped:
`guide_charging_lifecycle` (aggregate + 5 desks: request/start/progress/complete/
settle), `project_energy` (per-operator kWh/cost/off-peak share), the
`grid_price_changed` fact via `simulate_grid_prices`, and the
`on_grid_price_changed_schedule_charging` PM (charge-now-vs-defer from the mesh
price). The sim emits the full charging stream (priced by the live tariff) and
defers non-critical charging when the grid is dear. **Simplifications vs the
sketch below:** tariff is stamped inline on `charging_started`/`energy_settled`
rather than a separate `tariff_applied` event; `charger_reserved`/DCB reuse and
`charging_interrupted` were dropped (the bay is already reserved by the visit);
each region publishes its own price and reacts to its own (peer prices feed only
a regional view), sidestepping the mesh's no-same-node-loopback. The dashboard
Energy card + the write-up (§6.3) remain follow-ups.

### 5a. Charging as a first-class decentralized process
Today charging is one flat `battery_charged` event in `guide_vehicle_lifecycle`.
In a real EV fleet it is the highest-frequency, most economically central
process. Model it as its own vertical slice — a new app `guide_charging_lifecycle`
(screaming architecture; the charging process earns its own slice).

Event vocabulary (business verbs, no CRUD; `_v1` suffix per house style):

```
charge_requested_v1        (vehicle SoC below threshold, at/heading to a charger)
charger_reserved_v1        (a bay/charger claimed — reuses the bay DCB)
charging_started_v1
charging_progressed_v1     (per-SoC-milestone: 40% → 60% → 80% … — the density)
charging_completed_v1
charging_interrupted_v1    (pre-empted, fault, moved to serve demand)
tariff_applied_v1          (off-peak / peak rate stamped on the session)
energy_settled_v1          (kWh × tariff → cost, into the ledger)
```

Aggregate: `charging_aggregate` (stream `charging-<session_id>`), SoC/phase state
machine mirroring `ride_state`. Handlers `maybe_*`. This alone multiplies event
density: every vehicle charges several times a sim-day, and the per-SoC
`charging_progressed` milestones make it a genuinely dense stream (unlike the
sparse ride milestones).

### 5b. Read model
`project_energy` (SQLite): per-operator kWh, cost, off-peak %, sessions,
per-vehicle charge history. Projection `charging_event_to_energy`. Feeds an
Energy card in the dashboard and the settlement ledger (`energy_cost` debit —
already a ledger kind).

### 5c. The federation twist (the decentralized NFR made tangible)
Coordination with **no central charging controller**:

- A **`grid_price_changed`** integration FACT propagates across the mesh (from a
  simulated energy provider node, or a designated tenant). Public schema:
  `#{region, price_cents_per_kwh, window, valid_until}`. No PII.
- A **process manager** on each edge — `on_grid_price_changed_schedule_charging`
  (lives in the target `guide_charging_lifecycle` per the cross-domain-via-PM
  rule) — reacts: given local vehicle SoC + the shared price signal, it decides
  charge-now vs defer, autonomously. The aggregate charging behavior of the
  whole mesh *emerges* from fact propagation, not a central dispatcher.
- Optional CCC angle: gate a charge decision on the *absence* of a competing
  reservation across streams (payload-conditioned), showcasing DCB/CCC.
- Optional: each tenant emits an `energy_demand_summary` fact (aggregate, no
  PII) — the sovereignty boundary in action (local sessions private, aggregate
  shared). Consumers: a mesh-level demand view; the cooperative-energy-commons
  story (OpenEMS/Victron thread).

### 5d. Sim wiring
`simulate_fleet_core` already models battery drain + `apply_service(charge)`.
Split its single charge action into the process: on reaching a charger, emit
`charge_requested` → `charging_started` → periodic `charging_progressed` as SoC
climbs during the `servicing` phase → `charging_completed`/`energy_settled`.
Drive the charge/defer decision from the PM's grid-price signal. This also makes
the servicing phase (currently ~24% of vehicles, a silent in-memory state)
produce a rich event stream.

---

## 6. Sequencing & deliverables

1. **Phase 1** first — scorecard + partition/sovereignty/self-heal runbook. This
   *is* the motivation; ship it before the process work.
2. **Phase 2** — `guide_charging_lifecycle` slice + `project_energy` +
   `on_grid_price_changed_schedule_charging` PM + sim wiring. Deepens the demo
   (federation) and answers event density.
3. **Write-up** — fold the thesis + trade-offs + scorecard results into
   `reckon-ecosystem/publications/POST_DRAFT_reckon_vs_eventstoredb.md`, grounded
   in live numbers rather than assertions.

## 7. Discipline (per repo CLAUDE.md / hecate-corpus)
- Business-verb events only — no created/updated/deleted.
- Vertical slices — `guide_charging_lifecycle` owns its commands/events/handlers.
- Cross-domain via **process managers**, never direct dispatch; the grid-price PM
  is a sibling slice in the target charging domain.
- Domain events stay local (edge reckon_db); the mesh sees only explicit
  integration facts (`grid_price_changed`, `energy_demand_summary`) with stable
  public schemas — the sovereignty boundary is the whole point.

## 8. Related
- [PLAN_ROBOTAXI_REFRAME.md](PLAN_ROBOTAXI_REFRAME.md), [PLAN_PARKSIM_MESH_CITIZEN.md](PLAN_PARKSIM_MESH_CITIZEN.md)
- [DESIGN_PARKSIM_EVENT_SCHEMA.md](DESIGN_PARKSIM_EVENT_SCHEMA.md)
- reckon_db 5.11.0 (native rejoin / self-coordination) — the resilience NFR this demo showcases.
- `reckon-ecosystem/publications/POST_DRAFT_reckon_vs_eventstoredb.md` — the motivation post this feeds.
