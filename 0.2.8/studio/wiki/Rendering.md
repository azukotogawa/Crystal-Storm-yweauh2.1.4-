# Rendering

## Current rendering model

The game renders a streamed 3D voxel-heightfield world. Terrain chunks are built from 16x16 column data and uploaded as grouped `MultiMeshInstance3D` layers through `ChunkView`.

The renderer is not a fully stored 3D block grid. It is primarily a heightfield with greedy top/side faces, terrain edit strata, ramps, optional cave faces, and shader atlas texturing.

## Connected systems

- `ChunkManager` builds terrain mesh payloads.
- `ChunkMeshBufferBuilder` prepares render buffers.
- `ChunkView` owns terrain visual instances.
- `shaders/ChunkView.gdshader`, `ChunkSurfaceMesh.gdshader`, and `ChunkRamp.gdshader` handle atlas and face shading. They do not cast. `shaders/terrain_shade.gdshaderinc` adds a sun/hemisphere term, per-cell corner darkening, per-voxel noise, crystal-cell glow (atlas column 6, rows 1/2/3/5), and a cave tint. `cs_depth` applies vertex-color corner AO and that corner darken. `light()` multiplies directional shadow attenuation only, so side faces stay readable at the iso camera. Top and side corner AO is baked into vertex color alpha (`helpers/terrain_vertex_ao.gd`, off on LOW and SAFE). The directional light rays follow the terrain sun `(0.55, 0.82, 0.38)`. The ortho camera far is 520 so that shadow map stays fine enough to read. Voxel characters, creatures, vegetation props, and structures cast and receive the sun shadow. Terrain receives that shadow and does not cast. Contact blobs are one unshaded quad per player, mob, or `world_item` (`helpers/contact_shadow.gd`), with `cast_shadow` off. LOW and SAFE set `terrain_ao_strength` to 0 and hide the blobs. A cave cutaway discards fragments in a cone between the camera and the player (screen-door at the rim). `player/camera.gd` writes the cutaway shader globals once per frame and does not overwrite AO strength. Feet, one-layer steps, ramps underfoot, and foot-level water lids stay (`cutaway_feet_clear`). Authored structure materials (`StandardMaterial3D` on world objects) are not cut away. F6 (texture blueprint) swaps textures for same-size placeholders; it is off by default. Settings > Graphics texture set chooses Original or Batch 1 (`helpers/texture_set.gd`); blueprint mode still replaces the active set.
- `WorldVisuals` owns runtime visual layers: entities, vegetation, buildings, spawn markers, combat VFX, and feature visuals.
- `GameVisualRegistry` generates/caches visual assets.
- `CrystalChunkLayer` renders crystal coverage by chunk.
- `FeatureVisualLayer` populates visible vegetation/features.
- Combat particles, swing arcs, hit flash, and death fade live in `VfxPool` / `Juice`. Caps and buses are in `studio/wiki/Effects.md`. Terrain shaders stay unshaded, and these extras do not cast shadows.

## Gameplay-facing rendering

Rendering communicates:

- terrain shape and ramps,
- dig/build changes,
- target highlights,
- crystal spread,
- spawn markers,
- entity/enemy presence,
- combat feedback,
- vegetation/town/ruin features.

## Incomplete loops

- Visual feedback for strategic channel/crystal-flow effectiveness is limited.
- Spawn-point health/status presentation is minimal.
- Cave ceilings, tall terrain, and authored structures between the camera and the player are cut away when Camera cutaway is on (Graphics settings, default on). The floor under the feet, including foot-level water lids, stays.
- Visual refresh ownership is split across several systems.

## Isolated mechanics

The procedural texture generator and editor dock are useful tooling, but they are not themselves gameplay progression. They support presentation and iteration.

