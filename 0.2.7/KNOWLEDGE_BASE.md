# Crystal Storm Knowledge Base

This is the engineering encyclopedia for Crystal Storm. It extracts assumptions, constraints, algorithms, engineering decisions, constants, magic numbers, and implicit rules from the active source tree.

Scope reviewed: active Godot source and configuration files under `inventory/`, `ui/`, `building/`, `relics/`, `stats/`, `chunks/`, `systems/`, `fluids/`, `entities/`, `world/`, `helpers/`, `addons/`, `crystal/`, `config/`, `game/`, `player/`, `weapons/`, `scenes/`, `shaders/`, `scripts/`, plus `project.godot`, `export_presets.cfg`, and project docs already generated in this session. `archive/legacy/`, `.git/`, `.godot/`, and `venv/` are non-authoritative for production behavior.

## 1. Project Identity

Crystal Storm is a Godot 4.6+ voxel terrain action/strategy game. The core design assumption is that terrain is the player's primary weapon. The player reshapes terrain to slow an expanding crystal corruption, then fights back against crystal spawn points.

The game does not revolve around defending a single base. It revolves around:

- exploration
- digging
- building walls
- planting/terrain preparation
- water/channel manipulation
- redirecting crystal flow
- direct combat
- destroying spawn points
- eventually destroying the origin/source

The intended loop has two phases:

- Maze phase: longer strategic terrain editing and preparation.
- Assault/combat phase: shorter direct pressure and spawn destruction.

Production gameplay is the 3D heightfield voxel runtime. Legacy 2D code is archived and should not be wired into production.

## 2. Authoritative Runtime Entry Points

Production main scene:

- `project.godot` sets `run/main_scene="res://scenes/main.tscn"`.
- `scenes/main.tscn` root is `Game`, a `Node3D` with `main.gd`.
- `main.gd` is intentionally short and documents boot order.

Autoloads:

- `CrystalTextureGenerator="*res://systems/crystal_texture_generator.gd"`
- `PerfProfiler="*res://systems/perf_profiler.gd"`

Renderer/engine assumptions:

- Godot 4.6, Forward Plus.
- Jolt Physics.
- Viewport stretch mode.
- Canvas texture default filter `0` for pixel clarity.
- 2D transform snapping enabled.
- Windows rendering driver set to `d3d12`.

Main scene node order:

1. `ConfigService`
2. `PerformanceService`
3. `GameVisualRegistry`
4. `World`
5. `VoxelWorld`
6. `WorldVisuals`
7. `WorldFeatures`
8. `CrystalManager`
9. `GameManager`
10. `TerrainEditor`
11. `VoxelFluidService`
12. `SaveGameService`
13. dev tools
14. environment/light
15. `Player`
16. `CanvasLayer` UI

The scene order is not enough by itself. Readiness is controlled by groups, deferred calls, `ensure_ready()` loops, and explicit binding.

## 3. Architectural Principle

Rendering is derived state. Gameplay authority is not in meshes, `ChunkView`, `MultiMeshInstance3D`, Sprite3D, billboard nodes, or visual layers.

Canonical state lives in:

- `InfiniteNoiseWorld`: deterministic base terrain.
- `TerrainEdits`: dig/build height and build tile overlay.
- `FeatureRegistry`: towns, ruins, vegetation, placed features, feature tile overrides.
- `ChannelRegistry`: player-made water/channel overlay.
- `CrystalManager` / `CrystalFluidSim`: crystal depths, spawn points, absorption, evolution.
- `Inventory`, stats, relics, entities, game state.
- Save snapshots of canonical state.

Derived state includes:

- `ChunkData` worker snapshots.
- `ChunkView` meshes.
- crystal chunk layers.
- feature/entity/vegetation visual nodes.
- topographical map textures.

Implicit rule: if a feature affects collision, pathing, crystal flow, map display, save/load, or persistence, add it to canonical state first and render it second.

## 4. Boot Contracts

Current boot chain:

1. Autoloads create procedural texture generator and profiler.
2. `ConfigService` creates/defaults `GameConfig`, activates `WorldSettings`, registers built-in content, and pushes config to available systems.
3. `PerformanceService` selects a preset from env/config and applies it after scene nodes exist.
4. `GameVisualRegistry` waits for performance, generates/caches textures, and marks texture readiness.
5. `WorldFeatures` waits for config/performance/texture readiness/world, resets overlays, and seeds feature registries.
6. `VoxelWorld` waits for `WorldFeatures.ensure_ready()` before creating `ChunkManager`.
7. `ChunkManager` streams initial chunks around the player.
8. `WorldFeatures.on_chunk_manager_ready()` binds chunk manager to terrain, entities, visuals, VFX, config, and performance.
9. `CrystalManager` waits for world, chunk manager, spawn area readiness, and features before initializing simulation and spawns.
10. Player, UI, visuals, save, and dev tools finish lazy binding.

Critical hidden constraint:

- `GameVisualRegistry.ensure_textures_ready()` means texture bundle only. It must not wait for chunks because chunks are created after `WorldFeatures` waits for visual texture readiness.

Boot risks:

- Circular waits between visual readiness, feature seeding, chunk creation, and crystal readiness.
- Using `get_first_node_in_group()` before the target node enters its group.
- Assuming a sibling node is ready merely because it exists in `main.tscn`.

## 5. World Scale And Coordinates

`WorldSettings` is the single knob for scale.

Important defaults:

- `voxel_scale = 2.0`
- `max_world_height_voxels = 20`
- `chunk_size_voxels = 16`
- `max_height_world_units = max_world_height_voxels * voxel_scale`
- `legacy_height_reference = 158.0`

Derived rules:

- One terrain layer is `voxel_scale` world units.
- `column_to_world(column) = column * voxel_scale`.
- `world_to_column(world) = world / voxel_scale`.
- `chunk_world_size = chunk_size_voxels * voxel_scale`.
- Feet sit on top of solid voxel columns: `surface_y + layer_height`.
- Step height window is roughly `0.85x` to `1.35x` layer height.
- Cliff height is `1.05x` layer height.
- Player height is `0.4x` layer height.
- Player radius is `0.2x` layer height.
- Floor snap distance is `0.3x` layer height.
- Max walking step is `1.08x` layer height.
- Max jump step snap is `5x` layer height.

Implicit rule: do not use hardcoded world-unit conversions. Use `WorldSettings` and `WorldVisualCoords`.

## 6. Input Bindings

Declared in `project.godot`:

- `jump`: M
- `rotate_left`: Q
- `rotate_right`: E
- `attack`: mouse left and F
- `inventory_toggle`: I
- `interact`: R
- `build_place`: mouse right
- `plant`: G
- `channel_water`: Shift+T
- `dev_chat_toggle`: T
- `debug_overlay_toggle`: F3
- `bug_report`: F11
- `quick_save`: F5
- `quick_load`: F9
- `toggle_map`: U
- hotbar 1-8: number keys

`GameplayInput.blocks_actions()` gates gameplay when dev chat is open. Dev chat forcibly releases mapped actions when opened to avoid stuck input.

Implicit conflict: `bug_report` and `quick_load` both appear tied to function-key style physical key values in `project.godot`. Verify bindings in-editor when changing input.

## 7. Terrain Model

Terrain is a streamed heightfield voxel renderer, not a full arbitrary 3D voxel volume.

`ChunkData` stores:

- `SIZE = 16`
- 16x16 `surface_map`
- 16x16 `tile_map`
- `ramp_map`
- `geometry_map`
- worker snapshot arrays for height deltas, build tiles, feature tile overrides
- one-cell halo surface data

Legacy full 3D voxel arrays were intentionally removed for performance. `get_voxel()` and visibility APIs synthesize surface-only values for compatibility.

`ChunkData.HEIGHT` is legacy/safety bound, currently `48`. Prefer `WorldSettings.chunk_height_bound()`.

Generation:

1. Main thread captures snapshot with `ChunkData.capture_worker_snapshot()`.
2. Worker computes column maps using worker-safe world calls.
3. Worker builds mesh quads and optionally packed buffers.
4. Main thread drops stale results using monotonic generation tokens.
5. `ChunkView` uploads MultiMesh groups.

Threading constraint:

- Worker generation must use snapshot/uncached/pure paths. It must not query live scene tree or mutate nodes.

Streaming constants:

- `ChunkManager.RENDER_DISTANCE` default export is `3`, but performance presets commonly override to 1/2/3.
- `MAX_CHUNKS_PER_FRAME` default export is `2`.
- `MAX_INFLIGHT_CHUNKS` default export is `6`.
- `chunk_upload_budget_us` default is `3500`.
- `prebuild_chunk_buffers = true`.

Terrain edit rebuilds:

- Chunk edges are sensitive because halos, lips, ramps, and side faces depend on neighbors.
- `TerrainEditor.REBUILD_EDGE_BAND = 2`.
- Cells within 2 columns of a chunk edge rebuild ring 1.
- Region rebuilds are deferred and coalesced via `_rebuild_pending`.

Implicit rule: terrain edit code should call `TerrainEditor`/`ChunkManager` rebuild APIs, not directly mutate chunk views.

## 8. Terrain Meshing

Meshing algorithm:

- Emit ramps first.
- Emit concave corner prisms.
- Finalize surface geometry kinds.
- Emit dug strata.
- Emit built strata.
- Greedy mesh top rectangles.
- Greedy/merged side walls/lips for cardinal sides.
- Emit cardinal ramp flank faces.
- Optionally emit cave faces.

Bottom faces are disabled for the main heightfield path.

Face codes:

- top `0`
- bottom `2`
- negative X `3`
- positive X `4`
- negative Z `5`
- positive Z `6`
- ramp `7`
- ramp corner `8`
- ramp side `9`

Mesh payload:

- Current representation uses dictionaries of quads and grouped `PackedFloat32Array` buffers.
- `ChunkMeshBufferBuilder.STRIDE = 16`.
- Per instance stores 12 transform floats plus 4 custom-data floats.
- Atlas x/y are encoded as normalized floats in custom data.
- Face code and `uv_h` are encoded together as `face_code + uv_h / 100.0`.
- `uv_w` is stored as custom data float 15.

Mesh groups:

- full cube
- half cube
- cardinal ramps
- corner ramps
- concave prism variants

Engineering decision: use MultiMesh groups with shared primitive meshes instead of a mesh or node per terrain cell.

## 9. Ramps And Geometry

Ramps bridge one-layer height steps. Their valid step range comes from `WorldSettings`.

Ramp representations are dictionary entries in `ChunkData.ramp_map`:

- cardinal: `corner=false`, `side=false`, `approach=false`, `dir`
- approach: `approach=true`, `dir`
- corner: `corner=true`, `dir`, `dir2`
- side: `side=true`, `dir`, `dir2`
- concave: `concave=true`, `side=true`, `dir`, `dir2`, `surface_h`

`VoxelGeometryKind` maps entries to geometry kinds and mesh groups. Geometry kinds replace full cube rendering when applicable.

Implicit ramp rules:

- Player-built walls suppress ramp generation.
- Ramps should replace or modify the cell they occupy, not add incoherent extra geometry.
- Side lips should be suppressed where a ramp covers a drop.
- Diagonal/corner ramps are fragile and heavily tested.
- Collision, mesh, and targeting must agree about ramp height.

Relevant tests:

- `verify_ramp_*`
- `verify_voxel_geometry_path.gd`
- `verify_player_collision.gd`
- `verify_built_wall_collision_main.gd`

## 10. Voxel Types And Atlas

`VoxelTypes` assigns integer IDs:

- `AIR = 255`
- ocean 0-2
- beach 3-5
- grassland 6-10
- hills/forest 11-14
- mountain 15-21
- snow 22-24
- valley 25-27
- desert 28-30
- tundra 31-33
- basin 34-36
- `RIVER = 37`
- `WATER = 38`
- `STONE = 39`
- `STONE2 = 40`
- `DIRT = 41`
- `DIRT2 = 42`
- `CAVE_STONE = 43`
- `CRYSTAL = 44`
- `GRASS_TUFT = 45`
- `BUSH = 46`
- `TREE_TRUNK = 47`
- `FARMLAND = 48`
- `TOWN_PATH = 49`

Production atlas:

- `assets/tiles/Cube.png`
- 7 columns
- 10 rows
- 48 px tiles

Do not bind `assets/tiles/new_tile_set.tres` or `voxelsnew.png` to production chunk rendering; they use another layout.

Face selection rule:

- Grass top uses grass; sides use dirt.
- Forest top uses forest tile; sides use trunk.
- Snow sides use stone.
- Desert sides use desert variant.
- Bottom uses `DIRT2`.

## 11. World Generation

`InfiniteNoiseWorld` owns deterministic base terrain.

World defaults:

- default seed `12349`
- temperature roll seed offset `777`
- biome scale `920.0`
- mountain frequency `1.0`
- detail frequency `4.5`
- legacy max height `158.0`
- sea level `38.0`
- mountain boost `78.0`

Algorithm:

- FastNoiseLite domain warp.
- Base height + detail noise.
- Biome layout regions with warp/blend softness.
- Temperature/moisture/ruggedness.
- River path/mask/carve noise.
- Border/ocean/mountain treatment.
- Optional cave noise.
- Terrain edits and feature tile overrides applied over base queries.

Interior biome assumption:

- The intended high-level biome identities are plains, steppe, forest, marsh, mountain.
- Tile IDs include extra visual/material variants beyond those five labels.

Rivers:

- Target prevalence `0.16`.
- Base frequency `0.068`.
- Scale factor `2.9`.
- Core power `1.95`.
- River threshold `0.19`.
- Surface tile threshold `0.22`.
- Max carve `17.0`.
- Mask threshold `0.013`.
- Carve threshold for river surface `11.5`.
- Warp strength `11.0`.
- Meander mix `0.30`.

Caves:

- Enabled by default in worldgen config, but cave meshing is normally disabled by performance presets.
- Cave constants include tunnel base `0.135`, room base `0.058`, scale factor `1.4`, tunnel weight `0.92`, room weight `1.28`, hollow base `0.39`, roof protect `0.12`.

World border:

- Playable half extents: 1024 x 1024 columns.
- Transition width `240.0`.
- Deep border `384.0`.
- Border sea level `38.0`.
- Ocean floor `22.0`.
- Mountain floor `88.0`.
- Mountain peak `138.0`.
- Border can block player movement and force/prefer ramps near edges.

Determinism rule: new generation features must derive from seed/config, not frame time or scene state.

## 12. Player Movement And Camera

Player is a `CharacterBody3D`, but movement is custom voxel-aware logic.

Player owns/creates:

- inventory
- stats
- weapon controller
- relic manager
- floor probe
- target highlight

Movement assumptions:

- `VoxelFloorProbe` is the shared surface sampler for player and entity navigation.
- It samples center plus radius offsets.
- It checks loaded chunk data first, then world fallback.
- It adjusts loaded snapshot surface with live terrain edit delta.
- It considers ramp entries and crystal walkable height.
- It supports cave floors when feet are far below surface.
- It blocks ocean movement in border zones.

Camera:

- Orthographic isometric.
- Target child of player.
- Smooth speed default `3.0`.
- Rotation speed `480 deg/sec`.
- Distance `100`.
- Height offset `101`.
- Zoom default `24`.
- Zoom step `2`.
- Min zoom `8`.
- Max zoom `140`.
- Orbit uses 90-degree steps, but visual yaw offset uses 45-degree isometric baseline.

Implicit rule: do not assume world north as player/action forward. Use camera/player targeting helpers.

## 13. Targeting And Highlighting

`ActionTargeting` is the canonical targeting resolver for terrain and combat.

It handles:

- movement/camera yaw
- mouse ray candidate cells
- terrain column AABBs
- face picking
- action validity filters
- forward fallback
- screen position for column
- mouse warp for probes
- attack target columns

Modes include dig/build/attack/any-like behavior. `TargetHighlight` uses the same resolver and colors:

- orange: dig
- green: build
- red: attack

Implicit rules:

- Weapons and tools should not implement their own target selection.
- Highlight must show the same cell the action will affect.
- Camera rotation must be tested for all targeting modes.
- Headless probes that warp mouse must clear it offscreen when testing forward fallback.

## 14. Terrain Editing, Building, Planting, Channels

`TerrainEditor` is the public gameplay entry point.

Actions:

- `try_dig`
- `try_build` / `try_build_wall`
- `try_plant`
- `try_channel_water`

Dig:

- Requires world and chunk manager.
- Uses `TerrainEdits.can_edit`.
- Refuses below `-layer_height * 4`.
- Grants loot by tile: wood from hills/trunks/bush, herb from basins/valleys, stone from stone/mountain/snow/cave.
- Dig delay: `0.04 + depth * 0.07 + depth^2 * 0.12`, divided by `DIG_SPEED`.

Build:

- Defaults to `stone_wall`.
- Uses `BuildingRegistry`.
- Consumes material count modified by `BUILD_COST`.
- Stone wall can fall back to wood if configured.
- Registers feature metadata with `build_id`, `flow_resistance`, and `player_built`.
- Build delay is `0.10 / DIG_SPEED`.

Plant:

- Uses `PlantableRegistry`.
- Consumes material.
- Sets tile override and feature metadata.
- Notifies vegetation growth manager.
- Plant delay is `0.45 / PLANT_SPEED`.

Channels:

- Modes: dig, raise, lower, redirect.
- Channel speed uses `CHANNEL_SPEED`.
- Water/channel behavior is stored in `ChannelRegistry` and used by crystal terrain query and generic fluid service.

Implicit rule: terrain actions need inventory/resource effects, overlay mutation, chunk rebuild, crystal-path implications, save/load coverage, and visual refresh.

## 15. Built-In Content

Items:

- `wooden_sword`: melee, 12 damage, range 2.8, cooldown 0.45.
- `stone_pick`: dig tool, 6 crystal damage, 5 entity damage, range 2.4, cooldown 0.22.
- `shortbow`: ranged, 10 damage, range 14, cooldown 0.8.
- Materials: wood, stone, herb.
- Max stack `99`.

Inventory:

- Hotbar size 8.
- Bag size 24.
- Total slots 32.
- Hotbar changes emit `hotbar_changed`.

Buildables:

- `stone_wall`: stone cost 1, wood fallback 2, tile STONE, flow resistance 0.85.
- `wood_wall`: wood cost 2, tile DIRT, flow resistance 0.55.
- `BuildableDef` supports max stack height 8 and placement range 2.0.

Plantables:

- grass tuft, tall grass, wildflower, fern, bush, tree.
- Bush/tree have multi-stage growth and area-denial effects.
- Tree denial radius 2, mature denial flow factor 0.1.

Entities:

- Passive animals: rabbit, deer, boar, bird.
- Town militia.
- Crystal enemies: crystal mite, farm bomber, crystal stag, thornling, corrupted beast, shard guard.

Spawn points:

- Origin boss: 500 health, boss, emit 3.2.
- Ruin miniboss: 120 health, emit 1.1, weaken 0.12, power drain 8.
- Artifact node: 80 health, emit 0.7, weaken 0.08, power drain 5.

Relics:

- `flow_anchor`: multiplies build flow block by 1.25.
- `mason_glove`: dig speed x1.35, build cost x0.8.

## 16. Stats

Stats are `StringName` IDs.

Defaults:

- max health 100
- health regen 0
- move speed 16
- jump force 70
- crystal resistance 0
- crystal damage 1
- crystal yield 1
- dig speed 1
- build cost 1
- plant speed 1
- channel speed 1
- melee damage 1
- ranged damage 1
- defense 0
- build flow block 0.85

Modifier operations:

- flat
- additive percent
- multiplicative

Formula:

`(base + flat_sum) * (1 + additive_percent_sum) * multiplicative_product`, then optional caps.

Implicit rule: relics and future buffs should use source IDs so modifiers can be removed/replaced by source.

## 17. Combat

Combat is controller + resolver + target signals.

`WeaponController`:

- Reads active hotbar item.
- Applies cooldown.
- Sends dig/build/plant/channel to terrain editor.
- Uses `ActionTargeting` for melee target column.
- Emits `attacked`, `dig_attempted`, `entity_hit`.

Melee:

- Default arc 70 degrees.
- Uses combat center/radius on entities.
- Config vertical tolerance 3.6.
- Max targets 4.
- If target-column melee misses, code also tries camera-forward fallback.
- Crystal spawn damage uses target cell and radius.

Ranged:

- Ray-like query with hit radius `ranged_hit_radius + target_radius * 0.5`.
- Default ranged hit radius 0.42.
- Vertical tolerance 2.5.

Damage:

- `final = base_damage * (1 - clamp(defense, 0, 0.9))`.
- Targets must implement `take_damage` to receive damage.

Implicit rule: VFX observes combat signals. VFX should not decide outcomes.

## 18. Crystal Simulation

`CrystalManager` is the high-level owner; `CrystalFluidSim` extends `VoxelFluidEngine`.

Crystal canonical state:

- depth per cell
- spawn ID per cell
- spawn points
- evolution state
- absorption progress
- ruin absorption progress
- chunk layer/dirty render state

Crystal flow model:

- Pressure pool, not normal water gravity.
- Depth min 0.04, max 12.0 by default.
- Pressure flow rate 0.20.
- Max flow per cell 0.28.
- Max outflow ratio 0.12.
- Lateral spread bias 0.12.
- Uphill penalty 0.06.
- Downhill bonus 0.30.

Water/rivers:

- River flow factor 0.06.
- Water build-over rate 0.35.
- Crystal can build over water but spreads into/out of rivers slowly.

Channels:

- Channel base flow factor 0.1.
- Along-flow multiplier 2.4.
- Cross-flow multiplier 0.3.
- Water-level flow scale 1.5.
- Channel equilibrate rate 0.4.

Emitters:

- Origin emit rate 0.42 in sim config; spawn def origin emit is 3.2.
- Ruin emit rate 0.55; spawn def ruin emit 1.1.
- Artifact emit rate 0.38; spawn def artifact emit 0.7.
- Initial spawn depth 2.0.
- Ruin spawn count 2.
- Artifact spawn count 1.
- Ruin distance 72-180.

Power:

- Power per volume 0.0025.
- Tier thresholds: 0, 20, 60, 140, 300, 600.
- `tier_from_power` returns highest threshold tier minus one.

Absorption:

- Grass/bush/tree/farmland have flow factors, absorb rates, and power boosts.
- Plants can define stage-specific flow/absorb behavior.
- Absorption can unlock enemies and grant relics.
- Hardcoded unlock-to-relic map: crystal mite -> mason glove; thornling/shard guard -> flow anchor.

Performance:

- Loaded-chunk-only sim is default.
- Crystal sim uses tick rate, skip frames, flow cell caps, new cell caps, mesh rebuild caps, and mesh depth epsilon.
- Dirty chunks are flushed under frame budget.

Implicit rule: `CrystalTerrainQuery` is the boundary between fluid math and terrain/features/buildings/channels. Changes there affect pathing, visuals, map, saves, and game rules.

## 19. Generic Fluid Engine

`VoxelFluidEngine` supports two models:

- pressure pool
- gravity channel

State:

- `depth: Dictionary`
- `max_cells_per_tick`
- `max_new_cells_per_tick`
- spread damping parameters
- empty-cell inflow cap
- depth write epsilon
- mesh depth epsilon

Algorithm:

- Select active cells.
- Prefer frontier cells when capped.
- For each cell, inspect cardinal neighbors.
- Compute surface level = terrain height + fluid depth.
- Apply flow conductivity from terrain, channel, water, and fluid config.
- Accumulate deltas.
- Apply deltas in batch.
- Cap new cells and sort pending new cells by magnitude.

Magic constants:

- Effective flow cap scales after 180 cells.
- Scaling uses `220 / n`, clamped 0.30-1.0.
- Empty-cell inflow defaults 0.018 in engine, usually overridden for crystal.
- Depth write changes below 0.02 are ignored in `set_depth`.

Water:

- Built-in water is gravity-channel, spread speed 2.4, viscosity 0.18, max flow distance 1.05, update 10 Hz, max depth 1.

Future stub fluids:

- lava, poison, oil exist as registry stubs.

## 20. Entities And Navigation

`EntityManager` seeds animals by chunk/biome and town defenders. It binds chunk streaming and despawns entities in unloaded chunks.

Defaults:

- animals per biome chunk 2
- max entities 128
- max defenders per town 8

Entity navigation:

- `EntityNavigation` can use `VoxelFloorProbe` for full terrain sampling.
- Performance presets can enable lightweight entity nav.
- Entities convert between world position and column cells.
- Step movement uses simple cell stepping, crystal avoidance/flee behavior, and snap-to-ground.

`WorldEntity`:

- Has brain/config/health/home cell.
- Visual can be voxel prop, sprite, or fallback capsule mesh.
- Hit flash and damage signals are local.
- Physics can be skipped by `entity_manager.physics_skip_frames`.
- It repeatedly binds scene dependencies if missing.

Implicit rule: entity visuals depend on `GameVisualRegistry` readiness and performance settings.

## 21. World Features, Towns, Vegetation, Ruins

`WorldFeatures` bootstraps:

- `FeatureRegistry`
- `ChannelRegistry`
- towns
- vegetation
- ruins
- entities

World features must seed before chunk generation so chunk worker snapshots include tile overrides.

Feature visual layer:

- Populates per loaded chunk.
- Budget per chunk defaults through visual registry/perf config.
- Vegetation can be voxel props or billboards.
- Buildings/ruins use billboards/textured meshes.
- Nodes are tracked by chunk and by cell for cleanup/growth refresh.

Vegetation:

- Grows by manager tick budget.
- Growth considers water/crystal modifiers.
- Plants can create denial zones slowing crystal spread.

Towns:

- Town managers seed and track settlements.
- Town defense reacts to crystal and can request militia.
- Town loss contributes to game-over checks.

Ruins:

- Ruins seed artifact/spawn interactions.
- Crystal can absorb ruins and clear them from feature state.

## 22. Visual Registry And Procedural Assets

`GameVisualRegistry` owns runtime texture lookup and visual configuration.

Defaults:

- entity sprites enabled.
- entity voxel models enabled.
- entity billboard distance 72 columns in registry, 56/72 by presets.
- feature billboards enabled.
- vegetation voxel models enabled.
- max feature billboards per chunk 48.
- surface lift 0.12.
- sprite pixel scale 0.026.

It uses `CrystalTextureGenerator` autoload when available, or creates a script instance fallback.

Important distinction:

- Texture readiness does not mean visual scene refresh has committed.
- `visuals_ready` means scene visual refresh completed.
- `post_bootstrap_refreshed` fires after chunk/world visual refresh.

Procedural texture generator:

- Generates crystal, ground, ore, combat UI, particles, entities, vegetation, buildings, item icons.
- Has palette JSON import/export.
- Editor plugin exists under `addons/crystal_texture_tools`.

Implicit rule: performance config controls whether entity/vegetation uses voxel models or billboards. Visual tests should account for both modes.

## 23. UI And Dev Tools

UI:

- `GameOverlay` shows phase, crystal coverage, spawn progress, progression/unlocks/relics, win/loss panels, and toasts.
- `Hotbar` has 8 slots, 52 px slot size, 6 px gap.
- `InventoryPanel` exposes bag/hotbar item management.
- `TopographicalMap` does async/step-based map jobs.
- `DebugPanel` is rate-limited and can disable expensive queries.
- `DevChatOverlay` blocks gameplay input while open.

Dev tooling:

- Dev chat bridge writes JSONL request/response files.
- Default request log: `requests.jsonl`.
- Default response log: `responses.jsonl`.
- `CRYSTALSTORM_DEV_ASSISTANT_DIR` can override location.
- Slash commands support status, preset, teleport, item grant, scenarios, and bug capture.
- `BugReporter` captures seed, player, chunk, crystal, perf, and errors.

Debug assumptions:

- Debug UI can use private-ish data and expensive group scans only when configured.
- Do not make debug paths authoritative.

## 24. Topographical Map

Map builder uses dictionary jobs.

Defaults:

- minimap size 160
- fullscreen size 512
- minimap radius 128 cells
- fullscreen half extent 512 cells
- sample stride 2
- rebuild interval 1.5 seconds in map config
- performance presets override runtime budgets

Algorithm:

- Begin job with internal resolution possibly divided by `internal_divisor`.
- Process pixels under pixel/time budget.
- Cache sampled columns.
- Paint terrain, water/channels, crystal overlay, towns, ruins, spawn markers.
- Supports incremental recenter by image shifting when movement is small.
- Repaints crystal overlay separately on idle interval.

Performance defaults in UI:

- map pixel budget 256
- map time budget 2500 us
- internal divisor 2
- crystal overlay interval 1 second

Implicit rule: map should read canonical world/overlay/crystal state, not visual nodes.

## 25. Save/Load

`SaveGameService` stores JSON under `user://saves/`.

Defaults:

- default slot 0
- slot count 3
- autosave enabled
- autosave interval 300 seconds
- autosave on enemy unlock
- autosave on town besieged
- save version 1

Snapshot includes:

- version
- timestamp
- world seed
- terrain edits
- channels
- features
- player
- crystal
- game phase/run state
- town defense
- entities
- crystal enemies
- serialized config

Load order:

1. Wait for feature/crystal bootstrap.
2. Warn if save version mismatches.
3. Warn if world seed mismatches.
4. Load terrain edits, channels, features.
5. Invalidate world column caches for edited cells.
6. Rebuild chunks and await rebuild idle.
7. Ensure crystal ready and import crystal.
8. Restore game manager.
9. Restore town defense.
10. Restore player.
11. Restore entities/enemies.
12. Refresh visuals.

Implicit rule: apply overlays before rebuilding chunks and before importing runtime systems that depend on terrain/chunks.

## 26. Performance Presets

Preset selection:

- `CRYSTALSTORM_SAFE_MODE=1` forces safe.
- `CRYSTALSTORM_PERF_PRESET=low|medium|high|safe`.
- Config can also provide performance resource.

SAFE:

- render distance 1
- max inflight chunks 2
- caves off
- crystal sim disabled
- minimap/fullscreen off
- entity spawning off
- feature billboards off
- combat visuals off

LOW:

- render distance 1
- crystal sim 8 Hz, skip 3 frames
- max crystal flow 140
- max new cells 4
- minimap off
- max entities 48
- vegetation scatter 0.35
- feature billboards 16/chunk
- combat visuals off

MEDIUM:

- render distance 2
- crystal sim 3 Hz, skip 2 frames
- max crystal flow 220
- max new cells 6
- minimap on, 96 px, stride 5
- max entities 64
- vegetation scatter 1.05
- voxel entity/vegetation visuals on
- combat labels/bursts 4 each

HIGH:

- render distance 3
- max chunks per frame 2
- crystal sim 18 Hz, skip 0
- max crystal flow 500
- max new cells 9
- minimap 128 px, stride 4
- max entities 96
- vegetation growth 8 Hz
- feature billboards 64/chunk
- combat labels/bursts 8 each

Implicit rule: any system work must preserve all presets and safe mode.

## 27. Shaders And Materials

Terrain:

- `shaders/ChunkView.gdshader`
- material `shaders/ChunkView.tres`
- atlas texture `assets/tiles/Cube.png`
- shader receives atlas grid and encoded per-instance custom data.
- nearest/pixel look is intentional.

Crystal:

- `shaders/crystal_procedural.gdshader`
- `CrystalManager` creates a material with generated amethyst texture if possible.
- Glow color roughly `(0.62, 0.22, 1.0)`.
- Glow strength 1.15.
- Iridescence 0.42.
- Roughness 0.14.
- Metallic 0.35.

Spawn markers:

- Standard unshaded material, pink/magenta by default.
- Texture marker visuals may override via registry.

## 28. Verification System

There are 97 `verify_*.gd` scripts in the current source inventory and a shell runner.

Main commands:

```bash
godot --headless -s scripts/run_all_verify.gd
bash scripts/run_all_verify.sh
bash scripts/run_smoke_gameplay.sh
bash scripts/run_display_session.sh
```

`run_all_verify.sh` is the durable suite list.

Some main-scene probes intentionally use abrupt exit and OK-marker matching because Godot teardown may abort after successful probes. Do not simplify this without understanding teardown history.

Major verification categories:

- stability/perf
- visual pipeline/boot/texture binding
- spawn markers/entity/vegetation visuals
- bootstrap deadlock
- chunk bootstrap/streaming/rebuild
- player jump/collision
- dig/build/terrain edit boundary
- ramps
- targeting/highlight
- main runtime health
- manual checklist corroboration
- combat/entity/crystal damage
- crystal spread/settling/routing
- full game loop
- map
- save/load
- smoke/display probes
- dev chat/tools/scenarios

Manual verification:

- `manual_verification.md` is human-only.
- Automated scripts must not mark human sign-off.

Smoke mouse rule:

- Some helpers warp mouse onto a target column.
- Tests for no-mouse or forward fallback must clear the mouse offscreen afterward.

## 29. Engineering Decisions Already Made

Important decisions encoded in code:

- Heightfield terrain over full 3D voxel arrays.
- MultiMesh terrain rendering over one node per voxel.
- Worker-thread chunk generation with main-thread scene application.
- Terrain worker snapshots to avoid registry races.
- Canonical overlays for terrain/features/channels.
- Visual readiness split into texture readiness and committed scene refresh.
- Custom voxel movement despite `CharacterBody3D`.
- Camera-facing targeting, not fixed world-facing targeting.
- Crystal as pressure-pool fluid, not simple cellular automata or water clone.
- Performance presets with loaded-chunk-only crystal simulation.
- Save canonical state, not rendered state.
- Use built-in registries for prototype content when config arrays are empty.
- Use `StringName` for stat/content IDs in hot paths.

## 30. Magic Numbers Index

World/terrain:

- chunk size 16
- default voxel scale 2.0
- default max height 20 voxels / 40 world units
- legacy height reference 158.0
- sea level 38.0
- playable half extent 1024
- border transition 240.0
- deep border 384.0
- border mountain floor 88.0
- border peak 138.0
- cave mesh depth 32
- rebuild edge band 2

Rendering:

- atlas 7x10
- atlas tile 48 px
- mesh buffer stride 16
- sprite pixel scale 0.026
- visual surface lift 0.12
- hotbar slot 52 px, gap 6 px

Player/camera:

- camera distance 100
- camera height offset 101
- zoom 8-140, step 2
- yaw step 90 degrees
- isometric yaw baseline 45 degrees
- camera rotation speed 480 deg/sec
- player slope limit 48 degrees

Combat:

- melee arc 70 degrees
- melee vertical tolerance 3.6
- ranged vertical tolerance 2.5
- max melee targets 4
- defense clamp max 0.9

Crystal/fluid:

- crystal min depth 0.04
- crystal max depth 12.0
- pressure flow 0.20
- max flow per cell 0.28
- max outflow ratio 0.12
- lateral spread 0.12
- uphill penalty 0.06
- downhill bonus 0.30
- power per volume 0.0025
- coverage loss ratio 0.72
- tier thresholds 0/20/60/140/300/600
- damping start 600, full 3000, min 0.35 by engine defaults

Content:

- inventory 8 hotbar + 24 bag
- max stack 99
- stone wall flow resistance 0.85
- wood wall flow resistance 0.55
- origin boss 500 HP
- ruin spawn 120 HP
- artifact node 80 HP
- relic slots 3

Save/map/perf:

- autosave 300 seconds
- map default minimap 160 px, fullscreen 512 px
- default map radius 128 cells
- map/fullscreen extent 512 cells
- performance chunk upload budget commonly 2500/3500/5000 us

## 31. Common Implicit Rules

- Production means `scenes/main.tscn`.
- Visual nodes are observers and derived views.
- Worker tasks cannot touch scene tree.
- Chunk result tokens must be checked before applying results.
- Chunk teardown must wait/clear workers to avoid headless aborts.
- Terrain edits near chunk borders need neighbor rebuilds.
- Player, entities, targeting, crystal, and map must agree on terrain queries.
- Dig/build must go through `TerrainEditor` for inventory/rebuild/save consistency.
- Spawn destruction is the win path; crystal coverage/contact/town failure can lose.
- SAFE mode must remain playable enough to boot/debug.
- Debug/dev tooling may inspect internals but must not become gameplay authority.
- New content must register through registries/config and save correctly.
- Documentation claims of "working" require dated human verification where manual feel/visuals matter.

## 32. Source Inventory Summary

Active production/runtime GDScript outside tests/addons is roughly 22.6k lines. Largest files and likely ownership:

- `crystal/crystal_manager.gd`: crystal orchestration, spawns, absorption, persistence, rendering.
- `chunks/chunk_manager.gd`: streaming, worker chunk gen, meshing, rebuilds, teardown.
- `systems/crystal_texture_generator.gd`: procedural texture and sprite generation.
- `world/InfiniteNoiseWorld.gd`: worldgen, biome, river, cave, tile/height queries.
- `player/action_targeting.gd`: targeting, ray/AABB logic, mouse/forward action resolution.
- `systems/game_visual_registry.gd`: texture cache, visual readiness, visual refresh.
- `player/player.gd`: custom voxel movement/player-owned systems.
- `systems/combat_visual_feedback.gd`: combat labels/bursts/spawn VFX.
- `fluids/voxel_fluid_engine.gd`: generic pressure/gravity fluid stepping.
- `ui/debug_panel.gd`: diagnostic HUD.
- `systems/topographical_map_builder.gd`: map jobs.
- `world/terrain_editor.gd`: terrain player actions.
- `weapons/weapon_controller.gd`: item action controller.
- `world/feature_visual_layer.gd`: feature visuals.
- `entities/world_entity.gd`: runtime entity behavior/visuals.

These are the highest-risk files for refactors and the best starting points for subsystem-specific reading.

## 33. Change Checklist

Before changing code:

1. Identify canonical state owner.
2. Identify derived views to refresh.
3. Identify save/load impact.
4. Identify performance preset impact.
5. Identify headless and display tests.
6. Check worker/main-thread boundary.
7. Check camera rotation/coordinate conversion if input or targeting changes.
8. Check crystal terrain query if terrain/features/buildings/channels change.
9. Check manual verification needs if visual feel/collision/readability changes.

After changing code:

- Run focused tests first.
- Run broader suite for cross-system changes.
- Do not edit `manual_verification.md` as a substitute for a human.
- Update this knowledge base when architectural assumptions change.
