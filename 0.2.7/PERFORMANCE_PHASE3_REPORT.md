# Performance Phase 3 — Frame Budget Scheduler

**Date:** 2026-07-17  
**Goal:** Predictable frame pacing via per-system work budgets (not max FPS).  
**Constraints:** Engine 1.0 frozen · no CrystalSimulation algorithm changes · no gameplay redesign.

## What shipped

### `FrameBudgetScheduler` (autoload)

Path: `systems/frame_budget_scheduler.gd`  
Registered in `project.godot`.

| Responsibility | Implementation |
|---|---|
| Configurable budgets | per-system `budget_us`, `max_units`, `min_units`, `priority` |
| Work unit drain | `run_budgeted(id, callable)` + `BudgetToken` |
| Carry-over | unfinished queue items stay FIFO for next frames |
| Starvation prevention | `min_units` always allowed even if soft wall budget exceeded |
| Emergency flush | `CrystalManager.flush_dispatch_queue()` + `note_emergency_flush` |
| Profiler surface | `format_budget_report()` in debug PERF block |

### Budget table (defaults)

| System | Budget (ms) | Max units/frame | Min units | Priority |
|---|---:|---:|---:|---:|
| `crystal_dispatch` | 2.0 | 48 | 8 | 10 |
| `chunk_apply` | 2.5 | 2 | 1 | 20 |
| `chunk_upload` | 2.5 | 2 | 1 | 25 |
| `town_defense` | 1.5 | 2 | 1 | 40 |
| `living_world` | 1.2 | 8 | 2 | 50 |
| `entity_spawn` | 1.0 | 4 | 0 | 60 |
| `world_rebuild` | 1.5 | 4 | 1 | 70 |
| `hud_rebuild` | 0.8 | 1 | 0 | 90 |

### Systems converted to incremental work

| System | Change |
|---|---|
| **Crystal dispatch** | Non-critical events queued; drained under budget. Critical (power/stats/absorption/ruin) immediate. Large `FLOW_BATCH` split into 32-cell units. Save export emergency-flushes. |
| **LivingWorld** | Ruin scan round-robin under budget (not full center list every frame). Rally still every frame (cheap). |
| **TownDefense** | Accumulated dt per town; round-robin ticks under budget (damage frame-rate independent). |
| **Chunk apply** | Drain uses scheduler token (unit + soft wall); queue depth reported. |

Simulation **tick algorithm** is unchanged (frozen). Tick can still be expensive; **dispatch monopolization is removed**.

---

## Evidence

### A) Synthetic dispatch hitch probe (300 depth events)

| Metric | Result |
|---|---|
| Enqueue | **0.82 ms** |
| Drain waves | 4 |
| **Max drain / wave** | **0.65 ms** |

### B) Large FLOW_BATCH (2000 changed + 1000 dirty)

| Metric | Result |
|---|---|
| Enqueue | **0.39 ms** → 95 units |
| Drain waves | 2 |
| **Max drain / wave** | **2.08 ms** (≈ budget) |

### C) Before (Phase 2 profile) vs after (Phase 3 probes)

| Hitch source | Phase 2 (session max) | Phase 3 (controlled flood) |
|---|---|---|
| Event dispatch monopolizing a frame | **~500–730 ms** (`_dispatch_sim_events` / drain) | **≤ ~2.1 ms / wave** |
| Crystal **tick** algorithm | ~100–120 ms max | Still present (algorithm frozen) |
| Town defense | ~1.6–3 ms | Budgeted · ~0.9–2.5 ms |
| Living world | ~8–12 ms steady | Budgeted scan · still ~9–16 ms wall (work remains, paced) |

### D) 45s gameplay profile (after budgets)

| Metric | Phase 2 | Phase 3 session* |
|---|---|---|
| Avg frame | 56.2 ms | 54.7–68 ms (machine variance) |
| P95 | 292 ms | 335–339 ms |
| Town defense avg | 1.6 ms | **0.94 ms** |
| Crystal dispatch unit drain | n/a | **capped** (verify + hitch probes) |

\*Full session worst frames still include **frozen** `CrystalSimulation::tick` and worker mesh — budgets do not rewrite those algorithms.

### Verifies

```
All frame budget tests OK
All living world tests OK
All crystal simulation split tests OK
```

Logs: `/tmp/cs-perf-phase3/` · suite registration: `verify_frame_budget.gd`

---

## Profiler: budget fields

Debug panel PERF block now includes:

```
FRAME BUDGETS (frame_id=…)
Worst queue: … depth=…
crystal_dispatch  budget … used … rem … units … q=… lat_avg … lat_max …
…
```

Gauges: `budget_<system>_ms`, `budget_<system>_queue`, `budget_<system>_remain_ms`.

---

## Remaining bottlenecks (Phase 4 candidates)

1. **`CrystalSimulation::tick` spikes** (algorithm frozen — needs micro-opt / substep policy inside sim façade only if allowed).  
2. **Worker mesh/column** completion volume (not main monopolization of apply — apply is budgeted).  
3. **LivingWorld ~9 ms** steady — further reduce work (not just units).  
4. **Main untracked residual ~33–46 ms** — continue attribution.

---

## Recommendation for Performance Phase 4

**Primary:** Cap or amortize **`CrystalSimulation::tick` cost at the façade** (e.g. already multi-step limited; explore reducing per-tick absorption scan / flow substeps under load **without changing fluid rules semantics** — config-only if possible).

**Secondary:** LivingWorld work reduction (spatial cull ruin tests).  
**Tertiary:** Residual main-thread attribution toward &lt;2 ms unknown.

---

## Design question (≤2 min)

**When crystal dispatch queue depth exceeds 200, should the game:**

**A)** Raise units temporarily (catch-up, risk hitch)  
**B)** Keep hard cap and accept visual lag behind sim  
**C)** Drop non-critical visual events only (depth toasts/mesh dirty)  
**D)** Something else
