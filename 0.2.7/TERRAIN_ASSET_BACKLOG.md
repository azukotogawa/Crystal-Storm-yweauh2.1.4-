# Terrain asset backlog

Derived from `TERRAIN_ASSET_INVENTORY.md`. No textures in this pass.

## Now (P0 — first author pass)

Author into **existing** `Cube.png` slots. 32×32, nearest, seamless, top + family side. See `TERRAIN_ART_STYLE.md` first-ten table.

1. GRASSLAND3 `(2,2)` — plains top
2. DIRT `(3,2)` — universal side / raised fill
3. RIVER `(1,0)` — water
4. STONE `(0,4)` — rock
5. HILLS `(0,3)` — forest top
6. TREE_TRUNK `(2,3)` — forest side + tree-base tops (veg override)
7. OCEAN `(0,0)` — ocean rim
8. BEACH `(0,1)` — shore
9. STONE2 `(2,4)` — ruin / snow side
10. DIRT2 `(0,6)` — subsoil / dig

Then hue-shift (same side tile): GRASSLAND, GRASSLAND2, GRASSLAND5, HILLS2. **Done — Batch 02** (`TERRAIN_BATCH_02_REPORT.md`).

P1 veg stamps already on the mesh (`GRASS_TUFT` shares GRASSLAND2, `BUSH` shares HILLS4) — they come along with those tops until cells are unshared.

## Next (P1)

Batch 03 unshared GRASSLAND4 / TOWN_PATH / FARMLAND onto unused holes (`TERRAIN_BATCH_03_REPORT.md`).

Still own-cell placeholders:

- MOUNTAIN2 `(1,4)` — highland / mid border. **Done — Batch 04.**
- BASIN `(0,9)` — steppe/marsh dry mud. **Done — Batch 04.**
- SNOW / SNOW2 `(0,5)/(1,5)` — cold map-temp. **Done — Batch 04.**

Still shared (split later):

- **None among live clash occupants.** Batch 05 unshared HILLS3 / BUSH / GRASS_TUFT / MOUNTAIN3 (`TERRAIN_BATCH_05_REPORT.md`). WATER still shares RIVER by design.

## Later (P2)

- WATER — keep sharing RIVER unless ports need still ponds
- CAVE_STONE — only if `MESH_CAVES` ships on
- Crystal — stay on `CrystalPresentation`, not the terrain atlas

## Do not author (P3)

AIR, OCEAN3, BEACH2/3, MOUNTAIN, MOUNTAIN4–7, SNOW3, VALLEY*, DESERT*, TUNDRA*, BASIN2/3, GRASS_TUFT, BUSH.

## Resolution / layout (repeat)

- Ship 32×32 in the live 7×10 `Cube.png`.
- Keep `get_atlas_coord_for_face`.
- One chunk atlas; do not move terrain onto the structure mesh path.
