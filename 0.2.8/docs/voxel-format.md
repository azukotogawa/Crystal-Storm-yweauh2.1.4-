# crystalstorm-voxel-v1

Shared store for Crystal Storm voxel models (characters, creatures, vegetation, items, objects). Cole, 2026-10-30: base **8 voxels per terrain block**, **16 per block only on silhouettes and edges**, hollow interiors, one small shared palette, no random per-voxel colour. Inventory icons stay flat 2D. This file does not place models in the world.

`VoxelModelBuilder` in `helpers/voxel_model_builder.gd` is the mesher. `CrystalVoxelLoader` in `helpers/crystal_voxel_loader.gd` reads this format, builds one `ArrayMesh` per model (and one mesh per named part), and caches the results. Do not instance a node per voxel.

## File

UTF-8 JSON, one model per file.

```json
{
  "format": "crystalstorm-voxel-v1",
  "name": "tree_oak",
  "size": [128, 120, 112],
  "vpb": 16,
  "base_cell": 2,
  "scale": "terrain_block",
  "pivot": [56, 0, 56],
  "palette": [[64, 44, 32]],
  "parts": {
    "trunk": [[14, 0, 54, 0]],
    "canopy": [[14, 93, 54, 8]]
  }
}
```

| Field | Meaning |
| --- | --- |
| `format` | Must be `crystalstorm-voxel-v1`. |
| `name` | Stable id. File name should match. |
| `size` | Grid extent `[x, y, z]` in cells. Cells outside this are dropped. |
| `vpb` | Cells along one terrain block. Reference models use **16**. |
| `base_cell` | Edge length, in cells, of a base cube. Reference models use **2**, which is 8 cubes per block. A detail cube is 1 cell (16 per block). |
| `scale` | `terrain_block` only. One cell is `WorldSettings.voxel_scale / vpb` world units (`voxel_scale` stays 2.0, so a cell is 0.125 and a base cube is 0.25). |
| `pivot` | Point in cell space that sits at the local origin. Y up. Not a bone. |
| `palette` | At most **16** colours, each `[r, g, b]` in 0–255. Every entry must be in `assets/voxel/palette.json`. |
| `parts` | Named groups. Each cell is `[x, y, z, i]`: integer cell, `i` an index into `palette`. Empty space is omitted, not stored as a clear cube. |

A cell is one cube. The file lists every occupied cell, including detail cells. `base_cell` is the authoring step, not a mesher expansion. Detail cells (anything not aligned to `base_cell`) belong on the outer shell and on edges. Interiors stay empty. Do not tint a cell at random; `i` is a palette material.

The same RGB is the same material. Painted light and dark steps are separate palette entries (the reference trees do this per 8-block cell). They are not a runtime light. Face shade still comes from the terrain sun `(0.55, 0.82, 0.38)` when a later pass instances the mesh. Vertex colour is albedo only.

## Parts, pivot, rigs

Part names are the rig. A pose rotates a whole part. It does not move cubes inside a part.

The loader builds:

- one `ArrayMesh` for every part concatenated (one draw for a static prop)
- one `ArrayMesh` per part, in the same pivot space, so a rig can parent them

Trees converted from the approved reference use `trunk` (palette indices 0–3, bark) and `canopy` (indices 4 and up). Other models pick their own names (`head`, `torso`, `lid`, `grip`).

The three trees share the authoring grid `size` `[128, 120, 112]` and `pivot` `[56, 0, 56]`. That pivot is the reference frame whose grid minimum sits 3.5 blocks toward −X and −Z (56 / 16). Feet are `y = 0`. The trunk centre is about cell `(55.5, *, 55.5)`, so it stands on the origin.

## Shared palette

`assets/voxel/palette.json` (`crystalstorm-voxel-palette-v1`) is the only colour list. A model copies the entries it uses into its own `palette` so the file still loads alone. A model does not invent a nearby RGB. Player cloth, hide, and crystal colours already named in `studio/ART-STYLE.md` stay the character set; vegetation uses the tree entries in the shared file.

## Mesh and cache

Greedy merge per face and per palette index. Hidden faces (a neighbour cell is occupied) are not emitted. The mesh is one surface, indexed triangles, normals outward, vertex colours from the palette. No per-voxel `MeshInstance3D`.

`CrystalVoxelLoader.mesh_for(path)` and `part_meshes(path)` keep an in-memory cache and write `user://crystal_voxel_cache/*.res`. The cache is not a source file and is not committed. Changing `voxel_scale` or the JSON changes the cache key.

## `.vox` import

MagicaVoxel `.vox` (version 150, `SIZE` / `XYZI` / `RGBA`) is an authoring input, not the store. `CrystalVoxelLoader.import_vox(path)` reads a single model:

- file Z is up; the loader maps `(x, y, z)` in the file to cell `(x, z, y)`
- the file colour index is 1-based into the `RGBA` chunk; the model palette is the colours actually used, in first-seen order
- the result is one part, `body`, with `vpb` 16, `base_cell` 2, `scale` `terrain_block`, and `pivot` `[0, 0, 0]` unless the caller passes another pivot

Save the result as `crystalstorm-voxel-v1` before the game uses it. Do not commit `.vox` as the reviewed copy.

## Reference trees

| Model | Path | Cells |
| --- | --- | --- |
| Oak | `assets/voxel/vegetation/tree_oak.json` | 54680 |
| Birch | `assets/voxel/vegetation/tree_birch.json` | 27740 |
| Pine | `assets/voxel/vegetation/tree_pine.json` | 42832 |

Converted from `trees_16vpb.json` without dropping cells. The oak’s quad count is above the later vegetation budget (≤5000 at LOD0). Thinning and LOD are a later job. These files are not spawned, and they do not change terrain, ramps, or lighting.

## Checks

`scripts/verify_voxel_model_loader.gd` loads the three trees, prints voxel and quad counts, checks the shared palette, meshes a part, and imports a tiny `.vox`.
