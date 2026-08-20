# Deferred world bake — architecture (no implementation)

**Status:** proposal only. Do not implement until this lifecycle is accepted.  
**Date:** 2026-08-15  
**Constraint:** remove the full 16,384-chunk bake from the path to `INITIAL_STREAM_READY` without shrinking the world, lowering quality, or treating an unfinished map as a valid bake.

Measured cold playable: **2,211.6 s**. Warm valid index: **17.7 s**.  
Dominant cold work: `_build_mesh` 905.9 s, height/tile sample 818.1 s, `.chk` writes 283.2 s. All of that runs **on the main thread** inside `WorldBakeService.bake_world_async` **before** CompositionRoot will mark the game playable.

---

## 1. Current lifecycle

```
main._ready
  → CompositionRoot.boot_async
      CONFIGURED / QUALITY_APPLIED
      FEATURES_SEEDED
        WorldFeatures.bootstrap_with_services
          towns / ruins / entity spawn stamps  (WorldState)
          skip runtime veg scatter if bake-on-new
      CHUNKS_CREATED
        VoxelWorld.create_chunk_manager_with_services
          await ChunkManager.bootstrap_world_bake_async
            await WorldBakeService.bootstrap_for_world_async
              load_bake_for_seed
                success + validate_loaded_bake.ok → mode=loaded   (~1 s)
                miss / invalid → bake_world_async                 (~36 min)
                  _bake_vegetation_by_chunk (12k attempts, ~2 s)
                  WorldState.replace_active()   # empty overlay session
                  for each of 16384 coords:     # MAIN THREAD
                    noise sample 256 columns
                    ChunkData + capture_worker_snapshot
                    mesh_host._build_mesh
                    _write_chunk_package
                    await process_frame every 4
                  restore WorldState
                  save_bake() → world.index     # only now valid=true
            _bootstrap_mesh_plan_cache
            _request_initial_stream             # player RD ring
      wait until cm.chunks.size() >= 1
      INITIAL_STREAM_READY   ★ playable / loading fade
      VISUALS_COMMITTED / RUNNING
```

`valid` is a single boolean. It is set **only** by `load_index` / end of a complete `bake_world*`. Almost every bake consumer keys off it:

| API | When `valid == false` | When `valid == true` |
|---|---|---|
| `try_apply_base_to_chunk_data` | refuse (stream falls through) | load package + apply base |
| `ensure_chunk_resident` | **refuse even if `.chk` exists** | read `.chk` into RAM + install veg |
| `should_block_procedural_generate` | allow `_generate_chunk` | block generate for all in-bounds coords |
| `has_chunk` / `covers_world_cell` | no | index rectangle |
| `validate_loaded_bake` | `index_not_valid` | require full 128×128 + veg + sample packages |
| `save_bake` | refuse | write `world.index` claiming `expected_chunk_count()` |

Package format (unchanged target):

```
user://world_bakes/v4_s{seed}_full/
  world.index          # CSWI + version/seed/bounds/flags/count/checksum
  chunks/cx_cz.chk     # columns + mesh plan + vegetation
  static_meta.json
```

Runtime stream (`ChunkPipeline.run_column_stage`) prefers bake apply; if that fails and `should_block_procedural_generate` is false, it calls `ChunkManager._generate_chunk` → `ChunkData._compute_column_maps` (same seed noise). Mesh is rebuilt on the worker either way. Vegetation for baked worlds is **not** scattered at feature seed; it is installed when a package becomes resident.

CompositionRoot playable gate is **≥1 resident `ChunkView`**, not “bake finished”. The bake is only on the critical path because `create_chunk_manager_with_services` **awaits the entire rebuild**.

Crystal waits `spawn_area_ready(0, 0)` (origin chunk). The player spawns ~44–64 columns from the origin boss, so the first stream ring is around the **player**, not the origin. Both neighborhoods matter.

---

## 2. Proposed lifecycle

Keep the v4 package format. Split **“this chunk’s package exists”** from **“the world index is complete.”** Never write `world.index` until every expected `.chk` is on disk.

```
BOOT
  features seed (unchanged)
  WorldBakeService.prepare_session(seed, full bounds)
    package_dir = v4_s{seed}_full
    valid = false
    if world.index present and validate_loaded_bake.ok:
        mode = loaded          # today’s warm path
    else:
        resume any existing .chk (do not delete)
        run world-wide veg scatter once (in-memory map, ~2 s)
        prime_region(player RD ∪ origin 3×3)
          _bake_one_chunk per missing coord  # SAME writer as today
        mode = partial
  request_initial_stream
  wait ≥1 resident chunk  (packages already on disk → apply, not generate)
  INITIAL_STREAM_READY ★ playable
  VISUALS / RUNNING
  background_fill (not awaited)
    for remaining coords, skip existing .chk
      budgeted _bake_one_chunk
    when count == expected:
      save_bake() → world.index
      valid = true
```

Warm path is unchanged: index load, `valid = true`, stream as today.

### Smallest design change

Do **not** invent a second terrain representation and do **not** mark a partial bake `valid`.

Extract the existing loop body into `_bake_one_chunk(coord, veg_bucket)`:

1. Sample 256 columns via `get_surface_height_worker` / `get_tile_type_worker` (base noise only).
2. Build a **base-only** `ChunkData` (empty overlay snapshot — see hazards).
3. `mesh_host._build_mesh`.
4. `_write_chunk_package` (same bytes as today).

Then add three session flags on `WorldBakeService`:

| Flag | Meaning |
|---|---|
| `valid` | Full index on disk. **Unchanged semantics.** |
| `bake_in_progress` | Background fill running. |
| `package_ready(coord)` | `.chk` exists (or resident), independent of `valid`. |

Consumer rule:

```
if package_ready(coord):
    apply package          # never generate
elif valid:
    block generate         # missing file = corrupt; do not invent terrain
elif bake_in_progress:
    on-demand _bake_one_chunk(coord) then apply
else:
    _generate_chunk        # bake disabled / tests
```

On-demand bake is the same function as background fill, so a player who walks off the primed ring gets **complete** terrain for that chunk, not a stub, and the file is written so the later fill skips it.

Primed set (cold, production defaults):

- Player stream rectangle: `RENDER_DISTANCE` uses `for z in cz-RD .. cz+RD+1` → typically **8×8 = 64** chunks (matches the cold profile `chunks_ready=64`).
- Origin 3×3 so `CrystalManager.spawn_area_ready(0,0)` and the first crystal mesh have packages.

At ~133 ms/chunk (measured), 64–73 packages ≈ **8–10 s** on this machine, plus ~8 s scene load and ~2 s veg scatter → cold playable on the order of **warm**, not 37 minutes. Remaining ~16,300 packages fill in the background.

### What stays on the critical path

- Feature seed (already ~2 s).
- One vegetation scatter map for the **full** playable rectangle (already ~2 s). Neighborhood packages need their veg buckets; keeping one deterministic 12k-attempt map preserves today’s plant set.
- Prime write of the start ring only.
- First stream apply (already sub-second once packages exist).

### What leaves the critical path

- The other ~16,300 `_build_mesh` + sample + write iterations.
- `save_bake` size-sum of all packages.
- Post-bake `ensure_mesh_plans` stamp refresh (stream already applies live WorldState town/ruin overlays).

---

## 3. Dependency hazards

**`ensure_chunk_resident` / `try_apply_base_to_chunk_data` require `valid`.**  
Partial `.chk` files are invisible to streaming today. This is the first code change. Both must accept `package_ready(coord)` while `valid` is still false.

**`should_block_procedural_generate` is `valid && coord_in_package`.**  
If we set `valid=true` early, every unbaked in-bounds coord is **blocked** → empty `column_source=blocked` (holes). That is exactly “fake completion.” Leave `valid=false` until the index is real.

**`WorldState.replace_active()` during `bake_world_async`.**  
Today the bake swaps in an empty overlay session so `capture_worker_snapshot` does not bake player/town edits into packages. Doing that **while the player is in-game wipes live WorldState**. Background / on-demand bake must **not** call `replace_active`. It must build base-only snapshots without touching the active session.

**Vegetation.**  
Feature seed skips scatter when bake-on-new. Plants appear only from package install. The primed ring **must** be written with veg payloads. Background must use the **same** scatter map (or the same seed+attempts+bounds function) so plants do not jump when a far chunk is first visited via on-demand vs later fill. Do not `apply_baked_vegetation_chunk` onto the **live** FeatureRegistry during background write — install only when the chunk becomes stream-resident (today’s `_install_resident_vegetation`).

**Town/ruin stamps.**  
Seeded before bake into live WorldState. Packages are base + veg only. Stream compose already applies overlays. Safe.

**Player vs origin.**  
Priming only the player ring leaves crystal’s origin chunk on the generate/on-demand path. Include origin.

**Walk-off during fill.**  
On-demand `_bake_one_chunk` can cost ~100–150 ms on the main thread. Acceptable as a rare hitch; better than empty terrain or a second algorithm. Do not stall the stream forever waiting for a distant background cursor.

**`force_rebuild_next` (loading “Rebuild World”).**  
Still a full rebuild, but neighborhood-first + background. Do not await completion for playable.

**Crystal / living world / spatial index.**  
They consume streamed chunks and WorldState, not `valid`. They start as soon as origin/player chunks exist.

**MeshPlanCache monolith.**  
Production plans live inside `.chk`. Do not resurrect monolith bake-on-new.

---

## 4. Save / index hazards

Save/load (`SaveGameService`) persists **WorldState + runtime** (edits, features, crystal, player). It does **not** persist bake packages. Load applies overlays then `rebuild_chunks`.

| Situation | Required behavior |
|---|---|
| Save during `bake_in_progress` | Allowed. Payload unchanged. |
| Load during `bake_in_progress` | Rebuild uses `package_ready` / on-demand bake. Do not require `valid`. |
| Quit mid-fill (no `world.index`) | Same files as today’s interrupted bake. **Next boot must resume**, not wipe 16k packages. |
| Premature `world.index` | `validate_loaded_bake` samples corners; missing files → invalid → **full rebuild**. Never write the index until `chunk file count == expected`. |
| Index written, file missing | `valid=true` + `should_block` → hole. Treat as corrupt; do not generate. |
| Player edits during fill | Edits stay in WorldState. Bake continues to write **base only**. Unchanged contract. |

Resume algorithm (replaces today’s “no index ⇒ rebuild all”):

1. Set `package_dir` for seed/full.
2. Inventory `chunks/*.chk` (filename parse `cx_cz`).
3. Prime missing start-ring coords.
4. Stream.
5. Background-fill the rest.
6. Write `world.index` only at the end.

`CRYSTALSTORM_BAKE_ON_NEW=0` (tests) still means “do not start a fill.” Smoke radius tests already set `CRYSTALSTORM_BAKE_RADIUS`; their entire world is the prime set.

---

## 5. Thread-safety

`bake_world_async` is **not** a worker job. It is cooperative main-thread work (`await process_frame`). `_build_mesh` uses `ChunkManager` emit helpers. `FileAccess` is not thread-safe with concurrent main-thread `ensure_chunk_resident` reads of the same path.

Recommended for v1 (smallest):

- Keep `_bake_one_chunk` on the **main thread**.
- Drain via `FrameBudgetScheduler` (existing `world_rebuild` is only 1.5 ms / 4 units — **too small** for a 133 ms chunk). Add a dedicated `world_bake_fill` system: **max 1 chunk per frame**, no `min_units` pile-up, pause when stream apply queue is deep or save is running.
- Mutex a `Dictionary` of in-flight coords so on-demand and background cannot write the same `.chk` twice.
- Write to `cx_cz.chk.tmp` then rename, so a concurrent read never sees a half file.
- Do **not** put this on `WorkerThreadPool` in the first change. Reusing `ChunkPipeline.run_worker_job` for package production is a later optional step (better hitches, more surface area).

WorldState: background bake must not read or write the live session. Snapshot for mesh is empty overlays + sampled base arrays only.

---

## 6. Files / functions likely to change

| File | Change |
|---|---|
| `world/world_bake_service.gd` | Extract `_bake_one_chunk`; add `package_ready`, `prime_region`, `start_background_fill`, `await_fill_complete` (tests); stop `replace_active` on live fill; `ensure_chunk_resident` / `try_apply_base` without requiring `valid`; resume inventory; atomic writes; write `save_bake` only at completion |
| `chunks/chunk_pipeline.gd` | Column stage: apply if `package_ready`; on-demand bake hook; block generate only if `valid` or package exists |
| `chunks/chunk_manager.gd` | `bootstrap_world_bake_async`: prime + stream, do not await fill; queue far stream requests that need on-demand bake |
| `chunks/voxel_world.gd` | Unchanged aside from still awaiting bootstrap (which becomes short) |
| `systems/composition_root.gd` | Keep `chunks.size() >= 1` gate; do not wait on fill. Optional: wait for primed ring instead of 1 chunk |
| `systems/frame_budget_scheduler.gd` | New `world_bake_fill` budget (1 unit / frame) |
| `world/world_features.gd` | Unchanged skip-scatter rule; fill still supplies packages |
| `ui/loading_screen.gd` | Copy only: nearby ready vs “rest of world generating” after fade (must not block fade) |
| `systems/save_game_service.gd` | Likely none; document load-during-fill |
| `scripts/verify_world_bake.gd` and full/streamed bake verifies | Await `await_fill_complete` or assert prime+resume instead of “bootstrap ⇒ index exists” |
| `scripts/verify_bake_runtime_isolation.gd` | Isolation (`blocked_generate == 0`) only after `valid` |

No change to `.chk` / `world.index` binary layout.

---

## 7. Rollback

Env flag, default **on** for production after soak:

```
CRYSTALSTORM_BAKE_DEFER_FILL=0   # old: await full bake_world_async before stream
```

When off, `bootstrap_for_world_async` is today’s function. Package format unchanged, so a half-filled directory + no index is the same recoverable state as an interrupted bake today (resume path) or the old wipe-and-rebuild if the flag is off.

Git rollback is one commit. No save-schema migration.

---

## 8. Verification strategy

Must pass existing bake isolation **after** fill completes.

New / extended probes (headless):

1. **Prime latency** — cold, no index: time to `INITIAL_STREAM_READY` < ~30 s on the profile machine; `valid == false`; start-ring `.chk` present; `world.index` absent.
2. **No holes** — after playable, player chunk and origin have `column_source=bake` (or on-demand bake), never `blocked`, never empty maps.
3. **Determinism** — package bytes for coord C written during prime equal bytes for C written by a full old bake (same seed, empty overlays). Spot-check origin + one player chunk.
4. **Resume** — kill fill at N packages, relaunch: no wipe; playable from existing ring; fill continues; index appears only at 16,384.
5. **Walk-off** — request a far unbaked coord: on-demand writes `.chk`, stream applies, no generate-vs-bake flicker.
6. **Edit during fill** — dig in primed chunk; fill continues; reload save; height_delta still applied on baked base.
7. **Warm** — with valid index, path identical to today (~tens of seconds, no fill).
8. **Suite** — `verify_world_bake`, `verify_full_world_bake`, `verify_streamed_world_bake`, `verify_world_state_stale_worker`, `verify_save_transaction`, `verify_composition_boot`, smoke. Full-world verifies must `await_fill_complete` or use radius-2 (entire world = prime set).

Do not claim playable until a human can move on the start ring while the debug HUD still shows fill progress.

---

## 9. Explicit non-goals (this change)

- Faster `_build_mesh` or cheaper noise.
- Smaller playable map / lower `RENDER_DISTANCE`.
- Worker-thread bake (follow-up).
- Writing a “valid” index for a partial world.
- Runtime `_generate_chunk` as a stand-in for missing packages in production (veg + isolation would diverge).

---

## 10. Decision

The smallest architectural change is:

**Treat `.chk` files as an incrementally completable cache, and `world.index` as the completion certificate.** Prime the start neighborhood with the existing writer, become playable, fill the rest under a frame budget, certify only at the end.

That removes 98% of cold-start wall time from the playable gate without a second world generator and without lying about bake validity.
