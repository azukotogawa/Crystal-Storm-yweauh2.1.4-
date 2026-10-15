# Micro path callers (D-222 step 1)

Audit only. Mapped on `cs/pivot-0.4` on 2026-10-15. No behavior change. Source of truth is the scripts below, not the older design note that every generated cliff is a micro column.

The macro/micro split is rejected (D-222). This file is the caller map for the later flag (`USE_MICRO_BRICKS`), save collapse, and mesh drop. `voxel_scale`, sun, ortho size 16, and hammer timings stay locked and are not part of this path.

## What the micro path actually is

`CRYSTALSTORM_MICRO_TERRAIN` defaults on. `MicroLayerGrid.enabled` treats `0`, `false`, and `off` as off and anything else, including an empty value, as on. `VoxelWorld._ready` copies that into `ChunkData.s_micro_enabled_from_env` via `configure_micro_terrain_from_env`. Later env changes do not move that static until configure runs again. Tests flip it with `ChunkData.set_micro_enabled_for_benchmark` without touching the env cache inside `MicroLayerGrid`.

A micro brick is one column record (`MicroColumnBrick`: `surface_y`, `surface_tile`, `reason`, `dug_layers`). It is copied from the column maps that already include the overlay. It is not a finer voxel grid. `dug_layers` is written on dig and read only by `scripts/verify_macro_micro_save_migrate.gd`. Mesh code never reads `reason` or `dug_layers`.

Bricks are not saved. `systems/save_schema.gd` only states the contract: persist `height_delta` and `build_tile`; re-derive bricks on generate or rebuild. No function in that file calls the micro types.

## Edit kinds

`MicroLayerGrid.update_dirty_columns` picks one reason per column, in this order:

| Kind | Reason constant | When | What the mesh does with it |
| --- | --- | --- | --- |
| Build | `REASON_BUILD` (3) | Worker or live `build_tile >= 0`. Wins over dig and cliff. Includes `TerrainEdits.build_wall` (height +1 and a tile) and `set_build_tile_only` (tile, no height). | Column leaves the greedy merge. `emit_micro_column_mesh` then emits build strata, one top, and four sides. Strata still key off `height_delta`, so a tile-only mark does not stack extra faces. |
| Dig | `REASON_EDIT` (1) | No build tile, and height-delta layer count is not 0. `dug_layers` is `max(0, -layers)`, so a raise without a build tile is still EDIT with `dug_layers` 0. | Same isolation. `_emit_dug_strata_region` returns immediately. The pit is the lowered `surface_map` top plus neighbor side faces. |
| Cliff detail | `REASON_CLIFF` (2) | No build tile and no height delta, and some in-chunk 4-neighbor differs by at least `layer_height * 0.85` (`MicroCliffDetector.CLIFF_HEIGHT_RATIO`). | Same isolation: one-column top and sides so a cliff lip is not merged into a greedy slab. |
| None | `REASON_NONE` (0) | None of the above. An existing brick is evicted. | Column stays in the greedy mesh. |

Cliff seeds are not the whole chunk. `columns_needing_micro` adds the 8-neighbors of the cells already in the work list when those neighbors are cliffs. Untouched generated cliffs get no brick until an edit or a dirty column sits next to them.

Priority when a column qualifies for more than one kind: build, then dig (any non-zero height delta), then cliff.

## Who allocates bricks

Both writers end in `MicroLayerGrid.update_dirty_columns(..., include_cliff_edges=true)`, which also sets `MacroLayerGrid.FLAG_MICRO_PRESENT` through `sync_micro_flags`. Nothing in production reads that flag. Only the micro verify scripts call `has_micro_flag`.

1. Incremental edit. `ChunkData.update_dirty_column_maps` rebuilds the dirty columns from the baked base plus the frozen overlay, then calls `update_dirty_columns` on that same cell list. Caller: `ChunkPipeline.run_column_stage` when the job is not a full rebuild (`column_source` `dirty`).
2. Full derive. `ChunkData.derive_micro_from_terrain_edits` clears the grid, scans all 16×16 columns, and seeds any column with `build_tile >= 0` or `abs(height_delta) > 0.001`. Cliff neighbors of those seeds are added inside `update_dirty_columns`. Callers:
   - `ChunkManager._generate_chunk` after `_compute_column_maps`. Reached from `ChunkPipeline.run_column_stage` on a full rebuild when the bake does not apply, and from `world/mesh_plan_cache.gd` when a plan fill misses the bake.
   - `WorldBakeService._apply_pack_to_data` after it writes `surface_map` / `tile_map` from the package plus the overlay. Reached from `try_apply_base_to_chunk_data` (pipeline full rebuild and bake verifies), from `fill_mesh_plans_in_packages`, and from `world/world_bake_worker_job.gd`.

`ChunkPipeline.run_worker_job` is the worker entry: column stage, then mesh stage. `ChunkManager` queues it from `_chunk_mesh_task`. Headless scripts that call `run_worker_job` directly are listed under tests.

## Gameplay edits that reach the incremental path

These do not name micro. They write `WorldState` overlays, then `ChunkManager.invalidate_columns_at_world`, which queues a dirty column job. The next worker job is what allocates the brick.

Dig (`REASON_EDIT`, plus cliff neighbors):

- `TerrainEdits.dig` / `dig_cells` / `_dig_listed_cell`. Dig floor is `height_delta` −1, refused below −6.
- `TerrainEditor.try_dig`, `try_dig_brush`, `_brush_dig_cell` via `_remesh_cells`.
- `TerrainEditor.remesh_break_chunk` (used by `dig_cells`, `place_cells`, `remove_structure_cells`).
- `TerrainEditor._channel_dig` calls `TerrainEdits.dig` and then `_invalidate_and_rebuild`.
- Water-source dig in `try_dig` goes through `_replace_cell_with_water_block` and the same invalidate. That is a tile replace, not a height dig. It allocates a brick only if the overlay then matches build, height, or cliff.
- `LivingForce` settle columns are appended onto the dig remesh list.
- `TerrainEditor._living_push_tick` remeshes columns the crystal push breaks (`terrain_edited` kind `remove`).

Build (`REASON_BUILD`, plus cliff neighbors):

- `TerrainEdits.build_wall`, `set_build_tile_only`, `place_cells`, `unstack_build`, `remove_structure_cells`.
- `TerrainEditor.try_build`, `try_build_wall`, `try_build_gate`, `try_build_bridge`, `try_place_blueprint`, `try_repair_structure`, `try_fill`, `try_remove`.
- `try_place_cardinal_ramp` and `try_place_corner_ramp` invalidate the same way. Ramp columns are not a fourth brick reason. A ramp brick appears only when that column also has a build tile, a height delta, or a cliff.
- `try_plant` invalidates. A plant is a feature tile, not `build_tile` or `height_delta`, so it gets a brick only when that column is already a cliff or already has an overlay.

Channel water that is not a dig:

- `_channel_raise` and `_channel_lower` change channel water level, not `height_delta`, then invalidate. A brick appears only if an overlay or a cliff already qualifies. `_channel_lower` can also clear the channel and its tile override.
- `_channel_redirect` only changes flow direction when the cell is already a channel. If it is not, it falls through to `_channel_dig` first.

Other invalidate callers (not an edit kind, but they run the same dirty micro update):

- `fluids/voxel_fluid_service.gd` `invalidate_columns_at_world`.
- `scripts/playtest_phase_profile.gd` and `scripts/_fullpass_030_window.gd` (untracked; not part of this change).

`InfiniteNoiseWorld.invalidate_column_cache` runs beside these edits. That drops the noise-height cache so `get_surface_height` adds the new `height_delta`. It does not touch bricks.

## Who reads bricks

Mesh, the only production consumer:

- `ChunkManager._build_mesh_region` (full and patch). If `_mesh_defer_micro_columns` (default true) and micro is enabled, `MicroTerrainMeshCompositor.build_skip_set` records brick columns in the rect on `data._mesh_job_micro_skip`.
- Greedy tops, sides, build strata, and water-skip use `_skips_greedy_surface_cell`, which returns true for those columns. In-chunk heights still come from `surface_map` via `_surface_y_at`, not from the brick.
- After greedy, the skip dict is cleared and `MicroTerrainMeshCompositor.compose` emits each skipped column through `emit_micro_column_mesh`: dug strata (no-op), build strata, one top quad, four side walls.
- `ChunkManager._build_micro_mesh_region` does the same compose and has no callers in `.gd`. The live path is `_build_mesh_region`.

Surface queries that prefer a brick over `surface_map` / macro:

- `ChunkData.get_surface_y` and `ChunkData.get_tile_type`.
- `MicroCliffDetector._is_cliff_column` calls `get_surface_y` while classifying, so a brick from an earlier pass can affect the next cliff test.
- `ChunkManager._surface_y_at` / `_tile_type_at` call those only for coordinates outside the chunk. In-chunk mesh reads `surface_map` / `tile_map`.
- `helpers/terrain_vertex_ao.gd` `sample_surface` calls `get_surface_y` when the halo sample is missing. Used by `helpers/chunk_surface_mesh_builder.gd` and `helpers/terrain_lighting.gd`.

`ChunkData.has_micro_brick` is the test probe. Production gameplay does not call it.

## Files in the queue list

| File | Role on the micro path |
| --- | --- |
| `helpers/micro_layer_grid.gd` | Brick store, reason rules, derive, flag sync. |
| `helpers/micro_column_brick.gd` | One column record. Only the grid constructs it. |
| `helpers/micro_cliff_detector.gd` | Cliff test and neighbor expansion. Only the grid calls it, plus `verify_micro_column_mesh_parity.gd`. |
| `helpers/micro_terrain_mesh_compositor.gd` | Skip set and per-column quads. Only `ChunkManager` preloads it. |
| `helpers/micro_terrain_perf_gate.gd` | Median budget helper. Only `verify_micro_terrain_perf.gd` calls it. No runtime caller. |
| `helpers/macro_layer_grid.gd` | `FLAG_MICRO_PRESENT` plus `set_micro_flag` / `has_micro_flag`. Written by the micro grid. Not read by mesh. |
| `chunks/chunk_data.gd` | Enable flag, acquire/reuse grid, derive, dirty update, `get_surface_y` / `get_tile_type` override. |
| `chunks/chunk_manager.gd` | Generate-time derive, mesh skip, compositor. `_build_micro_mesh_region` is unused. |
| `chunks/voxel_world.gd` | One call: `configure_micro_terrain_from_env` in `_ready`. |
| `chunks/chunk_pipeline.gd` | Not in the queue list, but it is the caller that turns dirty jobs into `update_dirty_column_maps` and full jobs into bake or `_generate_chunk`. |
| `player/voxel_floor_probe.gd` | Does not call the micro path. Feet use `InfiniteNoiseWorld.get_surface_height` / `get_tile_type`. The word "micro" at the ground-follow comment is a small vertical delta, not a brick. |
| `systems/save_schema.gd` | Contract comment only. Export keys are `height_delta` and `build_tile`. No brick field. |
| `world/InfiniteNoiseWorld.gd` | Does not call the micro path. `get_surface_height` is quantized noise plus `TerrainEdits.get_height_delta`. Locals named `micro` and `micro_var` are a height octave and a biome name split. |
| `world/world_bake_service.gd` | `_apply_pack_to_data` calls `derive_micro_from_terrain_edits` after composing the column. |
| `world/terrain_edits.gd` | Writes the overlays the reasons read. Does not mention micro. |
| `world/terrain_editor.gd` | Remesh entry for dig, build, ramp, channel, remove, crystal push. Does not mention micro. |
| `world/mesh_plan_cache.gd` | Plan fill calls `_generate_chunk` or `try_apply_base_to_chunk_data`, both of which derive. |
| `world/world_bake_worker_job.gd` | Calls `_apply_pack_to_data`, which derives. |

Collision, water sim, crystal queries, vegetation, towns, ruins, the map, and the action target all use `InfiniteNoiseWorld.get_surface_height` or `get_tile_type`. They see dig and build through `height_delta` / `build_tile`, not through bricks. Turning micro off does not by itself change those queries. It changes which columns are pulled out of the greedy mesh, `get_surface_y` / `get_tile_type` on `ChunkData` when a brick existed, and the tests that require a brick.

## Tests that lock the micro path

Do not delete these. Later steps drop them from run lists or gate them.

| Script | What it requires |
| --- | --- |
| `scripts/verify_micro_layer_grid.gd` | Env on. Dig allocates a brick and `FLAG_MICRO_PRESENT`. An untouched column does not. |
| `scripts/verify_macro_micro_save_migrate.gd` | Dig brick is absent from the save payload. v1 load re-derives `dug_layers >= 1` and the flag. |
| `scripts/verify_micro_column_mesh_parity.gd` | Dig and cliff columns get bricks. Mesh parity with micro forced on and off. |
| `scripts/verify_micro_terrain_perf.gd` | `MicroTerrainPerfGate` on a localized edit. |
| `scripts/verify_dug_strata_no_cap.gd` | With the benchmark flag on, derive allocates a brick. Also runs a micro-off case. |
| `scripts/verify_terrain_loop_complete.gd` | After `dig` plus `update_dirty_column_maps`, `has_micro_brick(3, 3)`. |
| `scripts/verify_world_state_stale_worker.gd` | Frozen overlay helpers, then derive. |
| `scripts/verify_chunk_pipeline.gd` | Worker job clears `_mesh_job_micro_skip` and must not keep the old manager-global skip fields. |
| `scripts/verify_macro_layer_grid.gd` | Dirty column maps. Compares macro height, not a brick. |
| `scripts/verify_macro_terrain_perf.gd` | Forces micro off around its own timing. |
| `scripts/verify_bake_runtime_isolation.gd` | Calls `update_dirty_column_maps` and `run_worker_job`. |
| `scripts/verify_chunk_surface_zero.gd`, `scripts/verify_chunk_atlas.gd`, `scripts/smoke_probe_helpers.gd`, `scripts/display_session_probe.gd` | Call `ChunkData.get_surface_y`, so they read a brick when one exists. |

## Not on this path

- Player stand height (`voxel_floor_probe.gd`).
- Save bytes (`save_schema.gd` functions).
- World generation noise (`InfiniteNoiseWorld.gd`).
- `MicroTerrainPerfGate` outside its verify script.
- `ChunkManager._build_micro_mesh_region` (no caller).
- `MacroLayerGrid.has_micro_flag` outside the two verify scripts.

## Next step (not this task)

Queue step 2: flag `USE_MICRO_BRICKS` off so dig and build write whole blocks only and the compositor is skipped, then run the ramp, water, and terrain verifies. This map says the flag has to gate `ChunkData.is_micro_terrain_enabled` (the value `update_dirty_column_maps`, `derive_micro_from_terrain_edits`, `get_surface_y`, and `_build_mesh_region` already consult). `VoxelWorld._ready` is the boot copy. Save files need no brick migration until a payload actually contains bricks, which the current schema does not write.
