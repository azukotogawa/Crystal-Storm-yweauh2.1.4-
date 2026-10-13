# Crystal Storm — Week Plan

## Goal
Move from many prototypes working independently to a coherent, visually understandable alpha slice that can be extended without recurring integration bugs.

## Priority

### 1. Stabilize the current cross-slice
Terrain editing, ramps/collision, camera/movement, building/removal, water, crystal simulation/presentation, enemies/combat, streaming/remesh, and save/resume.

### 2. Establish reusable content architecture
Create data-driven contracts for:
- items
- relics
- weapons
- enemies
- vegetation
- structures/buildables
- visual identities
- gameplay stats/behaviors
- spawn/configuration data

New content should not require one-off engine code.

### 3. Make the world feel alive
Use existing systems first:
- vegetation occupancy/scatter
- crystal growth/spread and biome interaction
- water movement/interaction
- understandable enemy presence
- terrain variation
- towns/structures where already supported

### 4. Establish visual scale
The world should not become Minecraft-like uniform cubes.

- Macro voxels provide efficient large-scale terrain.
- Micro voxels are reserved for digging and selected terrain features.
- Features must read at a meaningful fraction of a voxel.
- Terrain materials should eventually resemble pixel-art versions of real materials, not flat colors with noise dots.
- Three-dimensional surface detail is a future visual direction, not today's prerequisite.

### 5. First presentable alpha slice
The player can enter the world, understand the crystal threat, move/fight, dig/build/manipulate terrain, encounter environmental variation and enemies, use a small set of content, and perceive a coherent world.

## Agent division

### Agent 1 — systems/integration
Gameplay architecture, runtime integration, contracts, performance, collision, streaming/remesh, verification, bug fixing.

### Agent 2 — visual/content
Terrain materials, vegetation, structures, enemies, visual variants, and bounded asset integration.

Agent 1 does not invent art direction. Agent 2 does not change gameplay contracts or mappings without documenting the handoff.

## Daily cadence
1. Read /studio.
2. Pick one bounded objective.
3. Implement.
4. Focused verification.
5. Small live camera check when visual.
6. Update status.
7. Stop.

## No-regression rule
When a shared contract changes, add/update one focused regression test and one live check.

## Performance rule
MEDIUM is the current target. Do not tune HIGH until a representative windowed activity profile exists.
