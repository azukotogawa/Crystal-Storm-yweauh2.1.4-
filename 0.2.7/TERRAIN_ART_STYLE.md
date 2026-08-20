# Crystal Storm terrain art style

Style anchor: the shipped authored structures  
`wood_wall`, `stone_wall`, `gate`, `bridge`, `ruin_pillar`, `town_hall`.

**Forbids photoreal.** Terrain is not photoreal. It is the ground those props sit on. If the dirt looks like a photo and the palisade looks like a painted 256 nearest atlas, the world splits in half.

## What the structures already decided

| Structure | Read at iso | Palette | Detail scale |
| --- | --- | --- | --- |
| wood_wall | dark palisade, short cap | bark / rope / dirt | large logs, not bark pores |
| stone_wall | merlon block | grey masonry / moss | block joints, not granite speckle |
| gate | two posts + lintel | honey timber / iron | iron bands, empty middle |
| bridge | deck + rails | cool slate / rope | planks and rails, not grain photos |
| ruin_pillar | broken column | ochre drums / rubble | cracks + collar, not lichen photos |
| town_hall | pitched hall | plaster / terracotta / timber | tiles and framing, not stucco noise |

Rules those assets already follow (copy them):

- Readable from the **gameplay camera** (ortho iso ≈ −35.264 / 45, zoom ~10–18).
- **Hand-authored** shapes and hues, not photos.
- **Nearest-filter** friendly: hard value steps, 1–2 px joints, no 1 px sparkle.
- **Limited noise.** One material = one value band + a few marks.
- Strong **material differentiation** (you never confuse slate deck with honey gate).
- Small faces: a voxel top is ~one screen inch at play zoom. If you cannot name the material at that size, the tile is too busy.

## Terrain-specific rules

1. **Top and side are different jobs.** Grass tops are hue; dirt/stone sides are the cliff/wall the player stares at while digging and building. Author both. Do not stamp the same chip on every face.
2. **One read per tile.** Plains = “green carpet.” River = “dark water band.” Stone = “cool rock.” No 12-color photographs.
3. **Value first, hue second.** Iso lighting already multiplies sides by 0.68 (`ChunkView.gdshader`). Paint sides slightly lighter than you think so they do not turn to mud after the shader.
4. **No photoreal source photos** on the atlas. Structure authors already convert photos into stylized 256 atlases; terrain tiles are even smaller (32 px). A photo just becomes grey static.
5. **Sit under the props.** Ground is a step duller and cooler than structure wood/plaster so walls and halls pop. Exception: town path / farmland should be obviously *worked* ground, not another grass chip.
6. **Seams must tile.** Greedy meshing stretches UVs by `uv_w` / `uv_h` across merged quads (`fract(UV * voxel_tiling)`). A tile that does not wrap will stripe every river and cliff.
7. **Do not fight the 1 px atlas pad.** Shader insets each cell by `1/32`. Keep important marks inside the inner 30×30.

## Color / value relationships

Keep a short ground palette that does not collide with structures:

| Family | Top | Side | Avoid |
| --- | --- | --- | --- |
| Grass / plains | mid green, few tuft marks | warm dirt | same brown-green as current DIRT/GRASSLAND4 collision |
| Steppe / savanna | dry olive / tan-green | same dirt, slightly paler | desert photo sand |
| Forest | deep green canopy flecks | bark-brown (TREE_TRUNK slot) | black-green that reads as hole |
| Marsh | wetter, darker green | darker dirt | identical to plains |
| River / ocean | two blues: deep rim vs river | same family, darker | transparent water shader (not this milestone) |
| Beach | warm sand, low contrast | sand | coral detail |
| Stone / mountain | cool grey, large cracks | same, more joint | merlon copy of stone_wall |
| Snow | high-value, blue shadow | STONE2 rock | pure white blowout |
| Basin | khaki mud, cracked | mud | salt-flat photoreal |
| Town path | packed earth / pale stone | dirt | another grass chip |
| Farmland | furrowed brown-green | dirt | same texel as DIRT |

Crystal stays **off this atlas** (emissive cluster). Do not paint a purple dirt tile “so crystal matches.”

## Recommended resolution per category

| Category | Author | Ship on `Cube.png` | Why |
| --- | --- | --- | --- |
| All chunk terrain tiles (P0–P2) | 32×32 (or 64×64 then downsample) | **32×32** | Live atlas and shader pad assume 32. 48 px is a stale doc. |
| Shared side tiles (DIRT, TREE_TRUNK, STONE2, DESERT3) | 32×32 | 32×32 | Repeated on every cliff; noise is punished |
| Rare / unused (P3) | do not author | leave black / existing chip | Not drawn |
| Crystal / vegetation / structures | existing 256 structure atlas or generated sprites | **not** `Cube.png` | Different pipelines |

Do not put 256 px terrain faces on the chunk atlas. The shader would shrink them to 32 and they would shimmer.

## Face / UV strategy (stay on the live picker)

Keep `get_atlas_coord_for_face`. Do not invent a second UV path.

| Face | When drawn | What to author |
| --- | --- | --- |
| TOP (`0`) | Every column | The biome identity chip |
| SIDES (`3–6`) | Cliffs, digs, raised fill lips | Family side tile (dirt / bark / rock) |
| RAMPS (`7–9`) | Use **top** coord today | Same as top; extra ramp texture is out of scope |
| BOTTOM (`2`) | **Not emitted** | Recorded only; do not spend art on it |

Author **top + side** for every P0 family. Variants (meadow / savanna / pine) can be top-only hue shifts that reuse the family side.

Because greedy quads tile with `fract`, every terrain tile must be **seamless on both axes**.

## One atlas vs per-material assets

**Stay on one atlas for chunk terrain.**

Reasons (locked renderer, not taste):

- `ChunkView` binds a single `texture_atlas` and encodes `(col, row)` in instance custom.
- Greedy MultiMesh is one material per face-direction stream.
- Per-voxel `StandardMaterial3D` (the structure path) would explode draw calls on the heightfield.

**How to author without changing the renderer:**

1. Paint individual 32×32 tiles (or a small working PSD/atlas).
2. Composite them into `assets/tiles/Cube.png` at the **existing** `ATLAS_COORDS` slots.
3. Only request new atlas cells when two live types that must look different currently **share a slot** (see inventory collisions: `DIRT`/`GRASSLAND4`/`FARMLAND`, `TOWN_PATH`/`GRASSLAND3`, `TREE_TRUNK`/`HILLS3`). That slot-split is a later, explicit atlas-index change — not this audit.

Do **not** move terrain onto the structure `AUTHORED_BUILDING_*` maps. Those IDs are buildings.

## First 5–10 types to author

Order is “player stares at this every minute,” then “unshare a collision,” then “biome identity.”

| # | ID | Name | Slot | Faces | Note |
| ---: | ---: | --- | --- | --- | --- |
| 1 | 8 | GRASSLAND3 | (2,2) | top | Default plains. **Will also paint town paths until TOWN_PATH gets its own cell.** |
| 2 | 41 | DIRT | (3,2) | top+side | Grass sides + wood/gate/bridge fill. **Currently also GRASSLAND4 and FARMLAND.** Author as dirt; accept steppe/farm look wrong until unshare. |
| 3 | 37 | RIVER | (1,0) | top | Also paints WATER. Fine to share. |
| 4 | 39 | STONE | (0,4) | top+side | Border, cliffs, stone-wall fill. Also paints unused MOUNTAIN. |
| 5 | 11 | HILLS | (0,3) | top | Forest identity. Sides already remap to TREE_TRUNK. |
| 6 | 47 | TREE_TRUNK | (2,3) | top+side | Forest cliffs **and** tree-base tops (veg tile override). Also paints HILLS3 tops. |
| 7 | 0 | OCEAN | (0,0) | top | Rim. Also paints OCEAN2/3. |
| 8 | 3 | BEACH | (0,1) | top | Landfall. |
| 9 | 40 | STONE2 | (2,4) | top+side | Ruin pads + snow sides. Also paints MOUNTAIN3. |
| 10 | 42 | DIRT2 | (0,6) | top+side | Dig strata / subsoil. |

After those ten, unshare atlas cells (pipeline change) then author **TOWN_PATH**, **FARMLAND**, **GRASSLAND4**, **SNOW**, **BASIN**.

Do not start desert / tundra / valley / unused mountain rows. They are P3 and not emitted.

## Photoreal is a fail

A tile fails this guide if:

- it is a cropped photo,
- it needs a 256 crop to “look good,”
- top and side are indistinguishable at iso zoom 14,
- it collides in hue with honey gate, slate bridge, or ochre ruin,
- it sparkles under nearest filter.

A tile passes if a new player can name the material (“grass,” “river,” “dirt wall,” “forest,” “town dirt”) at gameplay camera distance in one look.
