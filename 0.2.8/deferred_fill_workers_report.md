# Deferred bake worker migration — report

**Date:** 2026-08-15  
**Contract:** unchanged (prime → playable → background fill; `world.index` only at expected count).

## What moved to workers

`WorldBakeWorkerJob.execute` (used by `WorkerThreadPool`, cap 2 inflight / 12 pending):

- column sample (`get_surface_height_worker` / `get_tile_type_worker`)
- `ChunkData.capture_base_only_snapshot` (empty overlays; no live WorldState maps)
- mesh plan via existing `ChunkManager._build_mesh` (same as stream workers)
- v4 `.chk` serialize + atomic disk write

Priority: stream on-demand > nearby (chebyshev ≤ 3) > distant fill. Duplicates rejected.

## What stays on the main thread

- inventory / prime (startup, loading screen)
- enqueue, collect, `_packages_known` register
- `ensure_package_for_stream` wait for one on-demand job (rare far travel)
- progress UI
- `save_bake` / `world.index` only when `known == expected`
- live stream apply, terrain edits, water, crystal
- `CRYSTALSTORM_BAKE_DEFER_FILL=0` full await-bake (sync `_bake_one_chunk`)
- `CRYSTALSTORM_BAKE_FILL_SYNC=1` old 1/frame main-thread fill (profile B)

Fill never calls `WorldState.replace_active` and never writes live overlays.

## Frame times (windowed `main.tscn`, D3D12)

B = previous main-thread fill (`deferred_fill_gameplay_profile.md`). A/C = this harness.

| | idle p50 | idle p95 | play p50 | play p95 |
|---|---:|---:|---:|---:|
| **A fill OFF** | 10.9 | 116.7 | 110.3 | 250.6 |
| **B old fill ON** | **106.7** | **173.4** | **191.2** | **626.8** |
| **C worker fill ON** | **8.8** | **46.0** | 153.1 (run2 **98.8**) | 294.4 |

C idle matches A (not B’s 9 FPS). C play p95 is ~295 ms vs B 627 ms; remaining play cost is **water reflow + edits**, also present in A (A play `voxel_fluid` max 272 ms).

## Bake stall gone

| | B old fill | C worker fill |
|---|---|---|
| `_bake_one_chunk` thread | main | **worker** (`main_thread=false`) |
| `world_bake_fill` p95 / max | 118–149 / 130–172 ms | **0.49–0.82 / 0.94–1.14 ms** |
| tick wall | ~92–103 ms | **0.87 ms** |
| packages during C | — | 396 → 570 (run1), then 686 (run2) |
| worker util | — | 0.64–0.89 |
| fill rate | ~3.4/s (1/frame) | ~1.8/s idle, ~9/s while 2 workers busy |

## Gameplay during C fill

| | A | C |
|---|---:|---:|
| dig call avg | 10.5 | 3.6 |
| build call avg | 15.9 | 12.3 |
| water call avg | 13.3 | 14.2 |
| `voxel_fluid` avg / max | 86.8 / 272 | 117 / 344 |
| `crystal_sim` | ≤6 ms | 0–6 ms |
| `chunk_apply` p95 | 1.8 | 1.2 |
| cold `INITIAL_STREAM_READY` | 12.5 s | 13.2 s / 12.3 s |

Water no longer inherits a 100 ms bake on the same frame (old B fluid 137/481). Residual water time is the existing immediate reflow path, visible with fill **off**.

## Determinism / contract

- `verify_bake_one_chunk_parity.gd`: sync `_bake_one_chunk` == `bake_world` (22,156 bytes) **OK**
- `verify_deferred_bake_workers.gd`: worker bytes == sync; write; stream apply; `valid` iff expected; `replace_active` blocked; overlay unchanged; duplicates rejected; resume inventory; on-demand; `DEFER=0` mode=baked **OK**
- `verify_deferred_world_bake.gd`: prime / `valid=false` / rollback **OK**

`valid` stayed false at 570/16,384. Index still completion-only.

## Files

| File | Role |
|---|---|
| `world/world_bake_worker_job.gd` | worker-safe package body |
| `world/world_bake_service.gd` | bounded queue, collect/register, sync path shared body |
| `chunks/chunk_manager.gd` | cheap tick + meshq pause of fill submits only |
| `world/InfiniteNoiseWorld.gd` | bake stats only on main thread |
| `systems/frame_budget_scheduler.gd` | fill budget 2.5 ms (schedule) |
| `scripts/verify_deferred_bake_workers.gd` | 12 contract checks |
| `scripts/profile_deferred_fill_workers.gd` | windowed A/C |
| `scripts/run_all_verify.sh` | register worker verify |

Raw JSON: `{SCRATCH}/deferred_fill_workers_profile.json` and `*_a.json` / `*_c.json`.
