# Performance Phase 2 Report — Attribution (Understanding, Not Speed)

**Date:** 2026-07-17  
**Scope:** Identify unknown main-thread time + function hotspots. No gameplay changes. No engine redesign.

## 1. Before vs after frame timings

| Metric | Phase 1 baseline | Phase 2 (after attribution) |
|---|---|---|
| Avg frame | 59.5 ms | **56.2 ms** (same machine/session class) |
| P95 frame | 295.7 ms | **291.5 ms** |
| Worst frame | 650 ms | **~960 ms** (spike sample) |
| Implied FPS | ~16.8 | ~17.8 |

Frame times are **not** the success metric for Phase 2. Understanding is.

## 2. Unknown main-thread time (the real product of this phase)

| Metric | Before Phase 2 | After Phase 2 |
|---|---|---|
| **Reported untracked avg** | ~30.3 ms *(inflated “tracked” by worker stages)* | **36.2 ms true main residual** |
| Untracked p95 | — | 248 ms |
| Untracked worst | — | 299 ms |

### Methodology fix (critical)

Worker stages (`chunk_mesh` / `chunk_column` / `chunk_buffer`) were previously counted as **main-thread tracked**, which **hid** real unknown main time.

They are now `record_worker_stage` and **excluded** from untracked.

So:

- Phase 1 “untracked ~30 ms” was **under-reporting** unknown main work.  
- Corrected pre-instrumentation residual ≈ **~50–53 ms**.  
- After naming more main systems (esp. `living_world`, `town_defense`, player/camera/UI/weapons/fluids): residual **~36 ms**.

**Target &lt; 2 ms residual: not yet met.** Remaining ~36 ms is real residual outside current GDScript scopes (engine/render/idle + still-unscoped nodes). Phase 3 must continue attribution + optimize known hotspots.

## 3. Top 10 hottest subsystems (avg ms, Phase 2 profile)

1. **untracked** — 36.2  
2. **worker_total** — 19.5 (worker wall, not main)  
3. **chunk_mesh** — 15.6 (worker-attributed)  
4. **living_world** — **8.2** ← newly named; was inside unknown  
5. **chunk_column** — 7.3 (worker)  
6. **crystal_sim** — 5.0  
7. **player_physics** — 1.6  
8. **town_defense** — **1.6** ← newly named  
9. **entity_physics** — 0.9  
10. **target_highlight** — 0.7  

## 4. Top 10 hottest functions (avg last-frame ms)

1. `CrystalManager::_process` — 5.4 (max **563**)  
2. `CrystalManager::_tick_crystal_sim` — 5.0 (max **562**)  
3. `CrystalSimulation::tick` — 3.3 (max **115**)  
4. `Player::_physics_process` — 1.6  
5. `TownDefenseManager::_process` — 1.6  
6. `CrystalManager::_dispatch_sim_events` — 1.2 (max **514**)  
7. `ChunkManager::_process` — 0.8  
8. `ActionTargeting::resolve_action` — 0.7  
9. `CrystalManager::_build_sim_snapshot` — 0.5  
10. `CrystalPresentation::flush` — 0.3  

## 5. Largest hitch discovered

**CrystalManager::_dispatch_sim_events** and **`_tick_crystal_sim`** — max **~500–560+ ms** in a single frame.  
Presentation rebuilds are modest by comparison (max ~6 ms).

→ Crystal spikes are **simulation + event dispatch**, not primarily presentation mesh rebuild.

## 6. Root cause — chunk loading lag

Measured stages (main vs worker):

| Stage | Thread | Evidence |
|---|---|---|
| Column maps | Worker | `chunk_column` avg 7.3 / max 148 |
| Mesh build | Worker | `chunk_mesh` avg 15.6 / max 274 |
| Buffer pack | Worker | `chunk_buffer` small |
| Upload/apply | Main | `chunk_upload` + `chunk_apply` ~0.2 ms avg |
| ChunkView::setup | Main | `chunk_view_setup` small |
| SceneTree insert | Main | `chunk_scenetree_insert` tiny |

**Conclusion:** Visible hitching correlates with **worker mesh/column completion bursts** showing up as high worker totals and occasional main apply, not SceneTree insert. Main-thread apply path is comparatively cheap; **queue completion bursts + crystal spikes** dominate worst frames.

## 7. Root cause — crystal spikes

| Operation | Role in spike |
|---|---|
| `CrystalSimulation::tick` | Up to **115 ms** |
| `CrystalManager::_dispatch_sim_events` | Up to **514 ms** |
| `CrystalPresentation::flush` / rebuild layer | Max **~6 ms** |

**Conclusion:** Spikes are **sim tick + dispatch**, not presentation mesh rebuild.

## 8. Profiler capabilities added

- Main vs worker section kinds; correct untracked  
- Function hotspots: `begin_func` / `end_func` / `record_func` / `get_hot_functions`  
- HOT FUNCTIONS in debug report  
- Streaming gauges + apply/setup/scenetree stages  
- Late `process_priority` so rotation sees a full frame  
- Broader main scopes: player, camera, weapons, overlay, target highlight, combat VFX, fluids, living world, town defense, etc.

Evidence: `PERFORMANCE_PHASE2_PROFILE.md`, `/tmp/cs-perf-phase2/profile_phase2b.log`  
Verifies: `verify_runtime_profiler` OK; `verify_profiler_main` OK.

## 9. Recommended optimization order (Phase 3)

1. **Cap / amortize `CrystalManager::_dispatch_sim_events`** (largest hitch) without redesigning CrystalSimulation architecture.  
2. **Throttle LivingWorldDirector** work (8 ms avg) — poll intervals / spatial cull.  
3. **Smooth worker mesh completion apply** so bursts cannot monopolize frames.  
4. Continue residual attribution toward **&lt; 2 ms unknown** (engine/render probes + remaining nodes).  
5. Only then broad FPS work.

## Design / engineering question (≤2 min)

**Should Phase 3 first attack crystal dispatch spikes or LivingWorld 8 ms steady cost?**

**A)** Crystal dispatch (hitches / p95)  
**B)** LivingWorld steady cost (avg FPS)  
**C)** Both with a shared per-frame budget envelope  
**D)** Something else
