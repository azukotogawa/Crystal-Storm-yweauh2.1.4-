# Live world representation audit

**Date:** 2026-08-17  
**Scope:** how visible objects exist in Godot: gameplay data, visual mesh, collision, and Node/scene.

Terrain stays chunked MultiMesh. Individual voxels are **not** Nodes.

---

## Shared contract

| Layer | Authority | Units |
|---|---|---|
| Gameplay / edits | WorldState overlays via TerrainEdits / FeatureRegistry / ChannelRegistry | integer columns `wx,wz`; Y in world units |
| Generation | InfiniteNoiseWorld seed noise | same columns; surface Y in world units |
| Visual | `WorldVisualCoords.column_to_world` → ChunkView MultiMesh / WorldObject / CrystalPresentation | XZ = column × `voxel_scale` |
| Walk / collision | VoxelFloorProbe heightfield (not Godot physics for terrain) | column + walkable Y |
| Player body | CharacterBody3D capsule; movement writes `voxel_position` then sets `global_position` | voxel_position XZ = columns |
| Authored structure | `WorldObject` scene (`scenes/world_object.tscn`) | gameplay cell + stored `yaw` → mesh + Area3D bounds |

**Face codes** (ChunkView.gdshader + ChunkManager + WorldVisualCoords):  
`0` top, `2` bottom (disabled), `3–6` −X/+X/−Z/+Z, `7–9` ramp/corner/side.  
A greedy Y-normal pass may only emit `FACE_TOP`. Side faces are X/Z wall runs. Mixing those is the face-orientation bug.

**Incremental mesh:** a greedy quad is coverage. Remesh replaces coverage *inside* `patch_rect` and **clips** the exterior of intersecting slabs. Dropping a whole merged slab leaves holes around edited blocks.

**Structure yaw** is gameplay state (`FeatureRegistry.yaw` / `dir`) computed by `StructureOrientation` from neighbors. Visuals and inspector read it. They must not invent a second orientation.

Helpers: `helpers/world_visual_coords.gd`, `helpers/structure_orientation.gd`.

---

## Object catalog

### Player
1. **Sees:** capsule/mesh at feet on the heightfield.  
2. **Node:** `Game/Player` (`CharacterBody3D`, `player/player.gd`).  
3. **Mesh:** `Player/MeshInstance3D`.  
4. **Collision:** runtime `BodyCollision` capsule; movement uses `VoxelFloorProbe`.  
5. **Data:** `voxel_position` (column XZ), health, inventory, stats.  
6. **Disagree?** Mesh Y vs voxel_position vs probe walk height if caches go stale.  
7. **Inspect:** Remote Scene `Player`; inspector column under feet; F4.

### Terrain voxel / chunk
1. **Sees:** greedy-meshed heightfield quads (atlas shader).  
2. **Node:** `ChunkView` under ChunkManager (pooled). **Not** one node per voxel.  
3. **Mesh:** `MultiMeshInstance3D` / `terrain_surface_mesh`.  
4. **Collision:** none on the mesh. Walk via probe + `world.get_surface_height` + edits.  
5. **Data:** `ChunkData` maps; overlays in WorldState; bake package if present.  
6. **Disagree?** Mesh can lag edits; bake base vs live overlay. Incremental clip keeps coverage.  
7. **Inspect:** `cm.chunks[Vector2i(cx,cz)]`; inspector tile/height/bake.

### Ramp
1. **Sees:** wedge / corner / concave quads in ChunkView (`dir` = toward low).  
2. **Node:** none — encoded in chunk MultiMesh + `ChunkData.ramp_map`.  
3. **Mesh:** same ChunkView.  
4. **Collision:** `TerrainRamps.walkable_height_from_entry` (same `dir`).  
5. **Data:** `ramp_map` entry `{dir, dir2, corner, approach, …}`.  
6. **Disagree?** If mesh `dir` and probe entry differ (stale ramp_map). Inspector shows both.  
7. **Inspect:** `has_ramp` / `ramp` on the column.

### Wall (stone/wood)
1. **Sees:** raised terrain tile **and** `WorldObject` authored mesh cap.  
2. **Node:** `WorldObject` under Buildings (`scenes/world_object.tscn`).  
3. **Mesh:** authored OBJ via `GameVisualRegistry.configure_building_mesh`.  
4. **Collision:** taller `get_surface_height` / height_delta. Area3D is debug bounds only.  
5. **Data:** TerrainEdits height_delta + build_tile; FeatureRegistry `build_id`, `yaw`.  
6. **Disagree?** Until rebuild, visual height lags overlay; yaw must match stored feature.  
7. **Inspect:** `build_id`, `height_delta`, `structure_path`, yaw.

### Gate / bridge
1. **Sees:** `WorldObject` authored mesh; gate does not raise terrain; bridge does.  
2. **Node:** `WorldObject`.  
3. **Mesh:** `gate.obj` / `bridge.obj`.  
4. **Collision:** gate is a passage (walk through cell); bridge uses raised heightfield. Orientation is `yaw` (neighbor run).  
5. **Data:** FeatureRegistry `is_passage` / `is_bridge` / `yaw` / `dir`.  
6. **Disagree?** If yaw is missing, visual defaults to StructureOrientation at bind time.  
7. **Inspect:** feature dict + structure node path.

### Crystal
1. **Sees:** CrystalPresentation meshes / clusters.  
2. **Node:** `Game/CrystalManager` + presentation children; cells are not nodes.  
3. **Mesh:** presentation MultiMesh / cluster meshes.  
4. **Collision:** gameplay `has_crystal_at` / depth.  
5. **Data:** `CrystalSimulation` depth map.  
6. **Disagree?** Mesh dirty vs sim after terrain edit — presentation forces nearby full rebuild.  
7. **Inspect:** `get_depth_at`, spawn list, inspector `crystal_depth`.

### Water
1. **Sees:** river/water tiles + fluid mesh if present.  
2. **Node:** `VoxelFluidService` (logic); no per-cell node.  
3. **Mesh:** tile in chunk and/or fluid engine mesh.  
4. **Collision:** not a physics body; walk uses surface.  
5. **Data:** `ChannelRegistry` water_level / flow_dir.  
6. **Disagree?** Immediate reflow vs mesh apply.  
7. **Inspect:** channel dict.

### Enemy / wildlife
1. **Sees:** voxel prop or Sprite3D.  
2. **Node:** `WorldEntity` / crystal enemy under Entities.  
3. **Mesh:** `_voxel_prop` or `_sprite`.  
4. **Collision:** combat query AABB/radius (world space).  
5. **Data:** EntityBrain + FeatureRegistry spawns.  
6. **Disagree?** Visual offset vs `home_cell` if column/world mixed.  
7. **Inspect:** scene path + health.

### Vegetation
1. **Sees:** FeatureVisualLayer billboards / voxel models.  
2. **Node:** optional prop nodes; many are MultiMesh instances.  
3. **Mesh:** FeatureVisualLayer.  
4. **Collision:** none (walkable).  
5. **Data:** FeatureRegistry plant_id / baked static.  
6. **Disagree?** Baked veg vs live FeatureRegistry tombstones.  
7. **Inspect:** feature plant_id, `_baked_static`.

### Town hall / ruin
1. **Sees:** `WorldObject` (`town_hall` / `ruin_pillar`) at the landmark cell.  
2. **Node:** WorldObject under Buildings.  
3. **Mesh:** authored OBJ.  
4. **Collision:** terrain under stamp.  
5. **Data:** FeatureKind.TOWN_BUILDING / RUIN.  
6. **Disagree?** Stamp tile vs visual prefab origin.  
7. **Inspect:** town/ruin list + structure path.

---

## Deferred bake / playable gate

- `WorldBakeService.prime_region` bakes the start stream ring + origin 3×3 (and spawn-candidate rings) **before** the loading screen dismisses.
- `CompositionRoot` advances `INITIAL_STREAM_READY` only when `ChunkManager.is_start_region_ready()` — every in-bounds chunk in the player stream ring is **resident**, not “≥1 chunk”.
- `GameplayInput.world_loading` blocks move/dig/build until the loading overlay dismisses (or immediately after the gate if there is no overlay).
- Loading UI shows `Start region streamed / needed` and package occupancy from live `start_region_status()`, not a canned stage percentage.
- Remaining packages fill on workers after play. Far travel must not bake on the main thread (`ensure_package_for_stream` waits on the worker queue unless `CRYSTALSTORM_BAKE_FILL_SYNC=1`).

---

## How to inspect live

1. Run `scenes/main.tscn` (or Play from the menu).  
2. Press **F4** for **Live World Inspector**.  
3. Aim at a column (existing target highlight).  
4. Selection box marks the column; toggles draw voxel/chunk/mesh/walk/height/feature/water/crystal overlays.  
5. Collision toggle sets Godot `debug_collisions_hint` (player capsule + WorldObject Area3D).  
6. Remote debugger still inspects real Nodes (Player, ChunkView, WorldObject, WorldEntity).
