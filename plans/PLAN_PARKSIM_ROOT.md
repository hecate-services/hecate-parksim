# Parksim Plans — Index

*Navigation for `hecate-parksim/plans/`. One line per doc; open the file for detail.*

Parksim is the robotaxi + parking demo on the beam fleet (beam00-03, 4 tenants:
leuven/brussels/ghent/antwerp), event-sourced on reckon_db and federated via the
reckon-gateway + Macula mesh. It doubles as the live showcase for the decentralized
event-store story.

## Active plans

| Document | Description | Status |
|----------|-------------|--------|
| [PLAN_DECENTRALIZED_NFR_DEMO.md](PLAN_DECENTRALIZED_NFR_DEMO.md) | Use parksim to demonstrate/motivate decentralized-vs-centralized event-store NFRs; Phase 1 = Decentralization Scorecard + partition/sovereignty/self-heal runbook, Phase 2 = charging-as-a-decentralized-process | 🟢 Scoped, Phase 1 starting |
| [PLAN_PARKSIM_MESH_CITIZEN.md](PLAN_PARKSIM_MESH_CITIZEN.md) | Make parksim a proper meshed realm citizen (correctness of realm/mesh membership) | ⚪ Open, not started |

## Designs (reference)

| Document | Description |
|----------|-------------|
| [DESIGN_PARKSIM_ENTITY_MODEL.md](DESIGN_PARKSIM_ENTITY_MODEL.md) | The domain entity model (vehicles, rides, parking, assets, settlements) |
| [DESIGN_PARKSIM_EVENT_SCHEMA.md](DESIGN_PARKSIM_EVENT_SCHEMA.md) | Naming + richness pass over every event payload (screaming payloads) |

## Built / historical

| Document | Description | Status |
|----------|-------------|--------|
| [PLAN_ROBOTAXI_REFRAME.md](PLAN_ROBOTAXI_REFRAME.md) | Reframe parksim as a robotaxi fleet sim (grid city, sim clock, demand curve) | ✅ Built + live |

## Notable delivered work not tracked by a plan file here

- "Almost real" increments (money/settlement, asset lifecycle, exceptions, source-separation seam) — see git history + `apps/project_settlements`, `apps/project_assets`, `apps/guide_ride_lifecycle`.
- reckon_db clustering hardening consumed by the fleet: self-healing (5.8.x), native rejoin / no roll-time split (5.11.0), CPU+disk resource telemetry (5.10.x) surfaced in the gateway's Cluster Nodes panel.
