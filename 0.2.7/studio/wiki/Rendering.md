# Rendering

## Current rendering model

The game renders a streamed 3D voxel-heightfield world. Terrain chunks are built from 16x16 column data and uploaded as grouped `MultiMeshInstance3D` layers through `ChunkView`.

The renderer is not a fully stored 3D block grid. It is primarily a heightfield with greedy top/side faces, terrain edit strata, ramps, optional cave faces, and shader atlas texturing.

## Connected systems

- `ChunkManager` builds terrain mesh payloads.
- `ChunkMeshBufferBuilder` prepares render buffers.
- `ChunkView` owns terrain visual instances.
- `shaders/ChunkView.gdshader` handles atlas and face shading.
- `WorldVisuals` owns runtime visual layers: entities, vegetation, buildings, spawn markers, combat VFX, and feature visuals.
- `GameVisualRegistry` generates/caches visual assets.
- `CrystalChunkLayer` renders crystal coverage by chunk.
- `FeatureVisualLayer` populates visible vegetation/features.

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
- Terrain occlusion/readability is still a likely playability issue with vertical structures.
- Visual refresh ownership is split across several systems.

## Isolated mechanics

The procedural texture generator and editor dock are useful tooling, but they are not themselves gameplay progression. They support presentation and iteration.

