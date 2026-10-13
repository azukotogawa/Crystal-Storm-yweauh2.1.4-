# Terrain Batch 03 report

Unshared the three live atlas collisions that made **steppe look like dirt** and **towns look like grass/dirt**. Voxel IDs, atlas **size**, worldgen, mesh, water sim, and gameplay unchanged. Batch 01/02 cells pixel-identical.

## IDs authored

| Material | ID | Old cell | New cell | Side |
| --- | ---: | --- | --- | --- |
| GRASSLAND4 (steppe) | 9 | (3,2) DIRT | **(3,1)** | DIRT (3,2) |
| FARMLAND | 48 | (3,2) DIRT | **(4,1)** | DIRT (3,2) |
| TOWN_PATH | 49 | (2,2) GRASSLAND3 | **(5,1)** | DIRT (3,2) |

| Tile | Read |
| --- | --- |
| GRASSLAND4 | dry olive-tan steppe, sparse tufts — not dirt clods |
| FARMLAND | 3px horizontal furrows |
| TOWN_PATH | pale packed earth — not grass |

Sources: `assets/tiles/batch03/*.png` plus `*_2x2.png`.

## Mapping changes

`helpers/voxel_types.gd` `ATLAS_COORDS` only (smallest safe split — unused cells, live `get_atlas_coord_for_face` at mesh time):

- `GRASSLAND4`: (3,2) → (3,1)
- `FARMLAND`: (3,2) → (4,1)
- `TOWN_PATH`: (2,2) → (5,1)

Grass-family **sides still remap to DIRT**. DIRT and GRASSLAND3 keep their Batch 01 cells.

## Atlas cells changed

`Cube.png` still **224×320**. Hash vs pre-batch snapshot:

- `CHANGED=3 UNEXPECTED=0 BATCH_N=3 KEEP_UNCHANGED=14`
- `ATLAS_CELLS_OK`

Only the three unused holes (3,1)/(4,1)/(5,1) differ. Those holes were unused placeholder chips (not pointed at by any ID).

## Collisions remaining

| Cell | Occupants |
| --- | --- |
| (2,3) | TREE_TRUNK + HILLS3 |
| (4,3) | HILLS4 + BUSH |
| (1,2) | GRASSLAND2 + GRASS_TUFT |
| (2,4) | STONE2 + MOUNTAIN3 |

## Natural-generation evidence (seed 12349)

| ID | Natural cell |
| ---: | --- |
| GRASSLAND4 9 | **(−36, −9)** start-ring steppe. `chunk_boundary.png` shows the **generated** olive field (not only the stamp). HUD biome = Steppe. |
| FARMLAND / TOWN_PATH | not in ±200 coarse scan (town disks are small). Controlled 3×3 stamps. |

## Controlled-test evidence

Yard next to natural steppe (−34, −9). Stamp + `patch_local_column` + `remesh_resident_maps_at_world`. Iso −35.264 / 45.

`scripts/verify_terrain_batch03_capture.gd` — both launches `WANT==GOT`.

| Shot | ID | Cell | Frame |
| --- | ---: | --- | --- |
| `grassland4.png` | 9 | (−33, −8) | Olive steppe plateau + surrounding natural steppe |
| `farmland.png` | 48 | (−29, −8) | Furrowed plots, distinct from steppe and path |
| `town_path.png` | 49 | (−25, −8) | Pale packed earth, not grass |
| `dirt_b01.png` | 41 | (−21, −8) | Batch 01 warm dirt **unchanged** |
| `grassland3_b01.png` | 8 | (−33, −4) | Batch 01 mid-green **unchanged** |
| `grassland5_b02.png` | 10 | (−29, −4) | Batch 02 savanna still paler |
| `chunk_boundary.png` | — | (15, −8) | River edge + **natural steppe field** |

Copies: `{SCRATCH}/launch1/` and `{SCRATCH}/launch2/`.

## Regressions

None. Dirt still dirt. Plains grass still grass. Savanna still distinct. Steppe no longer shares the dirt cell.

## Next priority

Own-cell placeholders still looking like old chips:

1. **MOUNTAIN2** `(1,4)` — highland / border (grey grid)
2. **BASIN** `(0,9)` — dry mud
3. **SNOW / SNOW2** — if a cold seed, else stamp

Then remaining splits: HILLS3 → (3,3), optional BUSH / GRASS_TUFT.

## Stop

Batch 03 only.
