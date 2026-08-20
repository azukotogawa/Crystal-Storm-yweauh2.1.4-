# Terrain

## Current loop

Terrain gameplay is column-based. The player digs, builds walls, plants, and creates water channels through `TerrainEditor`.

The current terrain loop is:

1. Player targets a terrain column.
2. Dig/build/channel/plant action is selected from tool state and input.
3. `TerrainEditor` validates the cell.
4. `TerrainEdits`, `FeatureRegistry`, or `ChannelRegistry` is updated.
5. World column caches are invalidated.
6. Affected chunks rebuild.
7. Player movement, crystal flow, visuals, and map state observe the changed terrain.

## Connected systems

- `TerrainEditor` is the gameplay façade.
- `TerrainEdits` records height deltas and built walls.
- `FeatureRegistry` records plants, towns, ruins, and build metadata.
- `ChannelRegistry` records water/channel state.
- `ChunkManager` rebuilds affected terrain chunks.
- `VoxelFloorProbe` makes player/entity movement terrain-aware.
- `CrystalTerrainQuery` lets crystal flow respond to terrain.
- `SaveGameService` persists terrain edits and feature/channel state.

## Gameplay role

Terrain is the main strategic lever. Digging and building are intended to shape enemy/crystal routing and buy time before crystal pressure overwhelms the map.

## Incomplete loops

- Terrain editing has costs, but not yet a rich construction economy.
- No upgrade/repair loop beyond basic wall placement.
- No explicit maze-quality scoring or feedback.
- Digging yields material, but terrain depth does not yet expose a mining progression ladder.

## Isolated mechanics

- Channel water is mechanically connected to growth/crystal flow, but its strategic impact is not strongly surfaced to the player.
- Planting affects growth and future crystal absorption, but does not yet provide a direct harvest/reward loop.

