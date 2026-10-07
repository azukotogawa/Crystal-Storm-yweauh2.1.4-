# Crystal

## Current loop

The crystal is the main antagonist and run clock.

The current crystal loop is:

1. Crystal spawn points seed pressure fluid.
2. `CrystalFluidSim` spreads crystal across terrain.
3. Crystal absorbs vegetation, farmland, and animals. The ground becomes a crystal tile and plants become crystal grass, crystal bushes, or shard trees. Ruins, towns, and player buildings stay so they can still be used.
4. Absorption grants power and can unlock enemy types. It does not hand the player a relic.
5. Unlocked enemies spawn near the player/crystal.
6. Player attacks the crystal mass and spawn points. The pick removes depth quickly; the sword chips it. Broken cells drop crystal shards and leave scarred ground that grows back into the biome tile.
7. Destroyed non-boss spawns weaken emission.
8. Origin/boss spawn is sealed until non-boss spawns are destroyed.
9. Destroying all active spawns wins.

## Connected systems

- `CrystalManager` owns simulation, absorption, spawn setup, crystal visuals, and player-contact checks.
- `CrystalFluidSim` is its own pressure-pool sim. Water uses `VoxelFluidEngine`; crystal does not.
- `CrystalTerrainQuery` reads terrain, features, channels, and world state.
- `CrystalEvolution` records absorption and unlocks enemies.
- `CrystalCorruption` swaps absorbed cells to crystal ground and plants, tracks scars, and heals them.
- Passive deer, boar, rabbits, and birds standing in crystal become crystal stags, corrupted beasts, crystal mites, and crystal wisps.
- Relics come from destroying a spawn point or exploring a ruin.
- `CrystalEnemySpawner` reacts to unlocked enemies.
- `SpawnPointController` owns spawn damage, boss gate, weaken multiplier, and victory signal.
- `GameManager` observes crystal victory/loss conditions.
- `TownDefenseManager` reacts to nearby crystal depth.

## Progression

Progression currently ends at the finite absorption unlock table and spawn-point destruction chain. Once all enemy unlocks are active, crystal progression is mostly pressure, coverage, tier, and spawn activity.

## Loss conditions

- Crystal coverage exceeds configured overrun ratio.
- Crystal touches/damages player depending on run state/config.
- Player dies.

A fallen town is not a loss. It applies a crystal power surge and removes that town's defenders. The crystal heart starts in a map corner chosen from the world seed, then snaps to the nearest dry land in that corner.

Spread pace, crystal reserve depth, and enemy spawn rate differ by biome (`CrystalSimConfig` `biome_spread`, `biome_reserve`, `biome_mob`). Highlands and mountains spread slower and hold a deeper reserve. Plains and steppe spread faster and field more mobs.

## Incomplete loops

- No player reward for partial crystal containment.
- No boss phases beyond the sealed-origin gate.
- The objective HUD always shows phase, spawns remaining, coverage percent, and an arrow toward the nearest spawn.
- No long-term mutation tree after enemy unlocks.

