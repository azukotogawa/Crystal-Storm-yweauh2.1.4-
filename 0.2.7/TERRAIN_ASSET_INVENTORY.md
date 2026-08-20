# Crystal Storm terrain / voxel inventory

Audit of every integer ID in `helpers/voxel_types.gd` (`AIR` through `TOWN_PATH`).  
No textures were authored in this pass. No voxel IDs, atlas indices, worldgen, or mesh code were changed.

## Live pipeline (source of truth)

| Item | Live value | Stale notes |
| --- | --- | --- |
| Atlas file | `res://assets/tiles/Cube.png` (`ChunkView` preload) | — |
| Grid | 7 columns × 10 rows (`ATLAS_GRID_*`) | — |
| Tile size | **32 px** (`ATLAS_TILE_PIXELS`); file is 224×320 | `KNOWLEDGE_BASE.md` / `AI_CONTEXT.md` still say 48 px — ignore those |
| Shader | `shaders/ChunkView.gdshader` — nearest filter, 1 px pad, `atlas_grid = vec2(7,10)` | — |
| Face picker | `VoxelTypes.get_atlas_coord_for_face(tile, face_code)` | — |
| Face codes | `0` TOP, `2` BOTTOM, `3–6` sides, `7–9` ramps | Face `1` is unused |
| BOTTOM | Always remaps to `DIRT2` **if** asked. Production mesher **does not emit** `FACE_BOTTOM` (heightfield tops + side lips + ramps only). | Do not author bottoms as P0 work |
| Default missing tile | `Vector2i(6, 0)` (black unused cell) | — |

### Face remap (all types)

`get_atlas_coord_for_face`:

- `face_code <= 0` or `>= 7` (TOP + ramps): that type’s own `ATLAS_COORDS` entry.
- `face_code == 2` (BOTTOM, unused): **always** `DIRT2` → `(0, 6)`.
- Sides `3–6`:
  - grass family → `DIRT` `(3, 2)`
  - forest / hills family → `TREE_TRUNK` `(2, 3)`
  - snow / tundra family → `STONE2` `(2, 4)`
  - stone / mountain / valley / basin / cave → **own** coord
  - desert family → `DESERT3` `(2, 7)`
  - everything else → own coord

Shader then darkens sides (`×0.68`) and bottoms (`×0.48`).

### What current worldgen / mesh actually draws

**Interior biomes** (`BiomeLayout.INTERIOR_BIOMES`): plains, steppe, forest, marsh, highland.  
**Borders** (`WorldBorder`): ±X ocean, ±Z mountain.

`InfiniteNoiseWorld._compute_surface_tile` emits only:

| Source | IDs |
| --- | --- |
| Ocean border | `OCEAN`, `OCEAN2`, `BEACH` |
| Mountain border | `STONE`, `MOUNTAIN2`, `MOUNTAIN3`, `SNOW2` |
| Rivers | `RIVER` |
| Cave-mouth / steep | `STONE`, `STONE2` |
| Plains patches | `GRASSLAND`, `GRASSLAND2`, `GRASSLAND3`, `GRASSLAND4`, `GRASSLAND5`, `SNOW`, `SNOW2` |
| Steppe | `GRASSLAND4`, `GRASSLAND5`, `SNOW`, `SNOW2`, `BASIN` |
| Forest | `HILLS`, `HILLS2`, `HILLS3`, `HILLS4`, `GRASSLAND2` |
| Marsh | `GRASSLAND`, `GRASSLAND2`, `BASIN` |
| Highland | `MOUNTAIN2`, `MOUNTAIN3`, `STONE`, `STONE2`, `GRASSLAND`, `GRASSLAND2` |

**Overlays (not worldgen noise, still chunk-mesh tiles):**

- Player walls / gates / bridges: `DIRT` or `STONE` tile_id on raised fill (`building_registry.gd`).
- Town stamp (`town_manager._stamp_town_ground`): `TOWN_PATH`, `FARMLAND`, occasional `WATER`.
- Ruin stamp (`ruin_manager._stamp_ruin`): `STONE2` on the center 3×3.
- Vegetation stamp (`vegetation_manager.gd` `_try_place_vegetation` → `FeatureRegistry.set_tile_override` → `get_tile_type` / `get_tile_type_worker`): `TREE_TRUNK` (tree bases), `BUSH`, `GRASS_TUFT`, plus some flowers/ferns remapped onto `GRASSLAND2` / `GRASSLAND3` / `HILLS2`. These **are** heightfield surface tiles. Voxel props / billboards sit on top of the same cells.

**Off the chunk atlas:**

- Crystal: `CrystalPresentation` + `CrystalClusterMesh` + `StandardMaterial3D` (magenta emissive). ID `CRYSTAL` exists in the atlas but is not the live crystal look.
- Vegetation **props** (the 3D tuft/bush/tree models) are `VoxelPropBuilder` / billboards — the **ground tile** under them is still the override above.
- Standing channel water: sim in `ChannelRegistry`; visible water on the heightfield is still `RIVER`/`WATER` atlas tiles.

`MESH_CAVES` defaults **false**. `CAVE_STONE` / deep `get_voxel` IDs are not drawn unless cave meshing is turned on.

`Cube.png` is a **placeholder atlas**: flat noisy color chips, many black unused cells. None of these tiles match the authored structure set (256 nearest plaster / timber / masonry). Treat the whole atlas as procedural/placeholder unless noted.

---

## Master table

Columns: ID, name, atlas `(col,row)`, top / side / bottom (after `get_atlas_coord_for_face`), gameplay, faces needed, class, unique?, share?, current look, priority.

| ID | Name | Atlas | Top | Side | Bottom* | Where it appears | Faces | Class | Unique authored? | Can share | Current look | Pri |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 255 | AIR | (6,0) | — | — | — | Empty / dug / cave air. Not a surface tile. | none | technical | no | n/a | unused black cell | P3 |
| 0 | OCEAN | (0,0) | (0,0) | (0,0) | (0,6) | ±X deep ocean border (`surf < SEA_LEVEL-6`) | top+side | fluid (solid heightfield) | yes (family) | OCEAN2/3 | flat blue chip | P0 |
| 1 | OCEAN2 | (0,0) | (0,0) | (0,0) | (0,6) | Shallower ocean border | top+side | fluid | share OCEAN | OCEAN | same chip as OCEAN | P0 |
| 2 | OCEAN3 | (0,0) | (0,0) | (0,0) | (0,6) | Table only (`shallow sea` map). **Not emitted.** | top+side | fluid | share OCEAN | OCEAN | unused / same chip | P3 |
| 3 | BEACH | (0,1) | (0,1) | (0,1) | (0,6) | Ocean border above sea level | top+side | solid | yes | BEACH2 | yellow sand chip | P0 |
| 4 | BEACH2 | (1,1) | (1,1) | (1,1) | (0,6) | Table (`sandy beach`). **Not emitted.** | top+side | solid | share BEACH | BEACH | sand variant chip | P3 |
| 5 | BEACH3 | (2,1) | (2,1) | (2,1) | (0,6) | Table (`coral reef`). **Not emitted.** | top+side | solid | no (legacy) | BEACH | sand variant chip | P3 |
| 6 | GRASSLAND | (0,2) | (0,2) | DIRT (3,2) | (0,6) | Plains “grass”, marsh default | top+side | solid / grass | yes (grass family) | GRASSLAND2/3 | bright green chip | P0 |
| 7 | GRASSLAND2 | (1,2) | (1,2) | DIRT | (0,6) | Meadow patches (plains/forest/marsh/highland) | top+side | solid / grass | hue variant | GRASSLAND | yellow-green chip | P0 |
| 8 | GRASSLAND3 | (2,2) | (2,2) | DIRT | (0,6) | Plains default + `biome_to_voxel_id` fallback | top+side | solid / grass | hue variant | GRASSLAND | mid green chip | P0 |
| 9 | GRASSLAND4 | (3,1) | (3,1) | DIRT | (0,6) | Steppe. **Batch 03 unshared from DIRT.** | top+side | solid / grass | yes (dry grass) | own | dry olive-tan | P0 |
| 10 | GRASSLAND5 | (4,2) | (4,2) | DIRT | (0,6) | Savanna / hot steppe | top+side | solid / grass | hue variant | GRASSLAND4 | pale green chip | P0 |
| 11 | HILLS | (0,3) | (0,3) | TREE_TRUNK (2,3) | (0,6) | Forest biome | top+side | solid / forest | yes (canopy) | HILLS2 | dark green chip | P0 |
| 12 | HILLS2 | (1,3) | (1,3) | TREE_TRUNK | (0,6) | Dense forest | top+side | solid / forest | hue variant | HILLS | darker green | P1 |
| 13 | HILLS3 | (3,3) | (3,3) | TREE_TRUNK | (0,6) | Pine forest. **Batch 05 unshared from TREE_TRUNK.** | top+side | solid / forest | yes (pine) | own | pine needles | P1 |
| 14 | HILLS4 | (4,3) | (4,3) | TREE_TRUNK | (0,6) | Jungle. **Batch 05 BUSH moved off.** | top+side | solid / forest | hue variant | HILLS | jungle clumps | P1 |
| 15 | MOUNTAIN | (0,4) | (0,4) | own | (0,6) | Table (`mountain`). **Not emitted** (border uses STONE). | top+side | solid / stone | share STONE | STONE | grey rock grid | P3 |
| 16 | MOUNTAIN2 | (1,4) | (1,4) | own | (0,6) | Highland mid + border mid. **Batch 04.** | top+side | solid / stone | own | STONE | cool blue-grey plates | P1 |
| 17 | MOUNTAIN3 | (3,5) | (3,5) | own | (0,6) | Highland high + cold border peak. **Batch 05 unshared from STONE2.** | top+side | solid / stone | own | STONE2 | cool peak plates | P1 |
| 18 | MOUNTAIN4 | (3,4) | (3,4) | own | (0,6) | Table (`volcano`). **Not emitted.** | top+side | solid / stone | no | STONE | grey rock | P3 |
| 19 | MOUNTAIN5 | (4,4) | (4,4) | own | (0,6) | Table (`precipice`). **Same cell as CAVE_STONE.** Not emitted. | top+side | solid / stone | no | CAVE_STONE | grey rock | P3 |
| 20 | MOUNTAIN6 | (5,4) | (5,4) | own | (0,6) | Table (`zenith`). **Not emitted.** | top+side | solid / stone | no | STONE | grey rock | P3 |
| 21 | MOUNTAIN7 | (6,4) | (6,4) | own | (0,6) | Table (`plateau`). **Not emitted.** | top+side | solid / stone | no | STONE | grey rock | P3 |
| 22 | SNOW | (0,5) | (0,5) | STONE2 | (0,6) | Cold plains/steppe. **Batch 04.** | top+side | solid / snow | yes | SNOW2 | high-value blue shadow | P1 |
| 23 | SNOW2 | (1,5) | (1,5) | STONE2 | (0,6) | Cold steppe + high cold border. **Batch 04.** | top+side | solid / snow | hue variant | SNOW | icier blue | P1 |
| 24 | SNOW3 | (2,5) | (2,5) | STONE2 | (0,6) | Table (`glacier`). **Not emitted.** | top+side | solid / snow | share SNOW | SNOW | white chip | P3 |
| 25 | VALLEY | (0,6) | (0,6) | own | (0,6) | Table (`ravine`). **Same cell as DIRT2.** Not emitted. | top+side | solid / stone | no | DIRT2 | brown stripe chip | P3 |
| 26 | VALLEY2 | (1,6) | (1,6) | own | (0,6) | Table (`canyon`). **Not emitted.** | top+side | solid / stone | no | DIRT2 | brown chip | P3 |
| 27 | VALLEY3 | (2,6) | (2,6) | own | (0,6) | Table (`valley`). **Not emitted.** | top+side | solid / stone | no | DIRT2 | brown chip | P3 |
| 28 | DESERT | (0,7) | (0,7) | DESERT3 | (0,6) | Table only. **Not emitted.** | top+side | solid / desert | no until desert biome | DESERT2 | tan chip | P3 |
| 29 | DESERT2 | (1,7) | (1,7) | DESERT3 | (0,6) | Table (`dunes`). **Not emitted.** | top+side | solid / desert | no | DESERT | tan chip | P3 |
| 30 | DESERT3 | (2,7) | (2,7) | own | (0,6) | Table (`badlands`) + desert **side** remap. Not emitted as a surface. | side only if desert exists | solid / desert | no | DESERT | tan chip | P3 |
| 31 | TUNDRA | (0,8) | (0,8) | STONE2 | (0,6) | Table only. **Not emitted** (cold uses SNOW). | top+side | solid / snow | share SNOW | SNOW | grey-white chip | P3 |
| 32 | TUNDRA2 | (1,8) | (1,8) | STONE2 | (0,6) | Table. **Not emitted.** | top+side | solid / snow | share SNOW | SNOW | grey-white | P3 |
| 33 | TUNDRA3 | (2,8) | (2,8) | STONE2 | (0,6) | Table. **Not emitted.** | top+side | solid / snow | share SNOW | SNOW | grey-white | P3 |
| 34 | BASIN | (0,9) | (0,9) | own | (0,6) | Steppe rugged + marsh dry-lake patches. **Batch 04.** | top+side | solid | yes (dry mud) | BASIN2 | khaki cracks | P1 |
| 35 | BASIN2 | (1,9) | (1,9) | own | (0,6) | Table (`salt flat`). **Not emitted.** | top+side | solid | share BASIN | BASIN | khaki chip | P3 |
| 36 | BASIN3 | (2,9) | (2,9) | own | (0,6) | Table (`basin`). **Not emitted.** | top+side | solid | share BASIN | BASIN | khaki chip | P3 |
| 37 | RIVER | (1,0) | (1,0) | (1,0) | (0,6) | River ribbons (as common as a biome) | top+side | fluid | yes | WATER | darker blue chip | P0 |
| 38 | WATER | (1,0) | (1,0) | (1,0) | (0,6) | Town port puddles (`town_manager`). Same cell as RIVER. | top+side | fluid | share RIVER | RIVER | same as RIVER | P2 |
| 39 | STONE | (0,4) | (0,4) | own | (0,6) | Mountain border, cave mouths, highland, **stone_wall fill**, dug strata | top+side | solid / stone | yes | MOUNTAIN | grey rock | P0 |
| 40 | STONE2 | (2,4) | (2,4) | own | (0,6) | Cave mouths, highland, **ruin 3×3**, snow **sides** | top+side | solid / stone | yes (worn) | MOUNTAIN3 | grey rock | P0 |
| 41 | DIRT | (3,2) | (3,2) | own | (0,6) | **Grass/farm/town sides**; wood/gate/bridge **raised fill**; dug grass strata. **Shares cell with GRASSLAND4.** | top+side | solid | yes | own (conflict) | brown-green chip | P0 |
| 42 | DIRT2 | (0,6) | (0,6) | own | (0,6) | Subsoil `get_voxel`; unused BOTTOM; shares cell with VALLEY | top+side | solid | yes (subsoil) | VALLEY | brown stripe | P0 |
| 43 | CAVE_STONE | (4,4) | (4,4) | own | (0,6) | Deep `get_voxel` only. **Not meshed** while `MESH_CAVES=false`. | top+side if caves on | solid / stone | share STONE | STONE | grey rock | P2 |
| 44 | CRYSTAL | (6,2) | (6,2) | own | (0,6) | Atlas placeholder. **Live crystal is off-atlas** (cluster mesh + emissive material). | n/a on terrain | crystal | no (keep off-atlas) | n/a | black/unused cell | P2 |
| 45 | GRASS_TUFT | (5,2) | (5,2) | DIRT | (0,6) | Veg tile override. **Batch 05 unshared from GRASSLAND2.** | top+side | vegetation / solid | own | GRASSLAND2 | bright tufts | P1 |
| 46 | BUSH | (5,3) | (5,3) | own | (0,6) | Veg tile override. **Batch 05 unshared from HILLS4.** | top+side | vegetation / solid | own | HILLS4 | round pad | P1 |
| 47 | TREE_TRUNK | (2,3) | (2,3) | own | (0,6) | Forest **sides** + **tree-base tops** (veg override on TREE cells). Shares cell with HILLS3. | top+side | vegetation / solid | yes as forest side + tree pad | HILLS3 | dark green/bark | P0 |
| 48 | FARMLAND | (4,1) | (4,1) | DIRT | (0,6) | Town plots. **Batch 03 unshared from DIRT.** | top+side | solid / grass | yes | own | furrowed rows | P1 |
| 49 | TOWN_PATH | (5,1) | (5,1) | DIRT | (0,6) | Town center disks. **Batch 03 unshared from GRASSLAND3.** | top+side | solid / grass | yes | own | packed earth | P1 |

\*Bottom is recorded because the picker defines it. The live mesher never submits `face_code == 2`.

---

## P0 — player sees constantly

Only IDs the **current mesh actually draws** on a normal play session (default quality, caves off).

| ID | Name | Why P0 |
| ---: | --- | --- |
| 6 | GRASSLAND | Plains grass + marsh |
| 7 | GRASSLAND2 | Meadow patches in most biomes |
| 8 | GRASSLAND3 | Plains + fallback |
| 9 | GRASSLAND4 | Steppe (and currently dirt’s atlas cell) |
| 10 | GRASSLAND5 | Savanna / hot steppe |
| 11 | HILLS | Forest |
| 37 | RIVER | River network ~ biome-sized |
| 39 | STONE | Border, cliffs, stone-wall fill, dig strata |
| 40 | STONE2 | Ruin pads, cave mouths, snow sides |
| 41 | DIRT | Universal grass **side** + wood/gate/bridge fill |
| 42 | DIRT2 | Dig/subsoil read; unused bottom |
| 0 / 1 | OCEAN / OCEAN2 | ±X ocean rim |
| 3 | BEACH | Ocean landfall |
| 47 | TREE_TRUNK | Forest **sides** and **tree-base tops** (veg override) |

## P1 — important biome / landscape

Drawn, but not every session / every frame.

| ID | Name | Why P1 |
| ---: | --- | --- |
| 12–14 | HILLS2–4 | Dense / pine / jungle forest variants |
| 16–17 | MOUNTAIN2–3 | Highland + high border |
| 22–23 | SNOW / SNOW2 | Cold map-temperature |
| 34 | BASIN | Steppe/marsh dry patches |
| 45 | GRASS_TUFT | Common veg-stamp tops (chunk tiles, not just props) |
| 46 | BUSH | Bush-cell tops (chunk tiles) |
| 48 | FARMLAND | Town plots (needs its own tile — currently aliases dirt) |
| 49 | TOWN_PATH | Town disks (currently aliases plains grass) |

## P2 — special / rare

| ID | Name | Why P2 |
| ---: | --- | --- |
| 38 | WATER | Port puddles only; same pixels as RIVER |
| 43 | CAVE_STONE | Only if `MESH_CAVES` on |
| 44 | CRYSTAL | Off-atlas presentation; atlas cell unused |

## P3 — technical / unused / non-visible

| ID | Name | Why P3 |
| ---: | --- | --- |
| 255 | AIR | Never textured |
| 2 | OCEAN3 | Not emitted |
| 4–5 | BEACH2–3 | Not emitted |
| 15, 18–21 | MOUNTAIN, MOUNTAIN4–7 | Not emitted |
| 24 | SNOW3 | Not emitted |
| 25–27 | VALLEY* | Not emitted; (0,6) is DIRT2 |
| 28–30 | DESERT* | Not emitted |
| 31–33 | TUNDRA* | Not emitted (cold uses SNOW) |
| 35–36 | BASIN2–3 | Not emitted |

No P0 row is an ID the current mesh never draws.

---

## Shared-cell collisions (authoring blockers)

These IDs **point at the same `Cube.png` cell today**. First-author work must either accept a shared material or assign new atlas slots (that assignment is a later pipeline change — not this audit).

| Cell | IDs sharing it |
| --- | --- |
| (0,0) | OCEAN, OCEAN2, OCEAN3 |
| (1,0) | RIVER, WATER |
| (2,2) | GRASSLAND3, TOWN_PATH |
| (3,2) | GRASSLAND4, DIRT, FARMLAND |
| (2,3) | HILLS3, TREE_TRUNK |
| (4,3) | HILLS4, BUSH |
| (0,4) | MOUNTAIN, STONE |
| (2,4) | MOUNTAIN3, STONE2 |
| (4,4) | MOUNTAIN5, CAVE_STONE |
| (0,6) | VALLEY, DIRT2 |
| (1,2) | GRASSLAND2, GRASS_TUFT |

---

## Off-atlas visuals (stay off the terrain atlas)

| Visual | Path | Do not put on Cube.png |
| --- | --- | --- |
| Crystal clusters | `crystal/crystal_presentation.gd` + `helpers/crystal_cluster_mesh.gd` + magenta `StandardMaterial3D` | Crystal is a growing entity, not a biome tile |
| Vegetation | `VoxelPropBuilder` / generated billboards | Plants sit **on** terrain |
| Authored structures | `assets/structures/*` via `GameVisualRegistry` | Already a separate 256 nearest pipeline |
| Channel water sim | `ChannelRegistry` / `VoxelFluidService` | Visible water is still RIVER/WATER tiles |

---

## Coverage checklist (all 51 IDs)

`255, 0–49` — each appears once in the master table above.
