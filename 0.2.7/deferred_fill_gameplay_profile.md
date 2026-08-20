# Deferred-fill gameplay profile

**Date:** 2026-08-15  
**Scope:** measurement only. Bake architecture unchanged.  
**Question:** does background fill (`world_bake_fill` / `_bake_one_chunk`) hurt live play?

**Answer:** yes. `_bake_one_chunk` runs **on the main thread**, typically **90–130 ms per package**, about **one package per frame**. That is not an idle-only cost. It dominates frame time while fill is running.

Startup remains successful: cold `INITIAL_STREAM_READY` in **12.3 s** with `valid=false` and fill still in progress.

---

## Method

Windowed production `scenes/main.tscn` (D3D12 / Forward+, `CRYSTALSTORM_PERF_PRESET=medium`). Seed 12349. No `--headless`.

| Case | Bake state | Env | Player |
|---|---|---|---|
| **A** | complete `world.index` (16,384 packages) | `CRYSTALSTORM_BAKE_DEFER_FILL=0` | 20 s idle, then 20 s scripted play |
| **B** | no index, 233 existing `.chk` | `CRYSTALSTORM_BAKE_DEFER_FILL=1` | 20 s idle after `INITIAL_STREAM_READY` |
| **C** | same session as B | same | 20 s rapid dig / build / move / water / crystal |
| **T** | same incomplete dir, fill still running | `DEFER=1` | forced hops into unbaked chunks |

Play actions (C): `TerrainEditor.try_dig` / `try_build` / `try_channel_water`, `voxel_position` steps across chunk edges, `CrystalManager.damage_spawn_at_world`.

Independent clocks:

- frame wall via `PerfProfiler.get_snapshot().frame_ms`
- bake via timers inside `_bake_one_chunk` (sample / mesh / write) and `tick_background_fill`
- edits via usec around the public TerrainEditor / crystal calls

Raw dumps: `user://deferred_fill_profile_a.json`, `deferred_fill_profile_bc.json`, `deferred_fill_profile_t.json`.

---

## Does bake work block the main thread?

**Yes. Every observed bake ran on the main thread.**

Call path:

```
ChunkManager._process
  → _tick_deferred_bake_fill
    → FrameBudgetScheduler.run_budgeted(world_bake_fill)
      → WorldBakeService.tick_background_fill
        → _bake_one_chunk          # noise sample + _build_mesh + .chk write
```

On-demand far travel uses the same `_bake_one_chunk` from `ensure_package_for_stream` (also main-thread, during stream enqueue).

| Window | bake ops | main-thread ops | worker ops |
|---|---:|---:|---:|
| A idle / A play | 0 / 0 | 0 | 0 |
| B idle | 65 | **65** | **0** |
| C play | 70 | **70** | **0** |
| T travel hops | on-demand + background | **all main** | **0** |

`world_bake_fill` is budgeted at 1 unit / frame and 200 ms soft wall. That budget exists **because** one package already costs ~100 ms. It does not hide the cost from the frame.

---

## Frame-time distribution

`max` in the idle windows includes one shared post-boot hitch (~13 s, crystal/stream settle). That hitch appears in **A and B** and is **not** fill-specific. Compare **p50 / p95**.

| Window | frames | avg ms | p50 | p95 | max | implied p50 FPS |
|---|---:|---:|---:|---:|---:|---:|
| **A idle** (fill off) | 383 | 53.7 | **8.6** | **16.5** | 13279 | ~116 |
| **A play** (fill off) | 531 | 10.7 | **8.2** | **26.3** | 61.0 | ~122 |
| **B idle** (fill on) | 61 | 379.4 | **106.7** | **173.4** | 12959 | **~9** |
| **C play** (fill on) | 70 | 284.2 | **191.2** | **626.8** | 717.6 | **~5** |

Fill-on idle is ~**12×** slower at the median than fill-off idle. Fill-on play is ~**23×** slower at the median than fill-off play.

A play p95 26 ms is already over a 16.6 ms budget. C play p95 **627 ms** is a multi-frame hitch every few actions (bake + water reflow + mesh apply stacked).

---

## Bake cost distribution

`_bake_one_chunk` breakdown (ms), only frames that actually baked:

| | B idle | C play |
|---|---:|---:|
| ops in 20 s | 65 | 70 |
| ops / frame (when sampled) | 1.07 (max 2) | **1.00** (max 1) |
| **one_chunk avg / p50 / p95 / max** | 92.0 / 88.5 / 117 / 130 | **102.7 / 87.5 / 148 / 171** |
| sample (noise columns) | 36.6 / 36.4 / 52.3 / 63.5 | 40.4 / 35.4 / 63.9 / 72.9 |
| mesh (`_build_mesh` + plan copy) | 34.9 / 33.9 / 39.7 / 55.4 | 43.7 / 35.2 / 68.6 / 73.8 |
| write (serialize + `.chk` rename) | 16.6 / 10.6 / 52.6 / 56.4 | 14.4 / 11.5 / 20.8 / 53.3 |
| `tick_background_fill` wall | 92.4 / 88.9 / 118 / 130 | 103.1 / 88.1 / 149 / 172 |
| `world_bake_fill` section | 92.6 / 89.0 / 118 / 130 | 103.3 / 88.2 / 149 / 172 |

Fill progressed 235 → 300 in B and 300 → 370 in C (**135 packages / 40 s**, ~3.4/s). That matches ~100 ms main-thread work at ~one package per displayed frame.

A `world_bake_fill` section: **0.03–0.04 ms** (null check only).

---

## Spikes attributable to `world_bake_fill`

Every B/C frame that baked has a **68–172 ms** `world_bake_fill` slice. That is the floor under those frames.

Additional C spikes are **not** bake alone:

| C play section | avg | p95 | max |
|---|---:|---:|---:|
| `world_bake_fill` | 103.3 | 148.8 | 171.9 |
| `voxel_fluid` | **137.0** | **436.2** | **481.1** |
| `chunk_manager` (includes fill) | 118.5 | 253.7 | 322.2 |
| `chunk_apply` | 14.6 | 133.4 | 179.5 |
| `chunk_upload` | 14.5 | 133.2 | 179.3 |
| `chunk_mesh` (worker) | 26.6 | 66.7 | 148.2 |
| `crystal_sim` | 2.2 | 4.8 | 6.7 |

Water reflow after rapid channel/dig **plus** a 100 ms bake on the same frame is what produces the 600 ms+ frames. Bake is the steady hitch; fluid+apply are the extra spikes while playing.

A play `voxel_fluid` was 0.11 ms avg / 4.0 ms max. Same water API, no fill.

---

## Terrain editing

Edits **succeed**. They are not blocked by `forbid_session_replace`. They are slower, and the following frame is still waiting on bake.

| | A play | C play |
|---|---:|---:|
| dig successes | 36 | 18 |
| dig call avg / p95 / max ms | 0.93 / 3.3 / 10.8 | **10.9 / 16.4 / 18.8** |
| build successes | 28 | 14 |
| build call avg / p95 / max ms | 1.71 / 7.0 / 11.5 | **22.9 / 30.9 / 31.0** |

Call latency stays under ~30 ms, so the editor itself is not wedged. Perceived responsiveness is the **frame** (~191 ms median, 627 ms p95): input is sampled less often and rebuilds share the main thread with fill.

---

## Streaming

| | A idle | A play | B idle | C play |
|---|---:|---:|---:|---:|
| `stream_schedule` avg / p95 / max | 1.0 / 5.5 / 52.7 | 0.87 / 4.9 / 50.7 | **7.9 / 72.7 / 76.4** | 0.03 / 0.04 / 0.06 |
| stream queue avg / max | 3.2 / 39 | 4.2 / 33 | **15.6 / 39** | 0 / 0 |
| mesh queue avg / max | 0.13 / 2 | 0.13 / 2 | 0.66 / 1 | 1.56 / 4 |

B still draining the start ring while filling: stream schedule p95 **73 ms** on top of ~90 ms bake. Fill did **not** skip for mesh-queue depth (`fill_skip_meshq_frames=0`; skip threshold is queue > 8).

Stream still applies packages (no empty start terrain). It is just late and hitchy.

---

## Water

Responsive enough to accept 12 channel edits in C. Not cheap.

| | A play | C play |
|---|---:|---:|
| `try_channel_water` avg / p95 / max ms | 1.93 / 7.9 / 15.3 | **28.6 / 33.4 / 37.4** |
| `voxel_fluid` section avg / p95 / max | 0.11 / 0.53 / 4.0 | **137 / 436 / 481** |

Immediate reflow (`recompute_region_now`) plus fill on the same frame is the worst interaction in this pass.

---

## Crystal

Simulation kept ticking. It is not the hitch.

| | A play | C play |
|---|---:|---:|
| `crystal_sim` avg / p95 / max | 0.45 / 3.0 / 9.5 | 2.19 / 4.8 / 6.7 |
| `crystal_manager` avg / max | 0.57 / 9.8 | 2.53 / 9.1 |
| `damage_spawn_at_world` call | 0.022 ms avg (0 hits) | 0.018 ms avg (0 hits) |

`damage_spawn_at_world(0,0)` missed because the origin spawn relocates to `(-10, 10)` (water). The call itself is microseconds. Crystal is **not** the fill problem.

---

## Travel to unbaked territory

Dedicated hops while fill was at ~372 / 16,384 packages, `valid=false`:

| dest | was unbaked | resident after | void-like | wait_ms | on-demand `_bake_one_chunk` µs |
|---|---|---|---|---:|---:|
| (9, 0) | yes | yes | no | 465 | 69,835 |
| (11, 0) | yes | yes | no | 504 | 73,589 |
| (13, 0) | yes | yes | no | 493 | 72,424 |
| (15, 0) | yes | yes | no | 559 | 70,229 |

Terrain for those chunks was generated through `_bake_one_chunk` / package apply, **not** `_generate_chunk`, and **not** presented as empty. On-demand bake is another **~70 ms** main-thread stall inside the stream request, then ~0.5 s until the view is resident (stream apply + competing fill).

---

## Comparison summary

| | A fill off | B fill, idle | C fill, playing |
|---|---|---|---|
| Playable | 11.7 s (warm index) | 12.3 s (partial) | same session |
| `valid` / fill | true / off | false / on | false / on |
| Typical frame | **8 ms** | **107 ms** | **191 ms** |
| Bake on main thread | none | **~92 ms × 1/frame** | **~103 ms × 1/frame** |
| Dig / build / water | yes, 1–2 ms calls | n/a | yes, 11–29 ms calls |
| Crystal sim | ~0.5 ms | ~0.4 ms | ~2.2 ms |
| Empty terrain | no | no | no (travel hops resident) |

---

## Recommended next action

Do **not** treat “1 chunk/frame and asynchronous from boot” as acceptable. The work is asynchronous from **startup**, not from the **frame**.

Highest-value next change (when requested; not done here):

1. **Move `_bake_one_chunk` off the main thread.** Sample + `_build_mesh` + serialize on a worker; main thread only commits the `.chk` (or a small apply). Keep the same package bytes and the same “index invalid until 16,384” rule.
2. Until that exists, **do not bake every frame.** Gate fill on spare budget (a few ms, not 200 ms), empty-ish stream/mesh queues, and optionally idle input. `min_units=0` already allows skip; the 200 ms wall and 1-unit-per-frame schedule still force a hitch whenever it runs.
3. Do **not** raise fill rate. Do **not** call `WorldState.replace_active` to speed bake.

Startup architecture can stay. The remaining problem is **main-thread occupancy during play**.

---

## Files touched for this profile (measurement only)

| File | Change |
|---|---|
| `world/world_bake_service.gd` | last_*_us / history / `last_bake_cost()` around existing bake body |
| `chunks/chunk_manager.gd` | `PerfProfiler` begin/end around `_tick_deferred_bake_fill` |
| `scripts/profile_deferred_fill_gameplay.gd` | windowed A / B / C / T harness |

No bake lifecycle, gameplay, world-gen, or visual changes.
