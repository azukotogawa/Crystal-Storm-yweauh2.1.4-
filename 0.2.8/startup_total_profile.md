# Crystal Storm — startup / world-generation profile

**Status:** measurement only. No generation, quality, or world-size changes.  
**Date:** 2026-08-15  
**Godot:** 4.7.1.stable (headless console)  
**Machine:** Windows, 8 logical processors  
**Seed:** 12349  
**Production bake size:** 128×128 chunks = **16,384** packages (`PLAYABLE_HALF=1024`, `CELLS=16`)

Detailed dumps:

- `startup_phase_timings.json` — combined summary
- `startup_phase_timings_cold.json` — full cold event log
- `startup_phase_timings_warm.json` — full warm event log

Instrumentation is inert unless `CRYSTALSTORM_STARTUP_TOTAL_PROFILE=1`.

---

## What “playable” actually means

The loading screen fades at **`CompositionRoot.INITIAL_STREAM_READY`**.

That stage is defined as: **≥1 resident streamed chunk**. `main.gd` then allows gameplay input while later stages finish under the fade.

On a **cold** launch this gate is **after** `WorldBakeService.bootstrap_for_world_async` returns. That function does not stream the starting neighborhood first. It either:

1. loads a valid `user://world_bakes/v4_s{seed}_full/world.index`, or
2. **synchronously generates mesh plans + column data + `.chk` files for the entire 16,384-chunk map**.

Runtime chunk streaming around the player is **not** what holds the loading screen for minutes.

---

## Pre-existing disk state (why every launch can look cold)

Before this session, `user://world_bakes/v4_s12349_full` already existed with:

| Item | Value |
|---|---|
| `.chk` files | **8,592** |
| Expected full map | **16,384** |
| `world.index` | **missing** |

Production `load_bake_for_seed` only succeeds if the index is present. An interrupted bake leaves orphan packages and **forces a full rebuild** on the next launch. That matches “it always takes ~10 minutes”: many sessions never finish the bake, so the next session starts over.

That incomplete tree was moved aside as `v4_s12349_full_INCOMPLETE_PREPROFILE` so the cold run would be a clean first bake.

---

## Cold launch (no valid bake)

| Marker | Time |
|---|---|
| Process / script start | 0 |
| `PackedScene.load` main.tscn | 7.9 s |
| Feature seed (towns/ruins/spawns) done | 14.2 s |
| Bake miss (`no package for seed=12349`) | 15.1 s |
| Vegetation scatter done | 17.6 s |
| `bake.chunk_loop` start | 17.7 s |
| **60 s snapshot** | still in `bake.chunk_loop`; **264 / 16,384** chunks; **not playable** |
| `bake.chunk_loop` end | 2,201.4 s |
| `save_bake` / index write | 2,201.4–2,208.1 s |
| `INITIAL_STREAM_READY` / **PLAYABLE** | **2,211.6 s (36.9 min)** |
| `RUNNING` | 2,212.8 s |
| Process exit | 2,226.6 s |

`ICS_FRAMES_WAITED 0 chunks_ready=64` — once the bake finished, the first stream neighborhood was already resident. The long wait was **not** worker streaming.

### First 60 seconds vs the rest

| Window | Wall | What was happening |
|---|---|---|
| 0–60 s | 60 s (2.7% of total) | Scene load, config, towns/ruins, vegetation scatter, **264 bake chunks** |
| after 60 s | **2,166.6 s (97.3%)** | Remaining **16,120** bake chunks + index write |

At 60 s the player is still on the loading screen (`FEATURES_SEEDED` / “Generating World…”). Playable is ~36 minutes later.

### Ranked leaf contributors (cold wall-clock)

Parent wrappers (`boot_async`, `create_chunk_manager`, etc.) all collapse to the same bake. Leaf work inside the bake:

| Rank | Work | Seconds | % of 2,226 s wall | Class |
|---|---:|---:|---:|---|
| 1 | `ChunkManager._build_mesh` (mesh **plan** per package) | **905.9** | **40.7%** | sync main-thread mesh generation |
| 2 | `get_surface_height_worker` + `get_tile_type_worker` × 256 cells × 16,384 | **818.1** | **36.7%** | sync main-thread world generation |
| 3 | `_write_chunk_package` (`.chk` writes) | **283.2** | **12.7%** | disk I/O |
| 4 | `await process_frame` every 4 chunks | **69.7** | **3.1%** | yield / UI sync wait |
| 5 | `PackedScene.load(main.tscn)` | 7.9 | 0.4% | resource load |
| 6 | `save_bake` (index + reread-all size sum) | 6.8 | 0.3% | disk I/O |
| 7 | Feature seed (towns/ruins/spawns) | 2.1 | 0.1% | feature generation |
| 8 | Bake vegetation scatter (7,052 entries) | 2.1 | 0.1% | vegetation generation |
| 9 | Initial stream wait | 0.2 | ~0% | workers (not the hitch) |

`bake.chunk_loop` total = **2,183.6 s (98.1% of wall)**.

Crystal bootstrap (9.3 s) **overlaps** the start of the bake; it is not extra wall time. Water `_ready` is ~80 ms. Runtime vegetation scatter is **skipped** (`skip_runtime_vegetation=true`) because production will bake plants into packages.

Per-chunk average: **133 ms** (mesh plan ~55 ms, columns ~50 ms, write ~17 ms, yield ~4 ms). Rate started ~12 chunks/s and dropped to ~6 chunks/s after ~9,000 files (disk / AV / directory size). That slowdown is why an earlier session died at 8,592 files with no index.

### Call chain of the largest contributor

```
Godot process start
  → scripts/profile_startup_total.gd  /  main.tscn
    → main._ready
      → CompositionRoot.boot_async
        → CONFIGURED / QUALITY_APPLIED / FEATURES_SEEDED   (~6 s)
        → VoxelWorld.create_chunk_manager_with_services
          → ChunkManager.bootstrap_world_bake_async
            → WorldBakeService.bootstrap_for_world_async
              → load_bake_for_seed(12349)          # miss: no world.index
              → bake_world_async                   # MAIN THREAD, not workers
                → _bake_vegetation_by_chunk        # 2.0 s
                → for cz, cx in 128×128:           # 16,384 iterations
                    world.get_surface_height_worker  ×256
                    world.get_tile_type_worker       ×256
                    ChunkData.capture_worker_snapshot
                    mesh_host._build_mesh            # greedy plan
                    _write_chunk_package             # user://.../chunks/cx_cz.chk
                    await process_frame every 4
                → save_bake()                      # write world.index
        → request_initial_stream
        → INITIAL_STREAM_READY   ★ PLAYABLE
```

Workers are used later for **stream apply**. They do **not** run this bake. The bake calls the same “worker-safe” noise APIs **on the main thread**.

---

## Warm launch (valid `world.index` present)

| Marker | Time |
|---|---|
| `PackedScene.load` | 5.0 s |
| Feature seed done | 11.3 s |
| `load_bake_for_seed` + validate | 12.3–12.4 s (**mode=loaded**) |
| Chunk manager init done | 13.8 s |
| **PLAYABLE** (`INITIAL_STREAM_READY`) | **17.7 s** |
| `RUNNING` / process exit | 19–33 s |

No `bake.chunk_loop`. Index load 0.98 ms. Validate 14.7 ms. Stream wait 3 frames / 1 chunk then drain.

**Warm is ~125× faster to playable than cold** (17.7 s vs 2,211.6 s).

---

## Cold vs warm

| | Cold (rebuild) | Warm (valid index) |
|---|---:|---:|
| Playable | **2,211.6 s** | **17.7 s** |
| Wall to exit | 2,226.6 s | 33.1 s |
| Bake mode | `baked` | `loaded` |
| Chunks generated this launch | 16,384 | 0 |
| Mesh-plan CPU | 905.9 s | 0 |
| Column noise CPU | 818.1 s | 0 |
| Package writes | 283.2 s | 0 |
| Runtime stream | 0.2 s | 0.3 s |
| Loading-screen text | “Generating World… N / 16384 chunks” | “Loading World…” then nearby stream |

If a player always sees ~10+ minutes, they are on the **cold / invalid-index** path every time — usually because `world.index` was never written (process killed mid-bake).

---

## Exact reason the game stays unplayable for minutes

The game is not waiting on GPU, Jolt, crystal sim, water, or neighborhood chunk streaming.

It is blocked in **`WorldBakeService.bake_world_async` on the main thread**, generating a **finite but huge offline package** for the whole playable map (16,384 chunks × 256 columns × mesh plan × disk write) **before** `INITIAL_STREAM_READY`.

The loading screen text is technically honest (“Generating World… N / 16384 chunks”) but it is **not** the runtime stream around the player. That stream only starts after the full bake (or a valid index load). Cooperative `await process_frame` keeps the window painting; it does not parallelize the work.

On this 8-core machine a clean cold bake took **37 minutes** to playable. A ~10 minute report is the same pipeline: either a faster box, a partial wait, or quitting around the mid-bake slowdown (~8–9k files) that we already found on disk.

---

## What is *not* the hitch

- Crystal init / fluid tick
- Water engine
- Town / ruin / wildlife seeding (~2 s)
- Runtime vegetation scatter (skipped)
- Worker mesh jobs for the starting view (sub-second after bake)
- Texture generation
- Quality preset (default production path; no preset override)

---

## Files / env

Profile runs used production defaults: no `CRYSTALSTORM_BAKE_RADIUS`, no `CRYSTALSTORM_FULL_WORLD_BAKE=0`, no quality override.

Temporary instrumentation: `systems/startup_total_profiler.gd` plus env-gated hooks. Off unless `CRYSTALSTORM_STARTUP_TOTAL_PROFILE=1`.

---

## Verification suite (instrumentation safety)

`bash scripts/run_all_verify.sh` was run after the hooks with the suite’s smoke bake env (`CRYSTALSTORM_BAKE_RADIUS=2`, `FULL_WORLD_BAKE=0`). Instrumentation env was **unset**.

Passed: composition/boot, world-state, chunk pipeline, bake (including `verify_full_world_bake` / `verify_streamed_world_bake`), terrain, water, save architecture, combat, frame budget, and the other gating scripts in the runner.

Failed (6), **not** parse/boot breaks from the profiler:

| Script | Observed reason |
|---|---|
| `verify_crystal_live_spread` | Main-scene neighbors have no crystal depth at relocated origin `(-10, 10)` |
| `verify_living_world` | Town villagers not re-seeded after `chunk_ready` (`got=0 want=3`) |
| `verify_save_slot_main` | exit 1 (no instrumentation path in that test) |
| `verify_manual_pristine_after_probe` | exit 1 (evidence/pristine contract) |
| `verify_display_session_log` | exit 1 (display-session evidence file) |
| `verify_smoke_gameplay` / `verify_smoke_quit_path` | exit 1 (smoke evidence / quit-path on Windows headless) |

Those failures are content/stream/evidence contracts, not “profiler always-on” or missing `class_name`. The hooks are no-ops without the env flag.
