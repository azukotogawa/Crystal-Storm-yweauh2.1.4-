# Voxel art quad and draw budget

Measured on the medium preset (render distance 2, crystal sim on, flow cap 280, upload budget 3500us) with a valid 5x5 world bake. Headless Godot reports GPU draw and primitive counters as 0, so draw calls are visible MeshInstance3D + MultiMeshInstance3D + Sprite3D nodes, and quads are counted from mesh index buffers (a box counts as 6). Frame time is the mean of 48 frames after 120 warmup frames. The 10% crystal profile fills 10% of the columns in currently loaded chunks, not 10% of the whole 2048-wide world. `coverage` stays near 0 because that ratio uses the full world. `sim` is `CrystalFluidSim.cell_count()` after `_recalc_stats`.

Detail flags stayed at the approved values. A matched scene (same node and quad counts as the pre-integration sample) held about 60 fps, so edge detail, LOD distance, and wave amplitude were not reduced.

| Flag | Value |
| --- | --- |
| `TerrainLook.SURFACE_WAVE_AMPLITUDE_STEPS` | 2 |
| `VegetationVoxelCatalog.LOD0_COLUMNS` | 10 |
| `VegetationVoxelCatalog.EDGE_DETAIL` | true |
| `vegetation_billboard_distance_columns` (medium) | 72 |

## Model budgets

One ArrayMesh per model, or one mesh per moving part. Worst live counts from `CrystalVoxelLoader` on this machine:

| Group | Budget | Worst | Draws |
| --- | --- | --- | --- |
| Big tree LOD0 | 5000 quads | oak 4501 (LOD1 4105) | 1 mesh, instanced |
| Small plant | 300 quads | bush 94 (catalog worst plant 144) | 1 mesh, instanced |
| Object | 1500 quads | gate voxel 354 | 2 (torch, chest, door, furnace, crystal node); others 1 |
| Held item | 500 quads | wooden sword 86 | 1 mesh per tool |
| Entity | 3000 quads | player 454 | one mesh per rig part |

Object greedy quads: torch 105, chest 264, door 142, workbench 166, furnace 243, crystal node 83, bed 116, sign 166, wood wall 240, stone wall 133, gate 354, bridge 138, town hall 315, ruin pillar 346. Live walls, gates, bridges, town halls, and ruin pillars stay on the authored OBJ meshes. The voxel files are the fallback only when that visual id has no OBJ.

Chunk vegetation is one MultiMesh per mesh variant per chunk. Sprite3D billboards remain only for corrupt batch-1 plants and for authored plants past the billboard distance. At render distance 2 that distance is never reached, so the samples below show 0 sprites.

## Scene samples

Pre-integration (edge detail on, amplitude 2), settled after warmup:

| Profile | frame ms | fps | draws | quads | boxes | meshes | multimesh | sim cells |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Busy | 16.598 | 60.2 | 286 | 42792 | 121 | 240 | 46 | 1 |
| 10% loaded columns | 16.535 | 60.5 | 361 | 71893 | 155 | 283 | 78 | not printed |

Integration, same flags, a heavier stream that had loaded more columns (307 filled vs 281):

| Profile | frame ms | fps | draws | quads | boxes | meshes | multimesh | sim cells |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Busy | 17.070 | 58.6 | 304 | 46899 | 134 | 254 | 50 | 1 |
| 10% loaded columns | 16.878 | 59.2 | 381 | 79433 | 162 | 292 | 89 | 308 |

Integration with edge detail forced off, which landed on the same geometry as the pre-integration sample (quad delta 0). Frame time moved by under 0.2 ms, which is sample noise, not a mesh change. Edge detail was turned back on because it did not buy frames in this view.

| Profile | frame ms | fps | draws | quads | boxes | meshes | multimesh | sim cells |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Busy | 16.792 | 59.6 | 286 | 42792 | 121 | 240 | 46 | 1 |
| 10% loaded columns | 16.631 | 60.1 | 361 | 71893 | 155 | 283 | 78 | 282 |

The matched 10% profile is +0 quads and +0 draws versus the pre-integration sample. The heavier stream is about +10% quads, under the chunk cap of current +20%, and it tracked extra loaded columns rather than a denser mesh. Amplitude stays at 2.

## What replaced a placeholder

- Scatter kind `flower` uses the flower voxel MultiMesh (same path as `wildflower`). Bush and mushroom scatter were already on that path.
- Point-of-interest plants are one catalog mesh each: bush, fern, and stand-ins for crystal bush (bush), crystal grass (grass tuft), and shard tree (tree LOD1). The node is still named `VoxelProp_*` so layout checks keep working. There is no authored crystal-plant voxel.
- A treasure ruin keeps its pillar OBJ and adds the chest voxel one block to the side (`voxel_scale` on X, scale unchanged) when the cell stores a chest.
- `configure_building_mesh` uses the object voxel mesh when the visual id has no authored OBJ. Ids that already have an OBJ are unchanged.

## What is still a box or a billboard

- Rock, log, fence, boulder, stump, and dead bush stay box clusters. No voxel model exists, and the prop-density check requires those boxes.
- Distant landmarks stay boxes. Their verify script checks box height, width, and glow.
- Entity and held-item box meshes remain the fallback when a voxel rig is missing. Live creatures and tools already use the voxel rigs.
- Corrupt batch-1 plants stay Sprite3D. Medium play does not reach the vegetation billboard distance, so ordinary plants are not billboards in these samples.
