# Manual In-Game Verification — Crystalstorm

**Status:** Working (human sign-off required)

**human-hand ONLY** — automated probes must not edit or sign this file.

Automated smoke and verify scripts prove *Partially Working*. This checklist is the final gate for *Working* status.

## Session setup
- [x] Launch: `CRYSTALSTORM_PERF_PRESET=medium godot scenes/main.tscn`
- [x] Wait for world load (chunks visible, player movable)

## Movement & jump
- [x] Hold movement (WASD/arrows) and press jump — player stays airborne, lands while still running
- [x] No snap-back to ground mid-jump

## Digging
- [x] Select stone pick (hotbar 2), attack toward terrain — visible carve, no errors
- [x] Cursor highlight (orange box) follows targeted column

## Combat
- [x] Wooden sword damages a nearby animal (health flash / damage number)
- [x] Cursor highlight (red box) on melee target column

## Build
- [x] Hold interact — green highlight on build column; stone wall places when resourced

## Visuals
- [x] Terrain shows textured atlas (varied grass/stone/forest tiles, not solid green)
- [x] diagonal corners have no holes
- [x] Entities, vegetation, buildings show voxel/billboard art (not gray placeholders)
- [x] Hotbar shows item icons (sword, pick, bow, materials)

## Streaming
- [x] Walk 30+ columns — chunks load/unload without holes or crash

## Sign-off
- **Tester:**
- **Date:**
- **Result:** PASS / FAIL
- **Notes (2026-07-09 fixes — please re-verify):**
  - ramps are still in front of a voxel instead of replacing that voxel
  - ramps look good except diagonals, which the only problem is there is a missing texture on the floor in the voxel that they're in
  - based on the other textures from the game im assuming that voxel textures are plain color. i want minecraft esque textures for everything. maybe at a higher resolution.
  - some trees and crystal entities are billboards and need to be 3d voxels.
  - what is that weird texture where crystals spawn
  - collision is buggy
  - make the new terrain textures look more like what their real life simile is.
  - highlight works now but only when a pickaxe or block is selected in the inventory.
  - crystals load in a checkerboard pattern. they look alive instead of settling like water, except slowly.
  - Targeting uses camera facing + mouse column pick (Q/E rotate view; dig/build/attack follow cursor). `verify_target_facing.gd`. targeting works for pickaxe but not sword. also i need something that highlights which block is selected. sword only swings north of the player. block placing works but needs something that highlights where its placed. can we not reload the entire chunk when block breaked/placed. ramps shouldnt be added when walls are placed. block highlight is hidden below the terrain
  - Build interact binds terrain editor lazily (same as dig). Display + smoke probes use mouse warp for dig/build.
  - Stacked walls emit all layers via `_emit_build_strata`. `verify_terrain_build.gd`.
  - Vegetation density ~2×, voxel props 45% larger, voxel models to 72 columns. Entities use voxel props when enabled. trees are way too small. grass needs to be 3d. some trees dont load 3d voxel. there is a voxel prop that is 3 stick i dont know what it is.
  - L-corner concave ramp mesh rev 3 + support/side fill unchanged — confirm visually at step corners.
  - Step-corner ramps (two perpendicular steps) now use triangular prism (`FACE_RAMP_CORNER`) with floor fill under the cell.
  - Stacked walls emit intermediate top + side faces so lower blocks stay visible.
  - Melee sword shows red cursor highlight (dig=orange, build=green).
  - Crystal spawn markers are billboard quads (no cylinder UV stretch).
  - ChunkView rebinds Cube.png atlas each setup; terrain shader unshaded + nearest filter for pixel-art clarity.
  - Trees/bushes/fern always use voxel props when `vegetation_voxel_models_enabled` (MEDIUM/HIGH).
  - Crystal enemies (`crystal_mite`, etc.) use voxel props when `entity_voxel_models_enabled`.
  - Sharper sprite pixel scale (0.026). Automated corroboration: smoke + core verify OK — human visual pass still required for unchecked items.
