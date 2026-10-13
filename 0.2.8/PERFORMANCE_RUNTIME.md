# Runtime Performance Profiler — Engine 1.0

**Status:** Permanent (autoload `PerfProfiler`)  
**Gameplay impact:** None — measurement only  
**Budget target:** 16.6 ms/frame (60 FPS)

## How to read it in-game

1. Launch production main.
2. Open the debug panel (existing binding).
3. Read the `--- PERF ---` block: FRAME / CHUNKS / STREAMING / CRYSTAL / ENTITIES / WORLD / RENDER / UI / MEMORY / WORKERS / HOTTEST.

Headless capture:

```bash
CRYSTALSTORM_PROFILE_SECONDS=45 godot --headless -s scripts/profile_gameplay.gd
# → gameplay_profile_report.md under CRYSTALSTORM_SCRATCH
```

Contract verifies:

```bash
godot --headless -s scripts/verify_runtime_profiler.gd
godot --headless -s scripts/verify_profiler_main.gd
```

## Report map

| Block | What it measures |
|---|---|
| **FRAME** | frame_ms, FPS, avg/p95/max history, spike %, untracked |
| **CHUNKS** | snapshot / column / mesh / buffer / upload / apply stage ms |
| **STREAMING** | schedule ms, load queue, mesh queue, inflight jobs |
| **CRYSTAL** | simulation + presentation ms, cell gauges |
| **ENTITIES** | physics, navigation, combat, AI count |
| **WORLD** | terrain queries/edits, dirty regions |
| **RENDER** | draw calls, MultiMesh, primitives, upload |
| **UI** | debug/overlay cost |
| **MEMORY** | current/peak MB, chunk pool free |
| **WORKERS** | worker ms, active, queue, avg/longest job |
| **HOTTEST** | top named sections last frame |

## Instrumentation (no architecture change)

| Section | Source |
|---|---|
| `chunk_column` / `chunk_mesh` / `chunk_buffer` | Worker job complete → `record_us` |
| `chunk_upload` | Mesh queue / buffer drain |
| `chunk_apply` / `stream_schedule` | `ChunkManager._process` drains |
| `crystal_sim` / `crystal_mesh` | CrystalManager / Presentation |
| `entity_physics` / `entity_navigation` | WorldEntity / CrystalEnemy |
| Gauges (queues, pool, memory) | ChunkManager + PerfProfiler `_process` |

API: `begin` / `end` / `record_us` / `record_worker_us` / `set_gauge` / `note_worker_job_ms` / `get_runtime_report` / `get_bottlenecks` / `format_runtime_report`.

## Baseline Phase 1 (2026-07-17)

| Metric | Value |
|---|---|
| Avg frame | **59.5 ms** |
| Untracked (reported) | ~30 ms — **later shown to under-count** (worker stages counted as main) |

## Phase 2 attribution (see `PERFORMANCE_PHASE2_REPORT.md`)

| Metric | Value |
|---|---|
| Avg frame | **56.2 ms** |
| **True main untracked** | **~36 ms avg** (after worker exclusion + more scopes) |
| Largest hitch | `CrystalManager::_dispatch_sim_events` max ~514 ms |
| Newly named steady cost | `living_world` ~8.2 ms, `town_defense` ~1.6 ms |

Function hotspots: debug panel **HOT FUNCTIONS** + `get_hot_functions()`.

## Next (Phase 3) — optimize from evidence

1. Amortize crystal **dispatch** spikes.  
2. Throttle **LivingWorldDirector** steady 8 ms.  
3. Smooth worker mesh completion bursts.  
4. Drive untracked residual toward **&lt; 2 ms**.

Do not optimize without re-measuring.
