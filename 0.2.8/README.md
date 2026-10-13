# Crystalstorm

A voxel-based maze-building strategy + action game. Build the most devious terrain maze you can to buy time against an ever-expanding crystal threat that consumes the world and spawns enemies.

## Premise

You are the last line of defense. Using tools to raise walls and dig deep, you must route paths that force the crystal to take as long as possible to reach critical points while you grow strong enough to strike back.

The crystal absorbs:
- Plants and animals (granting it new spawn types — e.g. farm animals become suicide-bomber mobs)
- Artifacts in ruins (extra spawn points)
- Certain terrain features

Natural counters exist: water (crystal cannot absorb it), dense forests, NPC towns that fight back (but slowly lose).

**Two-phase loop**:
1. **Maze phase** (primary, longer): Exploration, construction, resource management, path optimization.
2. **Combat phase** (short, high intensity): Direct fights, destroying crystal spawns and a final boss at the origin crystal.

Win condition: Eliminate all crystal spawn points.

## Current Technical State

- **Engine**: Godot 4.6 (Forward+, Jolt Physics)
- **World**: Infinite heightfield voxel terrain (16×16 columns, one-voxel surface slabs at computed height; 160 max)
  - 5 real-life biomes (plains/steppe/forest/marsh/mountain) via height+precip+ruggedness+river bias for realistic topology + tile choice (grassland/hills/mountain/snow families etc.)
  - Realistic rivers: topo-guided (valley concavity + low-freq path noise), carve surface depth (up to ~3 voxels) for incised channels + natural banks via lips; river/water tile variants at lowered y so they traverse any biome following geography. Pure heightfield (no full 3D).
  - Async WorkerThreadPool chunk gen + 2D greedy meshing (Y flat rect merge + side lip runs); BOTTOM faces disabled for FPS
  - Efficient rendering via `MultiMeshInstance3D` (single buffer) + custom spatial shader (atlas 7×10, object-normal face culling, padding UV)
  - Tunables: RENDER_DISTANCE=3 default, drain cap 5/frame, debug rate-limited; focused on max FPS while preserving exact look + fast near-chunk pop-in
- **Player**: 3D orthographic isometric camera + custom voxel collision movement (jump, step, fall squash effects preserved from 2D prototype)
- **Status**: Core world streaming and player locomotion functional in the 3D prototype. Legacy 2D isometric code and scenes remain for reference (being phased out). Crystal, building, digging, enemy, and combat systems not yet implemented.

Key locations in the codebase:
- `chunks/chunk_manager.gd`, `chunks/chunk_data.gd`, `chunks/chunk_view.gd`
- `player/player.gd`, `player/camera.gd`
- `helpers/voxel_types.gd`
- `shaders/ChunkView.gdshader` + `ChunkView.tres`
- `src/world/infinite_noise_world.gd` (authoritative world gen)
- `scenes/main.tscn` (active entry point)

See `AGENTS.md` for coding conventions and detailed architecture notes.

## Running the Game

1. Have Godot 4.6+ installed.
2. From the project root:

```bash
godot .
# or open the project in the Godot editor and press Play (F5)
```

The game should load the procedural voxel terrain around the player and allow WASD movement + jump (Space) + Q/E camera rotation + mouse wheel zoom.

## Project Structure (abbreviated)

```
.
├── AGENTS.md
├── README.md
├── premise                 # Original design notes
├── project.godot
├── assets/
│   ├── player/
│   └── tiles/              # Texture atlas source + older tile data
├── chunks/                 # Voxel chunk engine (core)
├── helpers/
├── player/
├── scenes/                 # Current 3D main scene + ChunkView template
├── shaders/
├── src/world/              # World generation
├── ui/
└── (legacy 2D files at root + world/)
```

## Next Steps / Roadmap (from premise)

- Proper maze building tools (place/remove voxels for walls, variable dig depth)
- Crystal entity simulation + absorption + spawn logic
- NPC towns, animals, plants, ruins as interactable/absorbable elements
- Combat system, weapons, relics, bosses
- Topographical map / minimap
- Win/lose conditions and pacing

Contributions and iteration should focus on making the "Maze phase" deeply satisfying first.

## Notes

- The project name in Godot config was a placeholder and has been updated to Crystalstorm.
- Large session artifacts and virtualenvs are gitignored.
- This is an active prototype — expect rapid iteration on the voxel systems.
