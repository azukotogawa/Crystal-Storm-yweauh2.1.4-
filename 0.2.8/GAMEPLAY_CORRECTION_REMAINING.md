# Gameplay-correction pass — remaining discrepancies

**Stop line:** report leftovers. No further automatic work.  
**Evidence:** windowed `scenes/main.tscn` via `scripts/display_terrain_agreement.gd` (camera snapped, yard on dry steppe at origin (36,8)). F4 is source of truth. 61 FPS, `main 6.7 ms`.

## What this pass proved

| Item | Live camera + F4 | Regression |
|---|---|---|
| Building identity | Wood palisade, stone masonry, stone cube, wooden gate arch, bridge deck are distinct WorldObject meshes | `verify_building_orientation.gd`: EW yaw 0, NS π/2, `WorldObject.Mesh.rotation.y` matches |
| Building pin | Stone wall `(38,11)`: green agree, visual `stone_wall`, Δh +2, walk 12, highlight on the masonry | — |
| Gate | Visible arch; F4 `passage` on the gate cell; not a raised volume | existing gate identity verifies |
| Terrain after dig | `(44,14)` and neighbors stay covered; no slab vanish in the camera | incremental clip already in `verify_chunk_incremental_*` |
| Water during this yard | F3 61 FPS / 6.7 ms; water sleep except a 0.75 ms local tick | `verify_water_active_region.gd` |
| Cardinal emit (isolated maps) | — | `verify_ramp_landing.gd`: FACE_RAMP on landing, correct dir, all 4 compass dirs when surround is flat |

Previous screenshots were **invalid**: the iso camera lerps, so every shot was origin river. Harness now snaps `follow_target` and zoom.

## Remaining discrepancies (do not treat as fixed)

### 1. Ramp visual vs ramp_map — **fixed 2026-08-21**

Cause: `_sample_height` preferred stale in-chunk halo over patched `surface_map`, so preserve remesh never saw the stamped step. Halo interior is now ignored for in-chunk samples; preserve remesh refreshes halo from maps; yard stamps use `patch_local_column`.

Walk uses `ramp_map`, rebuilt from the quads the terrain mesh draws (model A: one-cell landing wedge and a triangle corner cap). Interior samples use the resident surface map; the halo is only the neighbor ring.

The yard stamp writes an isolated one-layer step so a cliff or corner surround still becomes a cardinal. Resident remesh snapshots the stamped maps and copies loaded neighbor surfaces into the halo border. `verify_ramp_landing.gd` covers the cross-chunk halo case, the isolated yard step, and the no-V valley. `verify_ramp_resident_mesh.gd` checks all four compass stamps after rebuild.

### 2. Camera vs pin (harness)

Some PNG names (`ta_wood_wall_…`) showed F4 pinned to a nearby ramp from the previous frame. The pin write invalidated the panel and waited for a later `_process`, and `get_texture()` at `process_frame` time is still the previous draw. The inspector now refreshes the label when the pin changes, and `display_terrain_agreement.gd` waits one more frame plus `frame_post_draw` before saving the PNG. No new windowed photo was taken in that change.

### 3. Collision model (unchanged, by design)

`is_colliding_at(walkable_top + 0.2)` is false on walls and gates. The probe is a **floor**. Walls block by failed step-up from the low neighbor. Gate is a gameplay passage. WorldObject `Area3D` is debug (`collision_layer=0`). Visible volume ≠ physics body.

### 4. Opposite terrain faces

Raised wall columns list both POS and NEG side codes (`[0,6,4,3,4,5,6]`). That is a raised box, not a winding bug. No live photo showed a single slab with inverted face textures after the earlier Y-down greedy removal.

## Do not do next without a new brief

- Do not add per-voxel bodies or authored assets.
- Do not treat `verify_ramp_landing` as camera proof of live wedges.
- Do not treat `verify_ramp_resident_mesh.gd` as a substitute for a windowed F4 photo of `(49,8)`.
