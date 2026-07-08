# RUNBOOK — Decentralized-vs-Centralized NFR Demo (Phase 1)

*Companion to [PLAN_DECENTRALIZED_NFR_DEMO.md](PLAN_DECENTRALIZED_NFR_DEMO.md). Three
scripted, repeatable scenarios a viewer watches live on the admin dashboard.
Each ends with the one-line contrast: **what a centralized store does instead**.*

## Setup

- **Dashboard:** `http://host00.lab:8080/admin/` — the **Decentralization
  Scorecard** card is the hero (sovereign stores · quorate/fault-tolerance ·
  edge footprint · facts-only egress). It reads the live SSE `status` snapshot;
  no refresh needed.
- **Fleet:** 4 sovereign tenants (leuven/brussels/ghent/antwerp), each a 3-node
  Ra cluster spread across beam01/02/03. The gateway on host00 only *federates a
  view*; it is not in any tenant's data path.
- **Probe (any tenant):**
  ```
  curl -s host00.lab:8080/v1/stores/parksim_leuven_store/cluster | jq
  ```
  Expect `total_nodes: 3`, `available_nodes: 3`, `has_quorum: true`,
  `can_lose: 1`.

Confirm all four green on the scorecard before starting.

---

## Scenario 1 — Partition autonomy

**Claim:** split the fleet and the majority side keeps committing on its own,
while the isolated side refuses unsafe writes. A central store split leaves the
minority dead *and* often stalls the majority; recovery is a human runbook.

> Granularity is a **site** (a beam), not a tenant: the beams share one Erlang
> dist mesh (one cookie, pinned dist port 9100), so a node partitions as a
> whole. Cutting beam03 isolates every tenant's beam03 replica at once — a
> "a whole site goes dark from HQ" story, which is the realistic failure.

1. All four tenants green on the scorecard (`3/3`, `can_lose: 1`).
2. **Partition** one site from the other two (drops only dist traffic to the
   peer beams; SSH + the gateway/dashboard stay reachable):
   ```
   scripts/demo-partition.sh beam03.lab cut
   ```
3. On the dashboard, every store drops to **`2/3` but stays quorate**
   (`has_quorum: true`, `can_lose: 0`): the two-beam majority **keeps
   committing** — autonomy. beam03's replicas are the isolated minority and
   correctly **refuse to commit** — safety, no split-brain. Prove the majority
   is live (rides still flowing) from a majority beam:
   ```
   ssh rl@beam01.lab "docker exec parksim-leuven /app/bin/hecate_parksim eval \
     'reckon_db_cluster:health_check(parksim_leuven_store).'"
   ```
   → `has_leader => true`, still committing; and the isolated beam03 has no
   leader for its replicas.
4. **Reconnect:**
   ```
   scripts/demo-partition.sh beam03.lab restore
   ```
   beam03's replicas **rejoin their persisted clusters natively** (reckon_db
   5.11.0 — no wipe, no reform) and catch up on everything committed during the
   split. Within a couple of SSE ticks the whole fleet is back to `3/3` green —
   convergence, not loss.

> **vs central:** one central cluster, one failure domain. A split kills the
> minority's producers and can stall the majority on quorum loss; there is no
> "other two sites keep serving," and reconvergence is manual.

---

## Scenario 2 — Sovereignty (data stays at origin)

**Claim:** rider PII lives only in the edge store; only *aggregate integration
facts* cross to the mesh. Right-to-erasure is a local delete, not a hunt through
a central pipeline.

1. Show a ride's PII **present locally** (pickup/dropoff/rider) on the edge:
   ```
   curl -s "host00.lab:8080/v1/stores/parksim_leuven_store/events/by-type?types=ride_completed&limit=1" | jq
   ```
   Domain event, full detail, in leuven's own store.
2. Show what the **mesh** carries — only aggregate demand/settlement facts, no
   rider identity, no coordinates. (Federated fact view / the demand-summary
   fact; no per-rider record exists off-node.)
3. **Right-to-erasure:** erase a rider's data locally and prove there is no
   central copy to chase. (The ledger/aggregate erasure path — ties directly to
   the NLnet right-to-erasure brief.)

> **vs central:** 100% of events sit in the middle. Erasure means chasing every
> downstream copy, backup and read model through the pipeline — and trusting the
> operator that it's gone.

---

## Scenario 3 — Self-heal (no operator, no scripts)

**Claim:** kill a replica; the store returns to full strength unattended
(reckon_db 5.11.0 native rejoin — no re-formation, no split).

1. leuven at `3/3`, `can_lose: 1` on the scorecard.
2. **Kill one replica** (a non-leader beam):
   ```
   ssh rl@beam03.lab "docker stop parksim-leuven"
   ```
3. Scorecard: leuven drops to `2/3` but **stays quorate** — `has_quorum: true`,
   `can_lose: 0`. Still serving. The fault-tolerance tile shows the margin
   spent, not an outage.
4. **Bring it back** (watchtower/restart):
   ```
   ssh rl@beam03.lab "docker start parksim-leuven"
   ```
   The replica **rejoins its persisted cluster natively** — no wipe, no reform.
   Within a couple of audit ticks leuven is back to `3/3`, `can_lose: 1`, green.
   No script was run to heal it.

> **vs central:** the central cluster *is* the failure domain. Losing it is an
> outage, and recovery is a human runbook — not an automatic, observable
> property of the system.

---

## Reset / between-runs

- Re-check all four tenants green:
  ```
  for t in leuven brussels ghent antwerp; do
    echo -n "$t: "; curl -s host00.lab:8080/v1/stores/parksim_${t}_store/cluster \
      | jq -c '{n:.total_nodes,up:.available_nodes,q:.has_quorum,lose:.can_lose}'
  done
  ```
- If a tenant is genuinely wedged (diverged singleton that native rejoin can't
  heal — pre-5.11.0 damage), reform it (DESTRUCTIVE, tenant only):
  ```
  scripts/reform-store.sh <tenant>
  ```
- Partition left dangling? `scripts/demo-partition.sh <tenant> restore` is
  idempotent; safe to run anytime.

## Scoring the talk

The whole point: on the **centralized** yardstick (events/s) parksim looks weak
— by design, each facility does a few events/s. On the **decentralized**
scorecard it is strong and a central store is *structurally incapable* of
Scenarios 1–3. That is the motivation, made live. Numbers feed
`reckon-ecosystem/publications/POST_DRAFT_reckon_vs_eventstoredb.md`.
