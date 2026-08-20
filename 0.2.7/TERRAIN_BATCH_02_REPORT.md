# Terrain Batch 02 report

Authored four live 32×32 nearest tops into the **existing** `Cube.png` cells. Voxel IDs, `ATLAS_COORDS`, atlas size, `get_atlas_coord_for_face`, worldgen, mesh, water sim, and gameplay were not changed. Batch 01 cells stayed pixel-identical.

## IDs authored

| Material | ID | Cell | Top | Side (unchanged remap) |
| --- | ---: | --- | --- | --- |
| GRASSLAND | 6 | (0,2) | (0,2) | DIRT (3,2) |
| GRASSLAND2 | 7 | (1,2) | (1,2) | DIRT (3,2) |
| GRASSLAND5 | 10 | (4,2) | (4,2) | DIRT (3,2) |
| HILLS2 | 12 | (1,3) | (1,3) | TREE_TRUNK (2,3) |

Hue-shifts of Batch 01 GRASSLAND3 / HILLS. 2–4px blobs, no 1px speckle.

| Tile | Read vs Batch 01 |
| --- | --- |
| GRASSLAND | brighter lime grass (marsh / “grass”) |
| GRASSLAND2 | yellow-olive meadow |
| GRASSLAND5 | pale dry olive savanna |
| HILLS2 | denser / darker canopy than HILLS |

Sources: `assets/tiles/batch02/*.png` plus `*_2x2.png` seam checks.

## Atlas cells changed

`Cube.png` still **224×320**. Hash vs pre-batch snapshot (`{SCRATCH}/batch02_atlas_cells.log`):

- `CHANGED=4 UNEXPECTED=0 BATCH_N=4 B01_UNCHANGED=10`
- `ATLAS_CELLS_OK`

Only `(0,2) (1,2) (4,2) (1,3)` differ. All ten Batch 01 cells and unused holes are identical.

## Collisions discovered (not remapped)

Dumped twice (`batch02_slot_map.log`, `batch02_slot_map_rerun.log`):

| Cell | Occupants | Batch 02 action |
| --- | --- | --- |
| (1,2) | GRASSLAND2 + **GRASS_TUFT** | Painted meadow. Tuft pads share the look. Documented, not split. |
| (3,2) | DIRT + GRASSLAND4 + FARMLAND | **Not painted.** Steppe/farm still read as dirt. |
| (2,2) | GRASSLAND3 + TOWN_PATH | **Not painted.** Town streets still plains grass. |
| (2,3) | TREE_TRUNK + HILLS3 | **Not painted.** Pine still bark. |
| (4,3) | HILLS4 + BUSH | **Not painted.** |

## Mapping changes

**None.** No `ATLAS_COORDS` edits. Unused-hole splits remain the later plan in `TERRAIN_ATLAS_COLLISION_MAP.md`.

## Natural-generation evidence (seed 12349)

`world.get_tile_type` hunt during live boot:

| ID | Natural cell |
| ---: | --- |
| GRASSLAND 6 | (−28, 4) |
| GRASSLAND2 7 | (−28, 11) |
| GRASSLAND5 10 | (−28, −9) |
| HILLS2 12 | (377, 402) near forest ~(363, 433) |

HILLS2 is ~500 cells from origin (far teleports go black). Grass family cells are in the start ring.

## Controlled-test evidence

Streamed start-ring 3×3 stamps + `ChunkData.patch_local_column` + `remesh_resident_maps_at_world` (bake mesh-plan cache would keep old quads). Gameplay camera iso −35.264 / 45.

`scripts/verify_terrain_batch02_capture.gd` asserts `WANT_ID == ACTUAL_ID` before each shot. Launch **twice**; both `TERRAIN BATCH02 CAPTURE OK`.

| Shot | ID | Cell | Frame |
| --- | ---: | --- | --- |
| `grassland.png` | 6 | (19, 19) | Lime grass top + dirt sides |
| `grassland2.png` | 7 | (23, 19) | Yellow-olive meadow + dirt sides |
| `grassland5.png` | 10 | (27, 19) | Pale savanna + dirt sides |
| `hills2.png` | 12 | (31, 19) | Dark dense canopy + bark sides |
| `grassland3_b01.png` | 8 | (19, 23) | Batch 01 mid-green still distinct |
| `hills_b01.png` | 11 | (23, 23) | Batch 01 canopy still lighter than HILLS2 |
| `dirt_b01.png` | 41 | (27, 23) | Batch 01 dirt unchanged |
| `chunk_boundary.png` | — | (15, 19) | River / grass across a chunk edge |

Copies: `{SCRATCH}/launch1/` and `{SCRATCH}/launch2/`.

## Regressions

None found. Batch 01 grass / dirt / hills still distinguishable beside the new tops. Atlas size and remaps unchanged.

## Next recommended batch

P1 landscape that already has **its own** cell (no clash overwrite):

1. **MOUNTAIN2** `(1,4)` — highland / mid border
2. **BASIN** `(0,9)` — steppe/marsh dry mud
3. **SNOW / SNOW2** `(0,5)/(1,5)` — only if a cold map-temp seed is used, else stamp

Then the **atlas-cell split** (unused holes, `ATLAS_COORDS` only): GRASSLAND4 → (3,1), TOWN_PATH → (5,1), FARMLAND → (4,1), HILLS3 → (3,3). Do not start P3 desert/tundra/valley.

## Stop

Batch 02 only. No Batch 03 tiles. No voxel-ID or atlas-index edits.
