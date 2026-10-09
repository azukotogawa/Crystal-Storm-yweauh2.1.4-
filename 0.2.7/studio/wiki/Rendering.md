# Rendering

## Current rendering model

The game renders a streamed 3D voxel-heightfield world. Terrain chunks are built from 16x16 column data and uploaded as grouped `MultiMeshInstance3D` layers through `ChunkView`.

The renderer is not a fully stored 3D block grid. It is primarily a heightfield with greedy top/side faces, terrain edit strata, ramps, optional cave faces, and shader atlas texturing.

## Connected systems

- `ChunkManager` builds terrain mesh payloads.
- `ChunkMeshBufferBuilder` prepares render buffers.
- `ChunkView` owns terrain visual instances.
- `shaders/ChunkView.gdshader`, `ChunkSurfaceMesh.gdshader`, and `ChunkRamp.gdshader` handle atlas and face shading. They stay unshaded. A cave cutaway discards fragments in a cone between the camera and the player (screen-door at the rim). `player/camera.gd` writes the shader globals once per frame. Feet, one-layer steps, ramps underfoot, and foot-level water lids stay (`cutaway_feet_clear`). Authored structure materials (`StandardMaterial3D` on world objects) are not cut away.
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
- Cave ceilings and tall terrain between the camera and the player are cut away when Camera cutaway is on (Graphics settings, default on). Authored walls and bridges that use their own `StandardMaterial3D` are not part of that cone.
- Visual refresh ownership is split across several systems.

## Isolated mechanics

The procedural texture generator and editor dock are useful tooling, but they are not themselves gameplay progression. They support presentation and iteration.

