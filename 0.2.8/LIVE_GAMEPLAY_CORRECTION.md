# Live gameplay correction

**Date:** 2026-08-17  
**Stop line:** water architecture + live pass on ramps / terrain invalidation / building orientation. No ruin/town assets, no new gameplay.

Evidence: `scripts/display_gameplay_validation.gd` (windowed `main.tscn`), `scripts/display_water_correction.gd`, headless `verify_water_active_region.gd` / `verify_ramp_slope.gd`. Raw JSON and screenshots under the implementer scratch.

---

## 1. Water (priority 1)

### Why `_tick_water` gathered ~2482 + ~4626 cells

Not a loop-count problem. Every frame:

1. `has_water = not ChannelRegistry.all_fluid_positions().is_empty()` kept the sim awake if **any** overlay water existed.
2. `_load_water_subset` copied **every** water cell plus 4 neighbors into the engine.
3. Then `world.get_tile_type` ran on that whole set to inject river sources.
4. `is_cell_active` (chunk loaded) only skipped *flow*, not the gather.
5. Up to 3 gravity steps/frame multiplied the cost.

Live baseline (`LIVE_GAMEPLAY_VALIDATION.md`): `channel_cells=2482`, `subset=4626`, `_tick_water` **357 ms** (max 641), hottest `VoxelFluidService::_tick_water`.

### Contract now

Gameplay water is **edit-driven**:

| Path | What it loads |
|---|---|
| Idle (`_dirty_cells` empty) | Nothing. Sleep. `last_tick_us=0`. |
| `mark_region_dirty` / `recompute_region_now` | Dirty box + 4-neighbors of **registered** water only. |
| Natural river tile | Injected only if that cell is already dirty (interactive dig/channel). |
| Player walk / stream / bake fill | Does **not** dirty water. |

One gravity step per frame. `get_sim_diagnostics()` no longer walks the overlay.

### Before / after (running game)

| | Before | After (idle playable world) |
|---|---|---|
| `_tick_water` | 357 ms (max 641) | **0 µs**, sleeping 30/30 frames |
| Gather | 2482 channels + 4626 neighbors | subset **0** |
| `loads_all_channels_each_tick` | true | **false** |
| `active_gate` | `chunk_loaded` | **`dirty_region`** |

Headless local path (500 overlay channels, one dirty cell): idle **2–3 µs**; dirty gather subset **21** in **367–725 µs**; downhill reflow still moves water (`dest=0.930`).

A mid-iteration that woke on player chunk + injected every river tile re-created a 3k-cell dirty wave (186–288 ms). That wake is **removed**. Walking a marsh is not a reason to simulate the overlay.

---

## 2. Ramps

### Shared contract (not an offset)

- `dir` = toward the **low** neighbor. Wedge high end is local +X; `wedge_transform` yaws high toward `-dir`.
- Walk: `surface_height_on_ramp` decreases along `dir`. Verified for all four compass dirs (`verify_ramp_slope`).
- Cardinal emit sits on the **landing**. The wedge **spans** landing + approach. Inspector `MESH_HOLE` now treats that span as coverage.

### Why the 4-dir yard stamp failed

`rebuild_chunk` re-runs the column stage (bake/generate + overlays), wiping a raw `surface_map` mutation. `ChunkManager.ramp_placement_chance` (28) was also a second dice roll; the yard only set `TerrainRamps.placement_chance`. Async remesh raced structure rebuilds on the same chunk.

### Fix

- `remesh_resident_maps_at_world` + `ChunkData.preserve_column_maps` skips column regenerate (and mesh-plan cache).
- `_should_place_ramp` uses `TerrainRamps.should_place_ramp` (one dice).
- Structures rebuild first and go idle; **then** stamp all four approaches and remesh each chunk once.

### Live

All four yard landings `has_ramp=true`, `missing=[]`:

| Cell | dir | surface | walk |
|---|---|---|---|
| east (28,24) | (1,0) | 6 | 7 |
| west (31,24) | (from inspector) | 6 | 7 |
| south (34,24) | (0,1) | 6 | 7 |
| north (37,24) | (0,-1) | 6 | 7 |

F4: green agree, `mesh_cover true`. Gameplay slope rules unchanged.

---

## 3. Terrain-edit invalidation

Adversarial live sequence (dig, adjacent, slab, build, **chunk seam 32,24**, **chunk corner 32,32**, **next to a stamped ramp**):

Every edited cell `covered_after=true`; all four neighbors `covered=true`; no `MESH_HOLE`. Incremental clip + dirty halo already matched the shared column contract. No extra offsets.

---

## 4. Building orientation

`StructureOrientation.yaw_for` is the single gameplay yaw (EW run = 0, NS run = π/2). `WorldObject` and F4 read that same field.

Live: EW palisade pair `yaw=0`; NS stone pair `yaw=1.5708`. IDs 1:1. Gate passage / walls raise unchanged.

---

## 5. Collision

Not changed. Hybrid stands: `VoxelFloorProbe` heightfield for terrain/walls/ramps/bridges; gate is a gameplay passage; `WorldObject` `Area3D` is debug (`collision_layer=0`). Sample at walkable top + 0.2 is on the floor, not a wall volume.

---

## 6. Loading / bake

Start region **36/36** streamed before `INITIAL_STREAM_READY`. Loading labels counted 0→36 with live package occupancy. `GameplayInput.world_loading` blocked actions. Background bake may still fill (`not_full_world` vs playable −64..63); that is **not** start-region gameplay on the main thread.

---

## Files

- `fluids/voxel_fluid_service.gd` — dirty-region sleep; no world scan; no walk-wake.
- `scripts/verify_water_active_region.gd` + `run_all_verify.sh`.
- `helpers/terrain_ramps.gd`, `chunks/chunk_manager.gd`, `chunks/chunk_pipeline.gd`, `chunks/chunk_data.gd` — resident remesh + one placement dice.
- `world/validation_yard.gd`, `helpers/live_world_query.gd`, `scripts/display_gameplay_validation.gd`.
