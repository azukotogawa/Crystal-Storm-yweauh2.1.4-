# Crystal Storm — character and creature art style

Direction from Cole, 2026-10-14. This file is the art rule for the player, people, wildlife, and crystal creatures. It does not change code, meshes, or textures.

Terrain tiles stay on `TERRAIN_ART_STYLE.md`. Structures stay on the authored wall, gate, bridge, ruin, and hall atlases. Those pipelines are not the character pipeline.

## What a character is

A character or creature is a 3D model made of small cubes. Each cube is a real box in the world, with its own position and face normal.

Do not build characters as:

- billboards
- `Sprite3D`
- a flat sprite region extruded into a slab
- a painted PNG whose pixels are only a front view

The player sheet `assets/player/player.png` and the part rectangles in `assets/player/author_player.gd` are the old front-view layout. `helpers/voxel_creature_builder.gd` still cuts a canvas (`CANVAS` 32, `DEPTH_STEPS` 8) out of a picture. That depth step is a slab thickness, not the cube size in this guide. New character work does not add another picture region.

Gameplay scale stays on the terrain block. `config/world_settings.gd` authors `voxel_scale` at 2.0 world units per column. Do not change `voxel_scale`. A person still stands about one and a half blocks tall, feet on the slab, body inside the existing collider. `ALPHA_VISUAL_CONTRACT.md` already forbids features that read as about one fifth of a terrain block. A mite is shorter than the player. A stag or the origin warden is larger. None of them change the terrain block.

## Cubes per terrain block

**Working proposal: 8 cubes along one terrain block.** Not locked. The other candidate is 16. The open choice is `studio/QUESTIONS.md`. Until that is answered, do not author a second grid size, and do not treat 8 as a shipped constant in code.

One terrain block is `voxel_scale` world units on each side. At 8 cubes per block, one character cube is `voxel_scale / 8` (0.25 world units at the authored scale). At 16 per block, one cube is half of that.

Why 8 is the proposal, at the locked camera:

- The gameplay camera is orthographic. Its size is 16. That size stays 16.
- In Godot that size is half the vertical span, so the frame is 32 world units tall. That is 16 terrain blocks at `voxel_scale` 2.
- A cube at 8 per block is 0.25 / 32 of the frame, about 8 pixels on a 1080p picture. The face still reads as a square.
- A cube at 16 per block is about 4 pixels on that same frame. After the isometric yaw, many faces shrink to a couple of pixels and the model reads as a noisy mesh instead of a stack of cubes.

Use the same cube size for the player and for every creature. A mite is fewer cubes, not smaller cubes. A boss is more cubes, not a finer grid.

Count cubes in block space. The old 16×34 scout pixels and the 32×48 player sheet are not a 16-cubes-per-block model.

## Palette

Albedo is flat. One material is one color. A second color means a second material (skin, cloth, horn, metal), not a darker copy of the same cloth used as shade.

Player materials already tried in `author_player.gd`, kept here as the starting set:

| Material | Color | Job |
| --- | --- | --- |
| Skin | `(0.86, 0.62, 0.42)` | face, hands |
| Hair | `(0.28, 0.16, 0.10)` | hair mass |
| Tunic | `(0.22, 0.42, 0.34)` | the readable body color |
| Belt | `(0.42, 0.28, 0.14)` | waist break |
| Boot | `(0.20, 0.14, 0.10)` | feet against the ground |

Do not add the painted tunic-dark or the painted black outline from that sheet. The dark green was fake shade. The outline was a sprite stroke. Cube edges come from the light falloff below, not from a black shell.

Keep the tunic off terrain green. Ground is the duller carpet in `TERRAIN_ART_STYLE.md`. The player reads as a saturated shape on top of it. Townsfolk can shift the tunic hue. They do not share the crystal purple.

Wildlife gets one family hue per species, plus at most one accent (belly, horn, beak). Value may change between those materials. Value may not change across the same material to fake a light.

No gradients inside a cube. No noise. No photo textures. Nearest filtering, same as the terrain rule: if the mark is smaller than one cube, delete it.

## Light, not painted shade

Shade comes from the face normal and the sun the terrain already uses.

`helpers/terrain_lighting.gd` sets that sun to `Vector3(0.55, 0.82, 0.38)` and writes `terrain_sun_dir`. Do not add a second sun. Do not change this vector.

A top face is the brightest, a face turned away from that sun is darker, and the response is computed. It is not stored in the vertex color. The multipliers baked into the current builders (`_TINT_SIDE` 0.62, `_TINT_BACK` 0.50, `_TINT_TOP` 0.84, `_TINT_BOTTOM` 0.42) are the painted shade this guide replaces. New models leave those multipliers off the albedo.

Terrain shaders stay `unshaded`, with the sun term inside `shaders/terrain_shade.gdshaderinc`. Character cubes follow that same sun. They do not grow a shadow-map pipeline. Contact on the ground stays the one quad from `helpers/contact_shadow.gd`. LOW and SAFE already hide those blobs and zero terrain AO. Character work does not turn shadow casting on to compensate.

Crystal cubes are the exception that may emit. Cloth, skin, and hide do not emit.

## Silhouette at ortho size 16

The model has to name itself from the gameplay camera: player, militia, deer, boar, bird, mite, warden. Q and E yaw the camera, so the read cannot depend on one front angle.

Rules:

- Big masses first: head, shoulders or chest, hips, tail, wings, weapon. A part thinner than one cube is deleted.
- The head is a separate mass from the chest. Legs are a gap, not a single pillar, or the walk pose cannot read.
- Feet meet the ground. The player boot sole stays on the capsule bottom. Do not float the model inside the collider, and do not let cubes stick outside the collider width.
- Clean and corrupted versions of the same creature share one silhouette. Color carries the corruption. A new outline for the corrupted form makes the species unreadable.
- Held tools stay outside the body and at least about one body tall, which is the existing held-item read. Hammer timing stays 0.62 of the 1.1 second swing. This guide does not move that hit.

Ortho size 16, the sun vector, `voxel_scale`, and those hammer times are locked. Art that only reads at a closer zoom is the wrong art.

## Crystal corruption tint

Corruption is a tint on the existing cubes, taken from `ui/crystal_palette.gd`. Do not invent a nearby purple.

Default palette:

| Use | Color | Source |
| --- | --- | --- |
| Crystal body | `(0.72, 0.28, 1.00)` | `CrystalPalette.mass_albedo` |
| Crystal glow | `(0.55, 0.18, 0.95)` | `CrystalPalette.mass_emission` |

The default enemy tint on `EnemySpawnDef` is `(0.72, 0.20, 0.95)`. New crystal creatures use `CrystalPalette`, not that one-off.

Colour-blind palette, same cubes, swapped samples:

| Use | Color |
| --- | --- |
| Crystal body | `(0.96, 0.78, 0.12)` gold |
| Crystal glow | `(0.85, 0.62, 0.08)` |

Markers in that palette stay blue (`marker_albedo` `(0.12, 0.38, 0.92)`). A creature is the mass colors, not the marker colors. Boss markers can stay the brighter boss samples already in `CrystalPalette`. Do not paint the boss as a new hue.

How much of the body changes:

- A crystal-born creature (mite, wisp, warden) is mostly crystal cubes, with one dark non-emitting cube group for eyes or a mouth so the face still has a direction.
- Wildlife that the crystal takes (deer to crystal stag, boar to corrupted beast, rabbit to crystal mite, bird to crystal wisp) keeps its species masses. Crystal cubes replace the accent first (eyes, horns, wingtips, spine), then more of the hide as the corruption is meant to read further along. The last cubes to flip are the feet and the belly, so the body does not become one purple blob.
- Those crystal cubes use the mass albedo and may use the mass emission. The other cubes keep the species albedo.
- The colour-blind switch recolors the crystal cubes only. It does not recolor tunic, hide, or terrain.

Scarred ground and crystal tiles stay on the terrain atlas (`CRYSTAL`, `CRYSTAL_VEIN`, `CRYSTAL_SHARD_GROUND`, `CRYSTAL_SCAR`). Do not stamp that atlas onto a creature.

## How a model is stored

**Working store: a code-defined occupancy grid.** One cell is one cube. A cell holds an integer position in cube steps and a material id from the palette above. Empty cells are absent, not transparent cubes.

Parts are named groups of cells (head, torso, arm, leg, tail, wing, weapon). A pose rotates a whole part. It does not move individual cubes inside a part, and it does not swap to another sprite frame.

The grid is the source the game builds a mesh from. The mesh is derived. Do not hand-edit the mesh and leave the grid behind.

`.vox` files are not the store. This project has no `.vox` importer, and a binary next to the script cannot be reviewed or locked by the headless checks. Whether MagicaVoxel `.vox` should become an authoring input later is an open question in `studio/QUESTIONS.md`. Until that is answered, do not add `.vox` assets.

Do not store the model as a PNG, a `Sprite3D`, or a region on a shared canvas.

## Out of scope for this note

No mesh, shader, palette, or import change ships with this file. The next implementation pass picks up the grid only after the 8-versus-16 question is settled, or explicitly ships the proposal as a trial behind the existing part-rig flag without changing `voxel_scale`, the sun, ortho size 16, or the hammer times.
