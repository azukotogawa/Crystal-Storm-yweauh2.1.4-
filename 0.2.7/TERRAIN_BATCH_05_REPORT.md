# Terrain Batch 05 report

Documented unused-hole `ATLAS_COORDS` split for the remaining live clashes, then painted those cells. Voxel IDs, atlas **size**, worldgen, mesh, water sim, and gameplay unchanged. Batches 01–04 KEEP cells pixel-identical.

## Mapping (smallest safe set)

| ID | Name | Old cell | New cell | Sides |
| ---: | --- | --- | --- | --- |
| 13 | HILLS3 | (2,3) TREE_TRUNK | **(3,3)** | TREE_TRUNK |
| 46 | BUSH | (4,3) HILLS4 | **(5,3)** | own |
| 45 | GRASS_TUFT | (1,2) GRASSLAND2 | **(5,2)** | DIRT |
| 17 | MOUNTAIN3 | (2,4) STONE2 | **(3,5)** | own |
| 14 | HILLS4 | (4,3) kept | **(4,3)** | TREE_TRUNK |

Holes had `OCCUPANTS []`. Did **not** move TREE_TRUNK, GRASSLAND2, STONE2, DIRT.

## IDs authored

| Tile | Read |
| --- | --- |
| HILLS3 | cool pine needles — not bark |
| HILLS4 | deep jungle clumps — not bush pad |
| BUSH | round dark-green pad |
| GRASS_TUFT | brighter tufts than meadow |
| MOUNTAIN3 | cool peak plates — not ochre STONE2 |

Sources: `assets/tiles/batch05/*.png` plus `*_2x2.png`.

## Atlas

`Cube.png` still **224×320**. Hash vs pre-batch snapshot:

- `CHANGED=5 UNEXPECTED=0 BATCH_N=5 KEEP_UNCHANGED=21`
- `ATLAS_CELLS_OK`

## Natural vs controlled (seed 12349)

| ID | Natural |
| ---: | --- |
| GRASSLAND4 | (−36, −9) |
| GRASS_TUFT | **(−32, 12)** |
| TREE_TRUNK | **(−24, 17)** |
| HILLS3 / HILLS4 / BUSH / MOUNTAIN3 | not in start ring (forest/highland far) — stamped |

Controlled yard at (−34, −9). Per-shot `remesh_resident_maps_at_world` so bake cannot leave steppe quads.

`scripts/verify_terrain_batch05_capture.gd` — both launches `WANT==GOT`.

| Shot | ID | Mesh |
| --- | ---: | --- |
| `hills3.png` | 13 | Pine ribs + bark sides |
| `hills4.png` | 14 | Jungle clumps |
| `bush.png` | 46 | Round pad, not jungle field |
| `grass_tuft.png` | 45 | Bright tufts + dirt sides |
| `mountain3.png` | 17 | Cool peak, not ochre |
| `tree_trunk_b01.png` | 47 | Batch 01 bark unchanged |
| `grassland2_b02.png` | 7 | Batch 02 meadow unchanged |
| `stone2_b01.png` | 40 | Batch 01 ochre unchanged |

## Remaining

P3 unused only (desert/tundra/valley, BEACH2/3, MOUNTAIN4–7). WATER stays on RIVER. CAVE_STONE only if caves mesh on.

## Stop

Batch 05 only. No Batch 06.
