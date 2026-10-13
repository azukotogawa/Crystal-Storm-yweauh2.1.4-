# Terrain Batch 01 report

Authored ten 32×32 nearest tiles into the **existing** `Cube.png` slots. Voxel IDs, `ATLAS_COORDS`, `get_atlas_coord_for_face`, mesh, worldgen, and water sim were not changed.

## Slot map (shipped `VoxelTypes`)

From `{SCRATCH}/batch01_slot_map.log` (dumped twice; same result):

| Material | ID | Cell | Top | Side | Bottom (unused) |
| --- | ---: | --- | --- | --- | --- |
| GRASSLAND3 | 8 | (2,2) | (2,2) | **DIRT (3,2)** | DIRT2 (0,6) |
| DIRT | 41 | (3,2) | (3,2) | (3,2) | (0,6) |
| RIVER | 37 | (1,0) | (1,0) | (1,0) | (0,6) |
| STONE | 39 | (0,4) | (0,4) | (0,4) | (0,6) |
| HILLS | 11 | (0,3) | (0,3) | **TREE_TRUNK (2,3)** | (0,6) |
| TREE_TRUNK | 47 | (2,3) | (2,3) | (2,3) | (0,6) |
| OCEAN | 0 | (0,0) | (0,0) | (0,0) | (0,6) |
| BEACH | 3 | (0,1) | (0,1) | (0,1) | (0,6) |
| STONE2 | 40 | (2,4) | (2,4) | (2,4) | (0,6) |
| DIRT2 | 42 | (0,6) | (0,6) | (0,6) | (0,6) |

Grass sides still remap to DIRT. Forest sides still remap to TREE_TRUNK. Face 2 still remaps to DIRT2.

## Shared-cell couplings (not remapped)

| Cell | Batch 01 occupant | Also looks like this |
| --- | --- | --- |
| (2,2) | GRASSLAND3 | TOWN_PATH |
| (3,2) | DIRT | GRASSLAND4 (steppe), FARMLAND |
| (2,3) | TREE_TRUNK | HILLS3 (pine tops) |
| (0,4) | STONE | MOUNTAIN |
| (2,4) | STONE2 | MOUNTAIN3 |
| (1,0) | RIVER | WATER |
| (0,0) | OCEAN | OCEAN2, OCEAN3 |
| (0,6) | DIRT2 | VALLEY |

Live consequence: steppe (`GRASSLAND4`) reads as the new dirt tile. That is the existing slot collision, not a new remap. Split plan stays in `TERRAIN_ATLAS_COLLISION_MAP.md` (unused Cube.png holes; no `ATLAS_COORDS` edits in Batch 01).

## Atlas integrity

`Cube.png` is **224×320**. Cell hash vs pre-batch snapshot (`batch01_atlas_cells.log`):

- `CHANGED=10 UNEXPECTED=0 BATCH_N=10`
- `ATLAS_CELLS_OK`

Only the ten listed cells differ. Neighbor chips (including unused black cells) are pixel-identical.

## Material language

One ground palette, painted in GDScript (not photos), fill + 2–4px blobs (no 1px speckle):

| Tile | Read |
| --- | --- |
| GRASSLAND3 | mid green carpet, sparse 2px tufts |
| DIRT | warm earth speckle (painted light so shader ×0.68 sides stay readable) |
| DIRT2 | cooler / darker subsoil |
| RIVER | mid navy speckle |
| OCEAN | deeper navy speckle |
| BEACH | warm sand speckle |
| STONE | cool grey + sparse cracks |
| STONE2 | worn ochre-grey + cracks |
| HILLS | deep canopy clumps |
| TREE_TRUNK | bark-brown speckle (sides + tree-base tops) |

Sources live in `assets/tiles/batch01/*.png` plus `*_2x2.png` seam checks. No text, watermarks, or borders.

## Live path

`ChunkView` still preloads `res://assets/tiles/Cube.png`. Face remaps unchanged.

Gameplay camera: iso −35.264 / 45. Every named shot asserts `world.get_tile_type == id` before capture (`scripts/verify_terrain_batch01_capture.gd`). Launch twice; frames under `{SCRATCH}/` and `{SCRATCH}/launch1/`.

### Where those IDs actually live (seed 12349)

| ID | Natural cell | Notes |
| ---: | --- | --- |
| HILLS 11 | **(369, 426)** | Forest Voronoi center ~(363.5, 432.7). `get_tile_type` confirmed 11. |
| BEACH 3 | **none** | Ocean biome starts at \|x\|>1024; rim height is already 2–8 (OCEAN). No landfall band on this seed. |
| STONE 39 | mountain rim e.g. (−40, 1030) | Inland cave-mouth hunt ±160 missed. Far rim shots were unstreamed/black. |
| STONE2 40 | (47, −6) | Ruin neighborhood. |
| OCEAN 0 | (1026, −24) | +X rim. |
| GRASSLAND3 / RIVER / TREE_TRUNK | start ring | Natural, plus grass→DIRT sides. |

Far teleports (HILLS ~560 cells, mountain/ocean rim) do not keep the start-ring mesh resident, so the photographed proof is a **streamed start-ring yard**: `FeatureRegistry.set_tile_override` + `ChunkData.patch_local_column` + `remesh_resident_maps_at_world` (bake mesh-plan cache would otherwise keep river quads). `get_tile_type` still returns the named ID. Same atlas path as natural cells.

### SHOT_ID (launch 1, all want==got)

| Shot | ID | Cell | What the frame shows |
| --- | ---: | --- | --- |
| `plains_or_steppe.png` | 8 | (19, 19) | Mid-green GRASSLAND3 tops + **DIRT cliff sides** |
| `dirt.png` | 41 | (23, 19) | Warm earth plateau (also the grass-side tile) |
| `river.png` | 37 | (27, 19) | Mid-navy water, distinct from dirt/stone |
| `hills.png` | 11 | (35, 19) | Deep canopy tops + **TREE_TRUNK bark sides** |
| `forest.png` | 47 | (19, 23) | Bark-brown tree-base / forest-side tile |
| `stone.png` | 39 | (31, 19) | Cool grey plates + cracks |
| `stone2.png` | 40 | (31, 23) | Worn ochre-grey, distinct from STONE |
| `dig_dirt_side.png` | 8 | (20, 19) | Grass top, dirt lip after a 1-layer dig |
| `dirt2.png` | 42 mesh / build 41 | (35, 23) | Darker subsoil island (DIRT dug 2 layers) |
| `ocean_rim.png` | 0 | (23, 23) | Deep water next to sand (yard OCEAN; natural rim is 1026,−24) |
| `beach.png` | 3 | (27, 23) | Warm sand field (stamped; no natural BEACH on this seed) |
| `chunk_boundary.png` | — | (15, 19) | Tile continuous across a chunk edge |
| `build_dirt_fill.png` | — | dirt+1 | Raised dirt + wood wall |

Vegetation IDs unchanged: tuft=45, bush=46, tree=47.

## Limitation (no renderer change)

Cannot give steppe, farmland, town path, or pine their own look without **new atlas cells**. Batch 01 paints the listed occupants only.

## Stop

Batch 01 only. No Batch 02 tiles. No voxel-ID or atlas-index edits.
