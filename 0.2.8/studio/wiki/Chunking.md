# Chunking

## Current chunking model

The world streams chunks around the player. Each chunk is 16x16 columns, with height/tile/ramp/geometry data stored in `ChunkData`.

The active terrain renderer is a chunked heightfield renderer, not a fully editable 3D block volume.

## Runtime loop

1. Player moves to a new chunk coordinate.
2. `ChunkManager` computes required nearby chunks.
3. Missing chunks are queued as worker tasks.
4. `ChunkData` captures worker-safe terrain/overlay snapshots.
5. Worker builds terrain data and mesh payload.
6. Main thread accepts non-stale results.
7. `ChunkView` uploads visual data.
8. Old chunks unload.

## Connected systems

- `InfiniteNoiseWorld` supplies terrain queries.
- `ChunkData` holds chunk snapshot data.
- `ChunkManager` owns streaming, worker tasks, rebuilds, and chunk views.
- `ChunkMeshBufferBuilder` builds render payloads.
- `ChunkView` owns rendered instances.
- `TerrainEditor` requests rebuilds after terrain edits.
- `EntityManager`, `WorldVisuals`, `CrystalManager`, and feature visuals bind to chunk load/unload signals.

## Gameplay role

Chunking determines which terrain exists visually and which world cells are active for some systems. Crystal simulation can be configured to loaded chunks only. Entities spawn/despawn around chunk lifecycle.

## Known gaps

- Chunking is deeply coupled to meshing, streaming, rebuild policy, and rendering upload.
- Terrain edit rebuilds are coarse compared with individual cell edits.
- Some gameplay systems depend on loaded-chunk checks, which can affect simulation behavior at the edge of the streamed world.

