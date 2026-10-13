# Terrain Batch 04 report

Authored four **unique-cell** P1 placeholders. Voxel IDs, `ATLAS_COORDS` (except no edits this batch), atlas size, worldgen, mesh, water sim, and gameplay unchanged. Batch 01–03 cells pixel-identical.

## IDs authored

| Material | ID | Cell | Side |
| --- | ---: | --- | --- |
| MOUNTAIN2 | 16 | (1,4) | own (1,4) |
| BASIN | 34 | (0,9) | own (0,9) |
| SNOW | 22 | (0,5) | STONE2 (2,4) |
| SNOW2 | 23 | (1,5) | STONE2 (2,4) |

| Tile | Read |
| --- | --- |
| MOUNTAIN2 | cool blue-grey plates — not Batch 01 cobble STONE |
| BASIN | khaki cracked mud — not dirt clods, not steppe grass |
| SNOW | high-value with blue shadow — not pure white |
| SNOW2 | icier / cooler than SNOW |

Sources: `assets/tiles/batch04/*.png` plus `*_2x2.png`.

## Mapping changes

**None.** Did not paint MOUNTAIN (shares STONE) or MOUNTAIN3 (shares STONE2).

## Atlas cells changed

`Cube.png` still **224×320**. Hash vs pre-batch snapshot:

- `CHANGED=4 UNEXPECTED=0 BATCH_N=4 KEEP_UNCHANGED=17`
- `ATLAS_CELLS_OK`

Prior Batch 01–03 cells (17 KEEP) identical, including STONE (0,4), STONE2 (2,4), GRASSLAND4 (3,1), DIRT (3,2).

## Collisions

| Cell | Occupants | Action |
| --- | --- | --- |
| (1,4) | MOUNTAIN2 only | painted |
| (0,9) | BASIN only (BASIN2/3 unused other cells) | painted |
| (0,5)/(1,5) | SNOW / SNOW2 | painted |
| (0,4) | STONE + unused MOUNTAIN | **not painted** |
| (2,4) | STONE2 + MOUNTAIN3 | **not painted** |

## Natural vs controlled

Seed 12349 start ring: GRASSLAND4 at (−36, −9). No MOUNTAIN2 / BASIN / SNOW in ±48 (highland is ~−306,22; snow needs cold map-temp).

Controlled 3×3 stamps + remesh on land next to natural steppe. `WANT==GOT` both launches.

| Shot | ID | Evidence |
| --- | ---: | --- |
| `mountain2.png` | 16 | Cool grey plates vs olive steppe |
| `basin.png` | 34 | Khaki cracked pad, player on it |
| `snow.png` | 22 | White-blue island |
| `snow2.png` | 23 | ID asserted; icier cell (1,5) |
| `stone_b01.png` | 39 | ID asserted; STONE cell unchanged in hash |
| `grassland4_b03.png` | 9 | Batch 03 olive steppe still present |
| `chunk_boundary.png` | — | Steppe / river edge |

## Regressions

None on atlas. GRASSLAND4 still unshared from DIRT. STONE / STONE2 cells unchanged.

## Next priority

Remaining **shared** live types (need unused-hole `ATLAS_COORDS` splits, do not overwrite):

1. HILLS3 vs TREE_TRUNK → (3,3)
2. Optional: BUSH vs HILLS4, GRASS_TUFT vs GRASSLAND2, MOUNTAIN3 vs STONE2

No more unique-cell P1 placeholders except unused P3 rows.

## Stop

Batch 04 only.
