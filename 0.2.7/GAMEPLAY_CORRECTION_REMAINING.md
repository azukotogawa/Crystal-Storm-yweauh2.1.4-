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

### 1. Ramp visual vs ramp_map (P0 leftover)

Yard stamps on dry land `(40,8)`…`(49,8)`:

| Cell | has_ramp | walk vs surf | FACE_RAMP in column quads | chunk `ramp_count` |
|---|---|---|---|---|
| east `(40,8)` | **false** | 8 vs 6 (no slope) | — | 11 |
| west `(43,8)` | true | 7 vs 6 | **no** (`RAMP_VISUAL`) | 11 |
| south `(46,8)` | true | 7 vs 6 | **no** | 11 |
| north `(49,8)` | true | 7 vs 6 | **no** | **0** |

Walk uses `ramp_map`. The uploaded column quads for those landings are FACE_TOP only. North’s chunk has **zero** ramp MultiMesh instances — walkable slope with no wedge. East never became a ramp (surround heights were not a single isolated step).

Headless `_build_mesh` on a flat 10 / approach 8 map **does** emit FACE_RAMP. The live miss was the **resident remesh / surface-mesh payload** path, not the emit math.

**Remesh path (headless, not a new camera pass):** a chunk-edge step stayed hidden because `_sample_height` prefers the halo, and the halo border was still the pre-stamp world-gen height. A same-chunk yard stamp could also lose the race to an in-flight column regen: the follow-up was recorded without `preserve_maps`, or the token bump left `pending` set so the preserve remesh never ran. Resident remesh now snapshots the stamped maps, copies loaded neighbor surfaces into the halo border, and uploads that mesh. `verify_ramp_resident_mesh.gd` (main scene, four compass stamps) reports `column_source=resident` and one `FACE_RAMP` quad per landing. `verify_ramp_landing.gd` covers the cross-chunk halo case. The F4 photos above are still the last camera evidence; this does not replace them.

### 2. Camera vs pin (harness)

Some PNG names (`ta_wood_wall_…`) still show F4 pinned to a nearby ramp from the previous frame. Snap is better than lerp; one extra settle frame is still needed for a 1:1 filename↔cell photo.

### 3. Collision model (unchanged, by design)

`is_colliding_at(walkable_top + 0.2)` is false on walls and gates. The probe is a **floor**. Walls block by failed step-up from the low neighbor. Gate is a gameplay passage. WorldObject `Area3D` is debug (`collision_layer=0`). Visible volume ≠ physics body.

### 4. Opposite terrain faces

Raised wall columns list both POS and NEG side codes (`[0,6,4,3,4,5,6]`). That is a raised box, not a winding bug. No live photo showed a single slab with inverted face textures after the earlier Y-down greedy removal.

## Do not do next without a new brief

- Do not add per-voxel bodies or authored assets.
- Do not treat `verify_ramp_landing` as camera proof of live wedges.
- Do not treat `verify_ramp_resident_mesh.gd` as a substitute for a windowed F4 photo of `(49,8)`.
