# World

## Current world loop

The world is deterministic by seed and combines procedural terrain with static runtime overlays.

The current world loop is:

1. `InfiniteNoiseWorld` provides terrain, biome, river, cave, and tile queries.
2. `WorldFeatures` seeds towns, vegetation, ruins, channels, and entity spawn data.
3. `ChunkManager` streams visible chunks around the player.
4. Gameplay edits update overlays.
5. Chunks, player movement, crystal, entities, map, and save/load consume those overlays.

## Connected systems

- `InfiniteNoiseWorld`: deterministic world queries.
- `BiomeLayout`: large biome regions.
- `TownManager`: settlements/ports.
- `VegetationManager`: scattered vegetation.
- `RuinManager`: ruin features and crystal spawn candidates.
- `EntityManager`: animal and defender spawning.
- `FeatureRegistry`: feature overlay.
- `TerrainEdits`: terrain edit overlay.
- `ChannelRegistry`: channel/fluid overlay.
- `TopographicalMapBuilder`: map rendering data.

## Gameplay role

World features feed both player strategy and crystal progression:

- vegetation/farmland/ruins become crystal absorption targets,
- towns create protection/loss pressure,
- terrain shape defines maze-building strategy,
- rivers/water/channels affect growth and flow,
- animal spawns create ecology and crystal unlock inputs.

## Incomplete loops

- Towns are mostly risk/loss systems, not reward or trade hubs.
- Ruins are more crystal fuel than player-facing exploration rewards.
- Vegetation has simulation value, but limited player economic value.
- Biomes affect placement and visuals, but do not yet provide strong biome-specific progression.

