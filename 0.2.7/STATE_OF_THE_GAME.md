# State of the game

Main `12582d0` (PRs #6 and #7 merged). This is an evidence audit, then the first cleanup that audit justifies. It is not a claim that the game is content-complete.

## Verdict

Cole’s diagnosis is **partly right, and it needs a sharper target.**

Iterative debugging **did** bury the simplest shape of several systems under extra representations, flags, and docs that disagree with the code. The clearest evidence:

- Terrain height is not one number. A column’s height is recomputed from noise, a surface cache, `WorldState.height_delta`, a baked base, per-chunk `surface_map`, an optional macro grid, an optional micro grid, a one-cell halo, a worker snapshot, and `ramp_map`. `chunks/chunk_manager.gd` is 3,565 lines. `chunks/chunk_data.gd` is 1,216. Comments in those files still argue with each other: the chunk path says the mesh is a one-voxel-thick heightfield, while `InfiniteNoiseWorld.get_voxel` is described as the volumetric source of truth.
- `ChunkData.set_voxel` is an empty `pass`. There is no hidden Minecraft voxel editor that debugging turned off. Free 3D placement was never the runtime model (`studio/design/GAMEPLAY.md` says the same thing).
- Ramps grew a second vocabulary on top of “one-layer step.” Cardinal wedges, approach cells, corner prisms, concave side prisms, a 28% placement roll, border-forced ramps, and a height cap at Y=88. The unused `ChunkData.set_ramp_side` helper is removed in the height cut. About 197 `verify_*.gd` files exist; the suite is the debugging scar, not a second game.
- Crystal flow and water flow are two engines (`CrystalFluidSim` and `VoxelFluidEngine`) that share terrain-query math and do not share state. The wiki used to say crystal runs on `VoxelFluidEngine`. It does not. The uncalled `CrystalManager` absorption ticks are removed; live absorption is `CrystalSimulation._tick_absorption_progress`.
- `shaders/crystal_procedural.gdshader` was not bound. It is deleted. Live crystals use `StandardMaterial3D` in `CrystalManager._setup_materials`.
- Character sizes ignored the voxel knob. With `voxel_scale` 2, a column is 2 world units tall and a crystal cell is 1.76, but the player body was `0.4` layers (0.8 units) and wildlife fallback capsules were a hardcoded 0.55. The floor probe used a separate radius of 0.22.

What the diagnosis gets wrong: the **core loop is still simple**, and the performance work is not the obfuscation.

- Dig and build are integer layer edits on a column (`TerrainEdits.dig` / `build_wall`).
- Crystal is a sparse 2D pressure pool (`CrystalFluidSim.depth`) drawn as one mesh instance per cell.
- Combat is a radius query (`CombatHitResolver`), not physics bodies.
- Streaming budgets, surface meshes, crystal flow caps, and loaded-chunk simulation are real limits (`config/performance_quality_config.gd`). They should stay.

So: clean the extra maps, flags, and dead paths. Do not throw away the heightfield and rebuild a voxel engine in the same breath, and do not strip LOD or frame budgets.

## What a capture can show, and what only Cole’s machine can show

Headless probes and editor captures **can** show:

- Contracts: dig lowers a column, a wall raises it, a corner prism walks up, crystal depth swells a cell, a hit marker is spawned in world space, save round-trips overlays.
- Mesh facts: triangle counts, AABB, whether a shader file is referenced, relative scale of a player box against a 1-voxel cube.
- A studio frame of the meshes and materials (this PR’s scale shot).

They **cannot** show:

- Whether a ramp reads as a slope at a glancing camera angle, or whether z-fighting hides it. `GAMEPLAY_CORRECTION_REMAINING.md` already says resident mesh probes are not a photo of the wedge.
- Whether digging feels snappy, whether the iso camera (`distance` 100, ortho `size` 24) makes a 1.6-voxel person readable, or whether crystal growth feels like a living front during a real minute of play.
- Audio. There is none in the tree (no `.ogg` / `.wav` / `.mp3`, no `AudioStreamPlayer`).
- Multiplayer. The only hook is a save stub: `authority.mode = local_singleplayer` in `systems/save_schema.gd`.
- Whether 28% ramp placement, assault damage, and town pressure are fun. Probes force `placement_chance = 100`.

A live session on Cole’s machine is still the check for feel, framing, and “does the crystal look like one mass while I play.”

## Scale contract

**1 voxel = 1 column = 1 height layer = `WorldSettings.voxel_scale` world units (default 2.0).**

| Thing | Before this change | After |
| --- | --- | --- |
| Player height | 0.4 voxels (0.8 units) | 1.6 voxels |
| Player radius / floor probe | radius 0.2 voxels, probe 0.22 units | both `player_radius()` (0.28 voxels) |
| Wildlife fallback capsule | 0.22 × 0.55 units, fixed | 0.18 × 0.55 voxels |
| Crystal mite body | 0.28 × 0.7 units, fixed | 0.22 × 0.70 voxels |
| Crystal cell mesh | 0.88 voxels | unchanged |
| Structures | scaled by `voxel_scale` in `GameVisualRegistry.configure_building_mesh` | unchanged |
| Camera | ortho size 24, looks at the feet | still size 24; look target lifted by half the player height |

Water `water_level` is a 0–1 fill inside a channel cell, not a height in voxels. That is a different quantity on purpose.

## Systems

Status words: **present** (works as a closed loop), **partial** (a real slice, not the vision), **missing**.

### Player dig / build — partial

Does: pick digs one layer (`TerrainEdits.dig`, floor −6 layers stored, gameplay floor about −4 layers). Walls add one layer and a build tile, cap +8. Gates set a tile without raising. Bridges raise like a wall. Shift/Ctrl/Alt on the pick edits water channels. Planting sets a feature, not a height.

Meant to do, and does not: place or remove an arbitrary voxel, carve a tunnel through a solid, or shape a freeform shell. `ChunkData.set_voxel` is a no-op. The mesh emits strata for dug or built columns (`chunk_manager.gd` `_emit_build_strata` / `_emit_dug_strata`), which is a heightfield showing its side, not a volume.

Pointers: `weapons/weapon_controller.gd`, `world/terrain_editor.gd`, `world/terrain_edits.gd`, `player/action_targeting.gd`.

### Voxel / terrain — partial, and this is where the obfuscation lives

Does: infinite noise heightfield, caves via `InfiniteNoiseWorld.get_voxel` for solidity queries, column mesh as one surface (surface ArrayMesh when `terrain_surface_mesh` is on, else box MultiMeshes). Edits invalidate chunks and rebuild.

The parallel heights listed in the verdict are all live. Walk height can follow `ramp_map` while the visible quad stays a flat top (`helpers/live_world_query.gd` calls that out as `RAMP_VISUAL`). Halo samples can disagree with `surface_map` at chunk borders. Macro (`CRYSTALSTORM_MACRO_TERRAIN`) and micro (`CRYSTALSTORM_MICRO_TERRAIN`) grids are optional second copies. Micro bricks are not saved (`systems/save_schema.gd`).

Perf that should stay: chunk streaming budgets, surface mesh, upload budget, worker snapshots. The yard “preserve maps” path is a debug/validation tool; gameplay edits clear it.

### Ramps / steps — present as a heightfield trick, partial as terrain shaping

A one-layer neighbor step can become a wedge on the high cell (`FACE_RAMP` = 7), an L prism on the low cell (`FACE_RAMP_CORNER` = 8), or a concave side (`FACE_RAMP_SIDE` = 9). Default placement chance is 28 (`TerrainRamps.PLACEMENT_CHANCE`). Player-built cells skip ramps. Walk height uses the ramp entry when the chunk is loaded.

PR #6 is the corner-walk fix: the step up an L is the prism, and the floor probe must be given a feet hint on the surface or it reads the cave floor.

Not a general “shape this into a ramp” tool. The player does not author the wedge; the mesher rolls for one.

### Water — partial

`VoxelFluidService` runs `VoxelFluidEngine` as a gravity channel on `ChannelRegistry` / `WorldState.channels`. The player can dig, raise, lower, and redirect channels. The sim sleeps when the dirty set is empty.

Passive level changes do not redraw the world: `channel_fluid_changed` has no gameplay listeners (`WATER_LIVE_PROFILE.md`). Visual water is mostly a river/water tile on the chunk mesh.

Crystal does not share this depth map. Wet tiles only reduce crystal conductivity (`CrystalTerrainQuery`).

### Crystal — partial, and this is the second obfuscated system

Does: spread on loaded chunks as a pressure pool (`CrystalFluidSim.tick_flow`), absorb plants, farmland, animal spawns, and ruin features, raise walkable height by depth, resist flow through build tiles (`BuildingRegistry.flow_resistance`), emit from spawn points, spawn enemies, pressure towns (`TownDefenseManager`), and damage the player in the assault phase (`GameManager`).

Does not: edit the heightmap itself, fill 3D cavities, push water, or consume a town as terrain (towns lose health; they are not an absorbable tile). Sim surface and drawn floor can disagree: flow uses raw column height, the mesh uses ramp-aware `_crystal_floor_at`.

Visual after PR #7: one centered facet cluster per cell, small when shallow, overlapping when deep. Still one MultiMesh instance per cell, not one merged volume. Legacy cubes remain behind `CRYSTALSTORM_CRYSTAL_RENDERER=legacy`. The procedural crystal shader is unused.

Caps worth keeping: `max_new_cells_per_tick`, flow budget, loaded-chunk-only sim, spread damping. Those are the perf wins.

### Combat — present as queries, partial as “hitboxes”

Sword, pick, bow, herb (`helpers/item_types.gd`). Melee is an arc (70°, then 180° if empty) plus a camera-forward fallback (PR #4). Crystal spawn damage aims at the column in front of the feet (PR #5). Entity damage numbers and hit rings are world-space (PR #7). Dig throws three break shards.

There are no combat physics bodies. `get_combat_radius` is the hitbox. Chunks do not create per-cell bodies.

### Rendering / LOD — present, with one unwired LOD flag

Terrain surface mesh + atlas (`shaders/ChunkSurfaceMesh.gdshader`, `assets/tiles/Cube.png` bound in `chunks/chunk_view.gd`). Crystal LOD drops pyramids by chunk distance (`CrystalClusterMesh.lod_tier_for_chunk_distance`). `LOD_FULL` is what the legacy box path asks for; the procedural path uses far/mid/near.

`vegetation_billboard_distance_columns` is on the quality config. `FeatureVisualLayer._player_column_distance` is never called, and `_use_voxel_vegetation` only checks the global voxel-model flag. Distance billboards are configured and not applied. Entity voxel models, when enabled, ignore distance too.

### UI — present, plain

`scenes/frontend.tscn` menu, `ui/game_overlay.tscn` HUD, hotbar, inventory, map, pause, loading. Built from Controls, not an art pack. Dev-only: F-key inspector, debug panel, dev chat.

### Audio — missing

No audio assets and no player nodes in game scripts.

### Networking — missing

Local single-player. Save schema reserves an authority field and does not sync anyone.

### Save / load — present for the overlay game

`SaveGameService` writes world overlays (height, build tiles, features, channels, towns), seed, player (inventory, stats, relics), crystal depth and spawns, phase, town defense, and live entities. It does not write GPU meshes, micro bricks, or the spatial index (those rebuild).

## Assets

62 PNGs under `0.2.7/assets`. No audio files.

| Path | What it is | Placeholder or real |
| --- | --- | --- |
| `assets/tiles/Cube.png`, `voxelsnew.png`, `Cube_prebatch.png` | Terrain atlases. `Cube.png` is what `chunk_view.gd` binds. `TERRAIN_ASSET_INVENTORY.md` still calls `Cube.png` a placeholder atlas. | Mixed. Batch folders are generated art, not empty files. |
| `assets/tiles/batch01`–`batch05/*.png` | Per-biome albedo pairs from `author_batch*.gd` | Real procedural textures, consistent with each other, not hand-painted |
| `assets/structures/{wood_wall,stone_wall,gate,bridge,ruin_pillar,town_hall}/` | OBJ + albedo PNG + `author_*.gd` (wood wall is a Python author) | Real authored meshes. Runtime scale is `voxel_scale` on XZ with per-building Y factors (wood cap 0.55, stone 0.68, gate/pillar/hall 1.0, bridge 1.15) in `game_visual_registry.gd` |
| `assets/structures/*/src/*.jpg` | Photo inputs to those authors | Source plates, not runtime textures |
| `assets/player/player.png` | Player box albedo. Was a tiny figure in a white field. | Re-authored this change as a 32×48 voxel scout (`author_player.gd`), nearest-filtered |
| `assets/tiles/new_tile_set.tres` | TileSet resource | Not the 3D terrain path |
| `shaders/ChunkView.gdshader`, `ChunkSurfaceMesh.gdshader` | Bound terrain materials | Live |
| `shaders/crystal_procedural.gdshader` | Was an unused fresnel shader | Deleted |
| `scenes/main.tscn`, `frontend.tscn`, `ChunkView.tscn`, `world_object.tscn` | Play, menu, chunk, structure | Live |
| `scenes/world_viewer.tscn` | 2D map tool | Tool, not the game |
| `systems/crystal_texture_generator.gd` | Runtime PNGs for entities, plants, items, combat bursts | The only art those systems have. Not on disk. |
| `helpers/voxel_prop_builder.gd` | Box-stack creatures and plants. `unit()` is `voxel_scale * 0.62` | Procedural, already on the voxel knob |
| `helpers/crystal_cluster_mesh.gd` | Crystal facet mesh | Procedural, no albedo texture |

Scale outliers that were **not** the character body, and are still true:

- Orthographic camera size 24 against a 2-unit voxel. A person at 3.2 units is about 13% of the frame height. Readable relative to a block, still small in the wide iso view. Changing `size` would reshoot every camera probe; left alone on purpose.
- Structure Y factors differ (a wood wall cap is 0.55× voxel height, a town hall is 1.0×). They share the column footprint. The height differences are the building designs, not a second unit.
- `legacy_height_reference` 158 maps noise into the 40-unit cap. That is a generation scalar, not a rendered size.

## Vision gaps

Target: 3D Minecraft-like shaping, plus a crystal that consumes and remakes the place you can stand.

| Capability | Status | Where |
| --- | --- | --- |
| Dig / remove voxels freely | **Partial** — one layer per dig, column only | `terrain_edits.gd` `dig` |
| Place voxels freely | **Partial** — walls +1 layer; gate is a tile | `build_wall`, `set_build_tile_only` |
| Ramps, walls, tunnels, channels, bridges, defenses | **Partial** — walls, gates, bridges, channels, auto ramps on natural steps. No authored tunnel, no player-drawn ramp | `terrain_editor.gd`, `chunk_manager.gd` `_emit_ramps` |
| Use terrain strategically | **Partial** — height and build tiles change crystal conductivity and walk height | `crystal_terrain_query.gd` |
| Crystal spreads | **Present** | `crystal_fluid_sim.gd` |
| Grows across / exposes terrain | **Partial** — depth overlay, not a terrain rewrite | `crystal_manager.gd` `get_walkable_height` |
| Enters cavities | **Partial** — 2D hole bonus and cliff checks, no 3D pocket | `_new_cell_priority`, `_cliff_blocked` |
| Interacts with water | **Partial** — wet cells slow crystal; water is not pushed | `get_standing_water_level` |
| Transforms terrain | **Partial** — clears plants, farmland, animals, ruin features. Does not edit height | `_complete_absorption` |
| Grows around obstacles | **Present** as flow resistance | `BuildingRegistry.flow_resistance` |
| Interacts with player structures | **Present** as resistance and walk blocking | same, plus floor probe |
| Hazards / pressure | **Present** — power, assault DPS, contact defeat flag, spawns, town states, coverage loss | `game_manager.gd`, `town_defense_manager.gd` |
| Keeps changing the play space | **Partial** — only inside loaded chunks, paused while streaming | `_is_cell_sim_active` |
| One living crystal mass | **Partial** — overlapping cell meshes (PR #7), not a single volume | `crystal_chunk_layer.gd` `visual_growth` |

## What this change does, and what it leaves

This pass does not merge the two fluid engines, delete macro/micro terrain, or turn dig into a 3D voxel brush. Those are the next cuts, and each one is a behavior change with its own probes.

This pass:

- Records the audit above.
- Puts the player, the floor probe, wildlife fallback bodies, and crystal-mite bodies on the voxel unit. Streaming, surface meshes, and crystal flow caps are untouched.
- Replaces the player albedo with a small voxel scout and filters it nearest, matching the block art.

## Height, water, and atlas cut

Interior mesh height is the resident `surface_map`. The halo stays, and it is only the neighbor ring the worker snapshots. `ramp_map` is rebuilt from the quads the chunk actually draws, so a cached or clipped mesh cannot leave a slope the player walks with no wedge. Streaming budgets, the surface mesh, worker snapshots, and crystal flow caps are unchanged.

Deleted: `ChunkData.set_ramp_side`, the uncalled `CrystalManager` absorption ticks (live absorption stays on `CrystalSimulation`), and `shaders/crystal_procedural.gdshader`. The wiki no longer says crystal runs on `VoxelFluidEngine`.

`channel_fluid_changed` draws a nearest-filtered fill. Its thickness is the 0–1 water level times one voxel layer. `Cube.png` is authored 4×4 voxel bricks on the same 7×10 grid. Hit rings, the boss ring, and spawn-marker fallbacks are expressed in `voxel_scale`.

Freeform 3D tunnels are still a follow-up. Dig and build remain one layer on a column. A dig brush that carves a volume would be a new editor, not this cleanup.
