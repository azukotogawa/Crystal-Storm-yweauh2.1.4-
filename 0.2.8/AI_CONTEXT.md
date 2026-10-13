# Crystal Storm AI Context

This is the one-file orientation guide for future AI work on Crystal Storm. It summarizes the live Godot 4 project, its design intent, runtime architecture, workflows, traps, and verification discipline. Prefer this as a starting map, then read the affected files and tests before changing behavior.

## Project Identity

Crystal Storm is a voxel terrain action/strategy game where terrain is the player's primary weapon. The player reshapes the landscape to slow an expanding crystalline corruption long enough to grow strong enough to destroy its source.

The player does not defend a fixed base. They explore, dig, build walls, route crystal flow, gather resources, fight enemies, and eventually push into the corruption. The crystal is intended to feel like a natural disaster: it spreads, pools, climbs, consumes plants/animals/ruins/settlements, evolves, and opens new threats.

Core loop:

1. Maze phase: long strategic terrain editing, exploration, resource gathering, path optimization, planting/building, map reading.
2. Combat phase: short high-intensity direct fighting against enemies, crystal spawn points, and eventually the origin source.

Current production game is the 3D voxel runtime. Legacy 2D prototypes live under `archive/legacy/` and must not be used in production scenes.

## Development Philosophy

Work with the live code, not stale assumptions. This repo has historical docs, active untracked work, and rapid iteration. Before changing behavior, read:

- `AGENTS.md`
- `AI_CONTEXT.md`
- the affected scene/script(s)
- the nearest `scripts/verify_*.gd` probes
- current `git status --short`

Make the smallest coherent change that respects existing ownership boundaries. Do not refactor unrelated systems while fixing a feature. Do not revert user changes. Do not mark manual verification as passed unless a human actually performed it.

For gameplay, prefer systems already present:

- Terrain changes go through `TerrainEditor`, `TerrainEdits`, `ChunkData`, and `ChunkManager`.
- Targeting goes through `ActionTargeting` and `TargetHighlight`.
- Collision/path surface questions go through `VoxelFloorProbe`, `WorldSettings`, and world/chunk query helpers.
- Crystal flow questions go through `CrystalManager`, `CrystalFluidSim`, and `CrystalTerrainQuery`.
- Visual output goes under `WorldVisuals` layers and uses `GameVisualRegistry`/performance flags where appropriate.
- Configuration belongs in `config/` resources and `GameConfig`, not scattered literals.
- Saves persist canonical overlays/runtime state, not mesh/view nodes.

Godot rules:

- Godot 4.6+ project, Forward+ renderer, Jolt Physics.
- Use Godot 4 GDScript syntax: `@export`, `@onready`, and `signal_name.connect(callable)`.
- Use `CharacterBody3D`; the player currently uses custom voxel-aware movement rather than normal `move_and_slide` authority.
- Worker threads must not mutate the scene tree. Use snapshots and deferred/main-thread application.

## Production Entry Points

Primary scene:

- `scenes/main.tscn` is the production main scene.
- `project.godot` has `run/main_scene="res://scenes/main.tscn"`.
- `main.gd` is a short root script documenting the boot chain.

Useful dev scene:

- `scenes/world_viewer.tscn` is a biome/world viewer.

Do not wire production behavior to legacy scenes under `archive/legacy/`.

Main scene runtime nodes include:

- `ConfigService`
- `PerformanceService`
- `GameVisualRegistry`
- `VoxelWorld`
- `WorldVisuals`
- `WorldFeatures`
- `CrystalManager`
- `GameManager`
- `TerrainEditor`
- `SaveGameService`
- UI/player/camera nodes authored in the scene

`WorldVisuals` owns explicit child layers:

- `Entities`
- `Vegetation`
- `Buildings`
- `SpawnMarkers`
- `CombatVFX`
- `FeatureVisualLayer`

Attach dynamic visuals under the appropriate layer and clean them up on unload.

## High-Level Architecture

The world is a streamed 3D heightfield voxel renderer with deterministic generation and mutable overlays. Rendering is derived state. Gameplay authority does not live in `ChunkView` or `MultiMeshInstance3D`.

Canonical sources:

- `InfiniteNoiseWorld`: deterministic base terrain by seed/config.
- `TerrainEdits`: mutable dig/build height and build-tile overlay.
- `FeatureRegistry`: plants, ruins, towns, buildings, feature tile overrides.
- `ChannelRegistry`: water/channel routing overlay.
- Crystal runtime state in `CrystalManager`/`CrystalFluidSim`.
- Player/entity/game state in their managers/components.

Derived streamed state:

- `ChunkData`: 16x16 column snapshot of generated terrain plus overlays, ramps, geometry kinds, halo data.
- `ChunkManager`: worker generation, greedy meshing, streaming, rebuilds, `chunk_ready`/`chunk_unloaded`.
- `ChunkView`: uploaded terrain MultiMesh groups and material binding.
- Crystal chunk layers and feature/entity visual layers.

Important rule: if a new feature needs to persist, save, affect collision, affect crystal, or affect pathing, put it in canonical data/overlays first. Then update mesh/visuals as a derived consequence.

## Boot Chain

Startup correctness depends on deferred initialization, groups, readiness waits, and explicit binding. Do not assume sibling order is enough.

Current intended chain:

1. Autoloads initialize `CrystalTextureGenerator` and `PerfProfiler`.
2. `ConfigService` creates/defaults/validates `GameConfig`, activates `WorldSettings`, and populates registries.
3. `PerformanceService` chooses SAFE/LOW/MEDIUM/HIGH from environment or defaults.
4. `GameVisualRegistry` waits for performance and builds texture bundle readiness.
5. `WorldFeatures` waits for config, applied performance, texture readiness, and world availability; resets/seeds feature/channel overlays.
6. `VoxelWorld` waits for feature seeding, then creates `ChunkManager`.
7. `WorldFeatures.on_chunk_manager_ready` fans out bindings to `TerrainEditor`, `EntityManager`, visual registry, world visuals, combat VFX, config/performance.
8. `CrystalManager` waits for world, chunk manager, spawn area, and features; initializes fluid sim, spawns, chunk-layer views, and perf config.
9. Player spawn and UI/visual refresh complete lazily.

Critical contract: `GameVisualRegistry.ensure_textures_ready()` means textures only. It must not wait for chunks during `WorldFeatures` bootstrap, because `VoxelWorld` creates chunks only after features are ready.

## Chunk And Terrain System

Key files:

- `chunks/chunk_data.gd`
- `chunks/chunk_manager.gd`
- `chunks/chunk_mesh_buffer_builder.gd`
- `chunks/chunk_view.gd`
- `scenes/ChunkView.tscn`
- `shaders/ChunkView.gdshader`
- `helpers/voxel_types.gd`
- `helpers/voxel_geometry_kind.gd`
- `helpers/terrain_ramps.gd`
- `world/InfiniteNoiseWorld.gd`
- `world/terrain_edits.gd`
- `world/terrain_editor.gd`

Current terrain is not a full 3D voxel volume. It is a heightfield path optimized for performance:

- `ChunkData.SIZE = 16`.
- `surface_map[x][z]` stores surface height.
- `tile_map[x][z]` stores surface tile.
- Full 3D voxel/visibility arrays were removed for runtime performance.
- `get_voxel`/visibility synthesize from maps for compatibility.
- `ChunkData.HEIGHT` exists as a legacy/safety bound; prefer `WorldSettings` helpers for real height interpretation.

Generation lifecycle:

1. `ChunkManager.request_chunk(coord)`.
2. Main thread creates `ChunkData` and calls `capture_worker_snapshot()`.
3. Snapshot copies terrain edits, build tiles, feature tile overrides, and one-cell halo surfaces.
4. Worker task computes column maps and mesh payload from worker-safe world calls.
5. Main thread checks generation token, drops stale results, instantiates/updates `ChunkView`, uploads MultiMesh buffers, emits `chunk_ready`.
6. Streaming unloads distant chunks and emits `chunk_unloaded`.

Meshing:

- Greedy top rectangles for flat surface cells.
- Side lips/walls for height deltas.
- Ramp, diagonal, concave, side, and approach geometry.
- Built/dug strata where terrain edits require visible layers.
- Bottom faces are intentionally disabled for FPS on the main heightfield path.
- Cave mesh emission exists behind configuration/performance paths.

Rebuild rules:

- Terrain edits can affect neighboring chunks because side lips, halos, and ramps depend on adjacent columns.
- `TerrainEditor.rebuild_ring_for_cell()` returns ring `1` near chunk edges.
- Use `ChunkManager.rebuild_chunk_at_world` or region rebuild APIs rather than manually poking views.
- `ChunkManager` uses monotonic tokens to drop stale worker results.
- Teardown uses `release_all_chunks_for_teardown()` to avoid headless exit aborts; do not bypass worker shutdown.

Texture/atlas:

- Production chunk atlas is `assets/tiles/Cube.png`.
- Atlas metadata is in `helpers/voxel_types.gd`: 7 columns x 10 rows x 48 px.
- `new_tile_set.tres` / `voxelsnew.png` use a different layout and should not be bound to `ChunkView`.
- `VoxelTypes.get_atlas_coord_for_face()` handles Minecraft-style side/top face selection.

## World Generation

Key files:

- `world/InfiniteNoiseWorld.gd`
- `world/biome_layout.gd`
- `config/world_gen_config.gd`
- `config/world_settings.gd`
- `helpers/world_border.gd`
- `helpers/voxel_types.gd`

`InfiniteNoiseWorld` owns deterministic base terrain. It uses seed-derived FastNoiseLite generators for height, detail, temperature, moisture, ruggedness/borders, and rivers. The intended biome set is grounded in real-life terrain: plains, steppe, forest, marsh, mountain, with terrain tile variants such as grassland, hills, mountains, snow, valleys, basins, rivers, water, stone, dirt.

Rivers are topo-guided and carved into lowered surfaces. They should traverse biomes by geography rather than biome label alone.

Worker code must use worker-safe/uncached query paths. Do not read live mutable registries or scene nodes from generation workers except via snapshots captured on the main thread.

Keep generation deterministic from seed/config. If adding noise or feature placement, seed it explicitly and include it in save/load/config thinking.

## Player, Camera, Movement, Targeting

Key files:

- `player/player.gd`
- `player/camera.gd`
- `player/voxel_floor_probe.gd`
- `player/action_targeting.gd`
- `player/target_highlight.gd`
- `helpers/world_visual_coords.gd`
- `helpers/gameplay_input.gd`
- `config/world_settings.gd`

The player is a `CharacterBody3D`, but movement is custom voxel-aware logic. Do not assume Godot physics body movement is authoritative.

`VoxelFloorProbe` is the shared model for surface/collision sampling. It resolves:

- loaded `ChunkData` when available
- fallback world queries
- ramps and landing ramps
- optional cave floors
- crystal walkability/contact height
- multi-offset checks for grounded, step, blocked, and landing behavior

Keep coordinate spaces separate:

- Logical terrain columns/voxel positions.
- Surface heights in world/settings units.
- Godot visual transforms.
- Camera-facing and screen-space targeting.

Use `WorldSettings` and `WorldVisualCoords` helpers rather than ad hoc conversion.

Camera:

- Orthographic isometric child camera.
- Q/E or configured actions rotate in 90-degree steps.
- Mouse wheel zoom.
- Because camera rotates, "forward" and screen direction cannot be hardcoded to world north.

Targeting:

- `ActionTargeting` is the canonical targeting resolver.
- It casts/filters candidate terrain columns for dig/build/attack and supports forward fallback where appropriate.
- `TargetHighlight` visualizes resolved action cells: orange dig, green build, red attack.
- Do not implement a second targeting rule in weapons/tools. Add modes/queries to `ActionTargeting` and verify across camera rotations.

## Terrain Editing, Building, Planting, Channels

Key files:

- `world/terrain_editor.gd`
- `world/terrain_edits.gd`
- `world/channel_registry.gd`
- `world/plantable_registry.gd`
- `building/building_registry.gd`
- `config/buildable_def.gd`
- `config/plantable_def.gd`
- `helpers/item_types.gd`

`TerrainEditor` is the high-level entry for player edits:

- `try_dig`
- `try_build` / `try_build_wall`
- `try_plant`
- `try_channel_water`

It handles edit eligibility, inventory consumption/grants, feature/building registration, channel updates, and chunk invalidation. Use it instead of directly changing `TerrainEdits` from gameplay code unless you are writing a lower-level tool/test.

Edits must update all affected systems:

- Terrain overlay.
- Feature/building/channel overlay if relevant.
- Inventory/resource state if player action.
- Chunk rebuild.
- Crystal terrain query/pathing implications.
- Save/load snapshot if new state type is introduced.
- Visual refresh if feature/entity/building layers depend on it.

Known sensitivity: ramps, walls, and terrain edits interact through geometry kinds and chunk-border halos. Be cautious changing ramp placement, stacked walls, or edge rebuild scope.

## Crystal System

Key files:

- `crystal/crystal_manager.gd`
- `crystal/crystal_fluid_sim.gd`
- `crystal/crystal_terrain_query.gd`
- `crystal/crystal_chunk_layer.gd`
- `crystal/crystal_cell.gd`
- `crystal/crystal_evolution.gd`
- `crystal/spawn_point_controller.gd`
- `crystal/crystal_spawn_point.gd`
- `config/crystal_sim_config.gd`
- `config/spawn_point_registry.gd`
- `config/spawn_point_def.gd`
- `helpers/crystal_types.gd`

`CrystalManager` owns corruption state and connects simulation, terrain query, spawn points, absorption/evolution, visuals, and persistence. It emits signals such as:

- `fluid_changed`
- `power_changed`
- `spawn_destroyed`
- `spawn_damaged`
- `all_spawns_destroyed`
- `crystal_touched_player`
- `absorption_completed`

The fluid model is pressure-pooling crystal flow, not generic water. It has performance caps:

- tick rate / skip frames
- substeps
- processed cell caps
- new cell caps
- spread damping
- loaded-chunk-only policy
- mesh rebuild budgets
- depth epsilon
- absorption scan budgets

`CrystalTerrainQuery` is a broad boundary. It combines world heights, chunks, terrain edits, water/channels, features, plants, buildings, and config. Changes here can affect crystal routing, player contact, entity behavior, save data, map display, and performance.

Crystal visuals are chunk-layer MultiMeshes, not one node per cell. Partial/full rebuild decisions are budgeted. Respect dirty queues and rebuild caps.

Design target: crystal should eventually look and feel like it settles/flows slowly, not like random checkerboard growth. Manual notes mention checkerboard-looking crystal as a known visual/design issue.

## Entities, Vegetation, Towns, Ruins, Features

Key files:

- `world/world_features.gd`
- `world/feature_registry.gd`
- `world/feature_visual_layer.gd`
- `world/vegetation_manager.gd`
- `world/vegetation_growth_manager.gd`
- `world/town_manager.gd`
- `world/town_defense_manager.gd`
- `world/ruin_manager.gd`
- `entities/entity_manager.gd`
- `entities/world_entity.gd`
- `entities/entity_navigation.gd`
- `entities/entity_brain.gd`
- `entities/crystal_enemy.gd`
- `entities/crystal_enemy_spawner.gd`
- `helpers/world_feature_types.gd`
- `helpers/voxel_prop_builder.gd`
- `helpers/voxel_primitive_meshes.gd`
- `helpers/visual_proximity.gd`

`WorldFeatures` seeds and binds towns, vegetation, ruins, and entities after config/perf/textures are ready and before chunk generation. This is important: chunks snapshot features during worker generation.

`FeatureRegistry` is canonical feature overlay state. `FeatureVisualLayer` and other visuals render derived feature state under `WorldVisuals`.

Vegetation/entities may use voxel props or billboard visuals based on performance settings. Existing manual notes call out trees/grass/billboards/scale as active visual concerns, so verify visually when touching this area.

Entity navigation should share terrain/collision logic through the floor probe/query model where possible. Do not invent independent height/path rules unless encapsulated and tested.

## Combat, Inventory, Stats, Relics

Key files:

- `weapons/weapon_controller.gd`
- `systems/combat_hit_resolver.gd`
- `systems/combat_visual_feedback.gd`
- `systems/combat_log.gd`
- `inventory/inventory.gd`
- `ui/hotbar.gd`
- `ui/inventory_panel.gd`
- `stats/stat_component.gd`
- `stats/stat_sheet.gd`
- `stats/stat_ids.gd`
- `relics/relic_manager.gd`
- `relics/relic_registry.gd`
- `config/combat_def.gd`
- `config/relic_def.gd`

Combat flow:

1. Input reaches `WeaponController` after `GameplayInput` gating.
2. Weapon reads active inventory item, cooldown, stats, and config.
3. Target resolution uses `ActionTargeting`.
4. Hit resolution uses `CombatHitResolver` against entities and crystal spawn points.
5. Damage/state changes emit signals.
6. `CombatVisualFeedback` observes signals for bursts, indicators, and labels.

Keep visuals as observers. They should not decide combat outcomes.

Manual notes indicate historical sword targeting issues, forward-only swing behavior, and block/highlight placement concerns. Relevant tests include targeting, melee, combat entity hit, and crystal damage probes.

## Game State And UI

Key files:

- `game/game_manager.gd`
- `ui/game_overlay.gd`
- `ui/debug_panel.gd`
- `ui/dev_chat_overlay.gd`
- `ui/topographical_map.gd`
- `systems/topographical_map_builder.gd`
- `systems/dev_tools_coordinator.gd`
- `systems/developer_assistant.gd`
- `systems/bug_reporter.gd`

`GameManager` observes game outcome signals such as all crystal spawns destroyed, player touch/death, and phase/run state. It publishes state to overlay/VFX. Do not put core win/loss authority in UI.

Dev tooling:

- `T` opens dev chat.
- Non-slash chat uses a JSONL file bridge for an external assistant, not a networked AI service.
- `F3` toggles debug UI.
- `F11` captures a bug-report bundle.
- Dev commands support status, presets, teleport, scenario setup, item grants, and bug reports.

Topographical map has dedicated builder/config/tests. Changes to terrain/crystal/features may need map updates.

## Save/Load

Key files:

- `systems/save_game_service.gd`
- `systems/save_codec.gd`
- `config/save_game_config.gd`

Save state persists canonical data:

- terrain edits
- channels
- features
- crystal state
- player/entity/enemy/game/town state

It does not persist terrain render nodes or visual layers as authority.

Load ordering matters:

1. Wait for feature/crystal bootstrap where required.
2. Apply overlays first.
3. Invalidate world caches and rebuild chunks.
4. Await idle/ready state.
5. Restore crystal/runtime systems that need terrain/chunks.
6. Restore player/entities/game/town state.
7. Request visual refresh.

Use `SaveCodec` for JSON-safe vector/key representation.

## Performance Model

Key files:

- `systems/performance_service.gd`
- `systems/perf_profiler.gd`
- `config/performance_quality_config.gd`
- `systems/game_visual_registry.gd`

Performance presets:

- Environment: `CRYSTALSTORM_PERF_PRESET=low|medium|high|safe`
- Safe mode: `CRYSTALSTORM_SAFE_MODE=1`
- Default target is medium unless config/environment overrides.

Important performance assumptions:

- Chunk rendering uses MultiMesh groups, not per-voxel nodes.
- Chunk generation is worker-threaded.
- Main-thread upload/drain is budgeted.
- Render distance default is low/moderate (`RENDER_DISTANCE` commonly 3).
- Crystal sim and mesh rebuilds are capped.
- Visual feature richness depends on performance settings.
- Debug UI updates are rate-limited.

Before increasing visual density, render distance, chunk drain, crystal cell processing, or per-frame rebuild work, run relevant performance probes.

## Important Files Quick Map

Architecture/docs:

- `AGENTS.md`: mandatory project rules.
- `AI_CONTEXT.md`: this file.
- `studio/ENGINE_ARCHITECTURE.md`: detailed runtime architecture.
- `studio/engineering/AI_DEVELOPMENT.md`: AI workflow guidance.
- `STABILIZATION.md`: current stabilization board and known verification state.
- `manual_verification.md`: human-only manual verification checklist/results.
- `VISION.md`, `prompts/premise`: design intent.

Scenes/project:

- `project.godot`
- `scenes/main.tscn`
- `main.gd`
- `scenes/ChunkView.tscn`
- `scenes/world_viewer.tscn`

Core terrain/runtime:

- `world/InfiniteNoiseWorld.gd`
- `chunks/chunk_manager.gd`
- `chunks/chunk_data.gd`
- `chunks/chunk_mesh_buffer_builder.gd`
- `chunks/chunk_view.gd`
- `world/terrain_editor.gd`
- `world/terrain_edits.gd`
- `helpers/voxel_types.gd`
- `helpers/terrain_ramps.gd`
- `helpers/world_visual_coords.gd`
- `config/world_settings.gd`

Player/action:

- `player/player.gd`
- `player/camera.gd`
- `player/voxel_floor_probe.gd`
- `player/action_targeting.gd`
- `player/target_highlight.gd`

Crystal:

- `crystal/crystal_manager.gd`
- `crystal/crystal_fluid_sim.gd`
- `crystal/crystal_terrain_query.gd`
- `crystal/crystal_chunk_layer.gd`
- `crystal/spawn_point_controller.gd`
- `config/crystal_sim_config.gd`

Features/entities/visuals:

- `world/world_features.gd`
- `world/feature_registry.gd`
- `world/feature_visual_layer.gd`
- `world/world_visuals.gd`
- `entities/entity_manager.gd`
- `entities/world_entity.gd`
- `systems/game_visual_registry.gd`
- `systems/crystal_texture_generator.gd`

Combat/game/ui/save:

- `weapons/weapon_controller.gd`
- `systems/combat_hit_resolver.gd`
- `systems/combat_visual_feedback.gd`
- `game/game_manager.gd`
- `inventory/inventory.gd`
- `ui/game_overlay.gd`
- `systems/save_game_service.gd`
- `systems/save_codec.gd`

Verification:

- `scripts/run_all_verify.gd`
- `scripts/run_all_verify.sh`
- `scripts/smoke_probe_helpers.gd`
- `scripts/run_smoke_gameplay.sh`
- `scripts/run_display_session.sh`
- many focused `scripts/verify_*.gd`

## Known Issues / Active Risk Areas

The codebase has many automated probes, but manual notes still matter. Current/historical risk areas include:

- Human visual verification is the final gate for "Working" status. Automated probes prove partial/corroborated behavior.
- Ramps have been a recurring source of holes, missing floor textures, diagonal/corner issues, side-cell problems, and collision/pathing mismatches.
- Terrain build/dig can accidentally rebuild too much, fail to rebuild neighbor border geometry, or hide highlights below terrain.
- Stacked walls need intermediate tops/sides so lower blocks remain visible.
- Build walls should not accidentally create terrain ramps.
- Collision has been called buggy in manual notes; movement changes need player collision/jump/ramp tests.
- Targeting must respect camera rotation and mouse column selection; sword, pickaxe, block placement, and forward fallback have had regressions.
- Highlight behavior should work for relevant tools/weapons and show selected target clearly.
- Crystal visuals have had checkerboard/live-looking spread; desired behavior is slow settling/pooling.
- Some entities/vegetation have used billboards/placeholders or incorrect scale; voxel prop settings/perf flags are sensitive.
- Texture atlas work is active; terrain should look Minecraft-esque and descriptive of real-life material, not solid flat colors.
- Chunk streaming and teardown can fail if worker tokens/shutdown are bypassed.
- Boot deadlocks can occur if visual readiness waits for chunks too early.
- Saves must restore overlays before chunk rebuilds and runtime systems.
- Worktree may be dirty with unrelated changes; do not revert them.

## Common Pitfalls

- Treating `ChunkView` or visual nodes as gameplay authority.
- Reading live `TerrainEdits`, `FeatureRegistry`, or scene nodes from worker generation instead of using snapshots.
- Adding scene-tree changes inside worker tasks.
- Assuming `ChunkData` is full 3D voxel storage; it is currently heightfield maps plus compatibility helpers.
- Assuming `ChunkData.HEIGHT` is the world height. Prefer `WorldSettings`.
- Hardcoding world north for targeting or combat despite camera rotation.
- Creating another targeting/collision query path instead of extending `ActionTargeting`/`VoxelFloorProbe`.
- Updating terrain without rebuilding affected neighbor chunks.
- Updating terrain/building/feature state without considering crystal terrain query and saves.
- Binding the wrong atlas (`voxelsnew.png`/`new_tile_set.tres`) to production chunk rendering.
- Adding one node per voxel/cell/plant in hot paths.
- Ignoring performance presets and SAFE mode.
- Editing `manual_verification.md` to claim automated results as human sign-off.
- Trusting old README statements over current code and `studio/` docs.
- Referencing legacy scenes from production.

## Workflow

Standard change workflow:

1. Check status: `git status --short`.
2. Read this file, `AGENTS.md`, affected files, and nearest tests.
3. Identify the canonical owner of the behavior.
4. Make a scoped change.
5. Add or update focused verification if the behavior is regression-prone.
6. Run targeted tests first.
7. Run broader suite for cross-system changes where practical.
8. Report exactly what changed and which tests ran.

Run the game:

```bash
godot .
godot scenes/main.tscn
CRYSTALSTORM_PERF_PRESET=medium godot scenes/main.tscn
CRYSTALSTORM_SAFE_MODE=1 godot scenes/main.tscn
```

Run all headless verification:

```bash
godot --headless -s scripts/run_all_verify.gd
bash scripts/run_all_verify.sh
```

Targeted examples:

```bash
godot --headless -s scripts/verify_target_facing.gd
godot --headless -s scripts/verify_terrain_build.gd
godot --headless -s scripts/verify_terrain_dig.gd
godot --headless -s scripts/verify_player_collision.gd
godot --headless -s scripts/verify_crystal_terrain_routing.gd
godot --headless -s scripts/verify_save_terrain.gd
bash scripts/run_smoke_gameplay.sh
bash scripts/run_display_session.sh
```

`scripts/run_all_verify.sh` is the authoritative suite list. Some main-scene probes intentionally match OK markers because Godot teardown may abort after a successful probe. Do not "fix" that harness behavior casually; understand it first.

When adding a durable regression test, add it to `scripts/run_all_verify.sh` if it should be a project gate.

## Verification Discipline

Use the narrowest relevant test before the full suite. Suggested mapping:

- Boot/readiness: `verify_bootstrap_no_deadlock.gd`, `verify_chunk_bootstrap.gd`, `verify_main_runtime_health.gd`, `verify_visual_boot_order.gd`
- Chunk/terrain mesh: `verify_chunk_atlas.gd`, `verify_chunk_surface_zero.gd`, `verify_chunk_rebuild_perf.gd`, `verify_chunk_incremental_scope.gd`
- Dig/build: `verify_terrain_dig.gd`, `verify_terrain_build.gd`, `verify_terrain_edit_boundary_ring.gd`, `verify_dug_strata_no_cap.gd`
- Ramps: `verify_ramp_*.gd`, `verify_voxel_geometry_path.gd`
- Movement/collision: `verify_player_jump.gd`, `verify_jump_while_moving.gd`, `verify_player_collision.gd`, `verify_built_wall_collision_main.gd`
- Target/highlight: `verify_target_facing.gd`, `verify_target_highlight.gd`, `verify_forward_highlight.gd`, `verify_build_highlight_placement.gd`, `verify_dig_highlight_placement.gd`, `verify_melee_forward_targeting.gd`
- Combat: `verify_weapon_attack.gd`, `verify_combat_entity_hit.gd`, `verify_combat_crystal_damage.gd`, `verify_combat_parse.gd`
- Crystal: `verify_crystal_spread_limits.gd`, `verify_crystal_frontier_density.gd`, `verify_crystal_settling.gd`, `verify_crystal_flow_mechanics.gd`, `verify_crystal_live_spread.gd`, `verify_crystal_terrain_routing.gd`, `verify_crystal_grid_align.gd`
- Entities/visuals: `verify_entity_*`, `verify_vegetation_*`, `verify_game_visuals.gd`, `verify_visual_pipeline.gd`, `verify_visual_texture_binding.gd`, `verify_visual_perf.gd`
- Save/load: `verify_save_terrain.gd`, `verify_save_slot_main.gd`, `verify_save_slot_inner.gd`
- Full loop/smoke: `verify_full_game_loop.gd`, `verify_smoke_gameplay.gd`, `verify_smoke_contract.gd`, `verify_display_session_log.gd`
- Dev tools: `verify_dev_chat.gd`, `verify_dev_tools.gd`, `verify_dev_tools_input.gd`

Display/human-sensitive behavior is not fully proven by headless tests. Use `manual_verification.md` as the human gate. Automated scripts must not edit it to claim human sign-off.

Headless mouse discipline:

- Some smoke helpers warp the mouse onto target columns.
- Probes asserting no-mouse or forward-fallback behavior must call `SmokeProbeHelpers.clear_mouse_offscreen(player)` afterward.
- Co-located player/entity placement can bypass honest melee coverage; do not rely on that as complete combat proof.

## What To Do When Unsure

If behavior touches terrain, ask: what is canonical state, what is derived mesh, what chunks/neighbors rebuild, what queries need to see it, and how does it save?

If behavior touches crystal, ask: does `CrystalTerrainQuery` see the same world the player sees, are sim caps preserved, and are dirty visual rebuilds budgeted?

If behavior touches visuals, ask: which `WorldVisuals` layer owns it, what performance flags affect it, and how does it clean up on chunk unload?

If behavior touches controls/combat, ask: does `ActionTargeting` resolve it under camera rotation, and does `TargetHighlight` show the same target?

If behavior touches boot, ask: could this create a wait cycle between config, performance, visual texture readiness, feature seeding, chunk creation, or crystal readiness?

If behavior touches saves, ask: is state restored before dependent chunks/systems rebuild, and is the encoding JSON-safe?

When in doubt, write or run the focused verification probe before broad changes.
