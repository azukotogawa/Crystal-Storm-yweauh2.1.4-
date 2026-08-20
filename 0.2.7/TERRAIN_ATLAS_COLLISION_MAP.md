# Live terrain ID → atlas cell → gameplay, and how to unshare

No voxel IDs, mesh, shader, or atlas **size** change. The pipeline stays:
`VoxelTypes.ATLAS_COORDS` → `get_atlas_coord_for_face` → `ChunkView` instance custom `(col,row)` on `Cube.png` 7×10 × 32.

## How a cell is chosen at runtime

1. `tile_map` = build tile **or** feature override **or** `_compute_surface_tile`.
2. Top / ramp: `ATLAS_COORDS[id]`.
3. Sides 3–6: grass family → `DIRT (3,2)`; forest/hills → `TREE_TRUNK (2,3)`; snow → `STONE2 (2,4)`; stone family → own cell; else own cell.
4. Bottom 2: always `DIRT2 (0,6)` — **not emitted**.

## Every ID → cell → who actually draws it

| ID | Name | Cell | Drawn as | Live usage |
| ---: | --- | --- | --- | --- |
| 255 | AIR | (6,0) | never | empty / cave air |
| 0 | OCEAN | **(0,0)** | top+side | ±X deep ocean |
| 1 | OCEAN2 | **(0,0)** | top+side | ±X shallower ocean |
| 2 | OCEAN3 | (0,0) | unused | table only |
| 3 | BEACH | (0,1) | top+side | ocean landfall (`surf ≥ sea`) |
| 4–5 | BEACH2/3 | (1,1)/(2,1) | unused | table only |
| 6 | GRASSLAND | (0,2) | top; side=DIRT | plains grass, marsh |
| 7 | GRASSLAND2 | (1,2) | top; side=DIRT | meadow + flower override |
| 8 | GRASSLAND3 | **(2,2)** | top; side=DIRT | plains + tall-grass override |
| 9 | GRASSLAND4 | **(3,1)** | top; side=DIRT | **steppe — Batch 03 unshared from DIRT** |
| 10 | GRASSLAND5 | (4,2) | top; side=DIRT | savanna |
| 11 | HILLS | (0,3) | top; side=TREE_TRUNK | **forest biome** |
| 12 | HILLS2 | (1,3) | top; side=TREE_TRUNK | dense forest + fern override |
| 13 | HILLS3 | **(3,3)** | top; side=TREE_TRUNK | pine — **Batch 05 unshared from TREE_TRUNK** |
| 14 | HILLS4 | **(4,3)** | top; side=TREE_TRUNK | jungle — **Batch 05 BUSH moved off this cell** |
| 15 | MOUNTAIN | (0,4) | unused | table; shares STONE |
| 16 | MOUNTAIN2 | (1,4) | top+side | highland / mid mountain border |
| 17 | MOUNTAIN3 | **(3,5)** | top+side | high border — **Batch 05 unshared from STONE2** |
| 18–21 | MOUNTAIN4–7 | (3–6,4) | unused | table |
| 22–23 | SNOW / SNOW2 | (0,5)/(1,5) | top; side=STONE2 | cold map temp |
| 24 | SNOW3 | (2,5) | unused | table |
| 25 | VALLEY | (0,6) | unused | shares DIRT2 |
| 26–27 | VALLEY2/3 | (1,6)/(2,6) | unused | table |
| 28–30 | DESERT* | (0–2,7) | unused | table |
| 31–33 | TUNDRA* | (0–2,8) | unused | table |
| 34 | BASIN | (0,9) | top+side | steppe/marsh dry patches |
| 35–36 | BASIN2/3 | (1,9)/(2,9) | unused | table |
| 37 | RIVER | **(1,0)** | top+side | river ribbons |
| 38 | WATER | **(1,0)** | top+side | town port puddles — **shares RIVER** |
| 39 | STONE | **(0,4)** | top+side | mountain border, cave mouths, stone-wall fill, dig strata |
| 40 | STONE2 | **(2,4)** | top+side | ruin 3×3, snow sides, some cave mouths |
| 41 | DIRT | **(3,2)** | top+side | grass **sides**, wood/gate/bridge fill — **shares steppe + farmland** |
| 42 | DIRT2 | (0,6) | top+side when meshed | dig strata **under a DIRT top** (2+ layers); unused bottoms |
| 43 | CAVE_STONE | (4,4) | only if MESH_CAVES | deep stone |
| 44 | CRYSTAL | (6,2) | unused on terrain | crystal is off-atlas |
| 45 | GRASS_TUFT | **(5,2)** | top; side=DIRT | veg override — **Batch 05 unshared from GRASSLAND2** |
| 46 | BUSH | **(5,3)** | top+side | veg override — **Batch 05 unshared from HILLS4** |
| 47 | TREE_TRUNK | **(2,3)** | top+side | forest **sides** + tree-base tops |
| 48 | FARMLAND | **(4,1)** | top; side=DIRT | town plots — **Batch 03 unshared from DIRT** |
| 49 | TOWN_PATH | **(5,1)** | top; side=DIRT | town disks — **Batch 03 unshared from GRASSLAND3** |

## Collisions that matter (player can see the clash)

| Cell | Occupants | Why it hurts |
| --- | --- | --- |
| (3,2) | DIRT only (Batch 03) | Steppe/farm unshared. |
| (2,2) | GRASSLAND3 only (Batch 03) | Town path unshared. |
| (2,3) | TREE_TRUNK only (Batch 05) | Pine unshared. |
| (4,3) | HILLS4 only (Batch 05) | Bush unshared. |
| (1,2) | GRASSLAND2 only (Batch 05) | Tuft unshared. |
| (2,4) | STONE2 only (Batch 05) | Mountain3 unshared. |
| (0,4) | STONE + MOUNTAIN | MOUNTAIN not emitted — **leave shared**. |
| (1,0) | RIVER + WATER | Port puddles = river — **leave shared**. |
| (0,0) | OCEAN + OCEAN2 + OCEAN3 | Depth family — **leave shared**. |
| (0,6) | DIRT2 + VALLEY | VALLEY not emitted — **leave shared**. |

## How to separate **without** breaking the pipeline

Do **not** add a second atlas, change voxel IDs, or change greedy meshing.

`Cube.png` already has unused black cells. Re-point **only** `ATLAS_COORDS` for the clash IDs onto empty cells, then paint those cells. `get_atlas_coord_for_face` keeps working (it reads `ATLAS_COORDS`).

Suggested unused targets (currently empty / black):

| ID to unshare | New cell | Why that hole |
| --- | --- | --- |
| GRASSLAND4 (steppe top) | **(3,1)** | Next to beach row; free. Sides stay DIRT. |
| FARMLAND | **(4,1)** | Free. Sides stay DIRT. |
| TOWN_PATH | **(5,1)** | Free. Sides stay DIRT. |
| HILLS3 (pine top) | **(3,3)** | Free on forest row. Sides stay TREE_TRUNK. |
| BUSH | **(5,3)** | Free. HILLS4 keeps (4,3). |
| GRASS_TUFT | **(5,2)** | Free. GRASSLAND2 keeps (1,2). |
| MOUNTAIN3 | **(3,5)** | Free on snow row. STONE2 keeps (2,4). |

Order to do it (later batch, not Batch 01):

1. GRASSLAND4 → (3,1) — biggest live lie (steppe = dirt). **Done — Batch 03.**
2. TOWN_PATH → (5,1) and FARMLAND → (4,1). **Done — Batch 03.**
3. HILLS3 → (3,3) so pine ≠ bark. **Done — Batch 05.**
4. BUSH → (5,3), GRASS_TUFT → (5,2). **Done — Batch 05.**
5. MOUNTAIN3 → (3,5). **Done — Batch 05.**

**Do not** move DIRT, TREE_TRUNK, STONE, RIVER, or OCEAN. Those are the family side/fill tiles the remapper already points at.

Batch 03 remapped GRASSLAND4 / FARMLAND / TOWN_PATH. Batch 05 remapped HILLS3 / BUSH / GRASS_TUFT / MOUNTAIN3 onto (3,3)/(5,3)/(5,2)/(3,5) and painted HILLS4 on freed (4,3). Live clash occupants left: **none** (WATER still shares RIVER; OCEAN family; unused P3 shares).
