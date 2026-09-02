# hecate-parksim-simulator

**Realm-bound traffic simulator** for the `hecate-parksim-*` family.
Fires mesh RPCs against the parking services so
[`reckon-lazy`](https://github.com/reckon-db-org/reckon-lazy)
(`lazyreckon`) and any other event-store viewer have continuous,
varied, believable event flow to display.

The simulator is a *client* of the parksim trio — it doesn't own
state, doesn't advertise capabilities, doesn't write to event stores
directly. Every action is a `macula:call/5` against a capability
advertised by one of the three services.

Runs on Hecate **infrastructure nodes** (BEAM cluster, dedicated
relay boxes). Implements the `hecate_om_service` behaviour.
Substrate: [`hecate-om`](https://github.com/hecate-services/hecate-om).

## Layer position

```
Layer 4 — apps        lazyreckon, hecate-app-*
Layer 3 — session     hecate-daemon
Layer 2 — services    ▶ hecate-parksim-simulator ◀
                        hecate-parksim-entry2exit
                        hecate-parksim-lot
                        hecate-parksim-pricing
Layer 1 — identity    hecate-realm
Layer 0 — kernel      macula-station
```

## Umbrella

| App | Purpose |
|-----|---------|
| `parksim_simulator` | shared root: mesh wrapper, capability constants, scenario presets, plate pool |
| `simulate_clock` | scaled wall-clock (compress N hours into one real hour) |
| `simulate_arrivals` | per-lot NHPP arrival generator (Lewis–Shedler thinning) |
| `simulate_sessions` | per-session command ladder (enter → dwell → trigger → payment → exit) |
| `simulate_lots` | per-lot ops cadence (sweeps, calibrations, maintenance, evacuation drill) |
| `simulate_pricing` | rate boot + permit roster + surge windows + lifecycle ticks |

## Configuration

`config/sys.config` (or env vars) carries:

| Key | Default | Purpose |
|-----|---------|---------|
| `shape` (`PARKSIM_SHAPE`) | `city` | `demo` / `city` / `stress` |
| `time_scale` (`PARKSIM_TIME_SCALE`) | `1.0` | compress N sim-hours into one real hour |
| `seed` (`PARKSIM_SEED`) | `0` | PRNG seed; 0 picks from os time |
| `include_evacuation` | `false` | fire an evac drill at sim-hour 4 |
| `dry_run` | `true` | log mesh.Call instead of invoking macula |

`dry_run` defaults to true so the simulator works against an empty
mesh. Flip it to false for live runs.

## Admin surface

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | hecate-om health probe |
| `GET /api/run` | report active scenario config |
| `POST /api/event` | inject an ad-hoc surge window (`kind`, `at`, `duration`, `multiplier`) |
| `POST /api/evacuate` | fire an evac drill (`lot_id`) |

Cowboy listener defaults to **port 8473** (one above the parksim
trio's 8470 / 8471 / 8472).

## Build / deploy

```bash
podman build -t ghcr.io/hecate-services/hecate-parksim-simulator:dev .
```

Production publish via CI → ghcr.io → reconciler picks up
`/etc/hecate/gitops/system/hecate-parksim-simulator.container` →
systemd boots.

## Deps

* [`hecate-om`](https://github.com/hecate-services/hecate-om) — service substrate
* [`macula`](https://github.com/macula-io/macula) — mesh SDK (`macula:call/5`)
* `cowboy` — local HTTP admin endpoints

## Status

Scaffolded. Boots an OTP release with five sub-apps; in `dry_run`
mode every mesh.Call is logged. Drop in a real `macula-station` and
flip `dry_run` to `false` to drive the live mesh.

## License

Apache-2.0.
