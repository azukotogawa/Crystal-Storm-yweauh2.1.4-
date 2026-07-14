# Crystal Storm identity

Crystalstorm is a voxel-based maze-building strategy and action game. The player reshapes terrain to delay an expanding crystal corruption, using the time created by route design to explore, prepare, and fight back.

The central fantasy is not defending a fixed base. It is turning a living landscape into a temporary advantage against a spreading natural disaster.

## Player promise

- Terrain is a meaningful strategic tool: dig, raise walls, route, and exploit elevation.
- The crystal changes the world and creates time pressure rather than acting as a static enemy camp.
- Exploration, world features, and direct combat support the same objective: reach and destroy crystal spawn points.
- The readable orthographic/isometric voxel presentation makes terrain shape and routes legible at a glance.

## Tone and visual direction

The world is a readable, pixel-art voxel landscape with grounded biome references: plains, steppe, forest, marsh, and highland/mountain terrain. Crystal is the disruptive visual counterpoint. The implementation currently mixes textured terrain, procedural sprite/billboard assets, and simple voxel props; visual polish remains an active human-review area.

## Non-negotiable distinctions

- **Crystalstorm** is the project name; “crystal” is the spreading corruption/fluid simulation.
- **Maze phase** and **combat phase** are gameplay states in `GameManager`, with maze play intended to dominate the run.
- The world is rendered as a 3D voxel-like heightfield, not a general editable volumetric voxel volume.
