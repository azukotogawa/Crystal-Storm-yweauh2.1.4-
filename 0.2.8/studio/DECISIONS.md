# Crystal Storm — Decision Ledger

One line per decision, keyed by a stable ID. Imported 2026-10-14 from Cole's ChatGPT-compiled ledger; the original text is kept as-is.

Format: `- D-NNN [topic] decision | status: S | date | verify: V | ref: `file:line` | sym: `symbol` | checked_on: YYYY-MM-DD | note: ...`

Status (design intent):
- `built`: recorded as implemented at some point.
- `decided`: explicit design or technical decision.
- `proposed`: idea or intended direction, not confirmed built.
- `rejected`: superseded or ruled out.
- `bug`: defect or failure recorded in project history.

Verify mark (only on `built` and `bug` entries, checked against `0.2.8/` code):
- `verified`: still in the code at `ref` (for a bug: the defect is still present).
- `stale`: the code contradicts it or it changed since (for a bug: fixed); `note` says how.
- `not-found`: not checkable in code (test runs, reports, hardware) or no matching code.

IDs never change or get reused. New decisions go at the end of their section with the next free ID. Open questions live in `studio/QUESTIONS.md`; the topic index is `studio/ATLAS.md`. Re-check refs with `bash .cursor/skills/verify-crystal-storm/ledger-verify.sh`.


## Crystal

- D-001 [crystal] Crystal is the defining world-changing force that progressively takes over the world | status: decided | 2026-08-31
- D-002 [crystal] Crystal spreads from crystal spawn points | status: rejected | 2026-07-15 | verify: verified | ref: `crystal/crystal_fluid_sim.gd:340` | sym: `tick_emitters` | checked_on: 2026-10-14 | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-003 [crystal] Crystal absorption can increase crystal power/tier | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_manager.gd:1682` | sym: `tier_from_power` | checked_on: 2026-10-14
- D-004 [crystal] Crystal absorption unlocks enemy types | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:55` | sym: `enemy_unlocked.emit` | checked_on: 2026-10-14
- D-005 [crystal] Farmland absorption unlocks `farm_bomber` | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:77` | sym: `farm_bomber` | checked_on: 2026-10-14
- D-006 [crystal] Tree absorption unlocks `crystal_stag` | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:78` | sym: `crystal_stag` | checked_on: 2026-10-14
- D-007 [crystal] Bush absorption unlocks `thornling` | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:79` | sym: `thornling` | checked_on: 2026-10-14
- D-008 [crystal] Grass absorption unlocks `crystal_mite` | status: built | 2026-07-15 | verify: stale | ref: `crystal/crystal_evolution.gd:80` | sym: `&"grass"` | checked_on: 2026-10-14 | note: crystal_mite is unlocked at run start (unlock_at_start=true; also forced in crystal_manager.gd:401), not by grass absorption
- D-009 [crystal] Animal absorption unlocks `corrupted_beast` | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:81` | sym: `corrupted_beast` | checked_on: 2026-10-14
- D-010 [crystal] Ruin absorption unlocks `shard_guard` | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:82` | sym: `shard_guard` | checked_on: 2026-10-14
- D-011 [crystal] Crystal can absorb plants, animals, ruins, and farmland | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_manager.gd:2425` | sym: `_absorption_source_for` | checked_on: 2026-10-14
- D-012 [crystal] Crystal pressure/coverage can cause a run loss when the world is overrun | status: built | 2026-07-15 | verify: verified | ref: `game/game_manager.gd:125` | sym: `_check_crystal_overrun` | checked_on: 2026-10-14
- D-013 [crystal] Crystal beneath the player during assault can damage the player | status: built | 2026-07-15 | verify: verified | ref: `game/game_manager.gd:159` | sym: `_apply_crystal_damage` | checked_on: 2026-10-14
- D-014 [crystal] Crystal Ward slows crystal flow to 0.72 of its normal rate | status: built | 2026-07-17 | verify: verified | ref: `relics/relic_registry.gd:51` | sym: `crystal_flow_mult = 0.72` | checked_on: 2026-10-14
- D-015 [crystal] Crystal flow should be affected by terrain features and player-made terrain | status: decided | 2026-07-17
- D-016 [crystal] Water should reduce crystal conductivity; crystal may still crawl slowly through wet cells | status: built | 2026-08-15 | verify: verified | ref: `crystal/crystal_terrain_query.gd:257` | sym: `wet` | checked_on: 2026-10-14
- D-017 [crystal] Crystal simulation should operate on loaded chunks with border masking and frame-budgeted dispatch | status: built | 2026-08-15 | verify: verified | ref: `crystal/crystal_sim_snapshot.gd:10` | sym: `loaded_chunks` | checked_on: 2026-10-14 | note: budget in crystal_simulation.gd:24; border mask via WorldBorder.allows_crystal at crystal_sim_snapshot.gd:29
- D-018 [crystal] Crystal simulation architecture is split into manager façade, immutable simulation snapshot, scene-tree-independent simulation, fluid simulation, events, and presentation | status: built | 2026-08-15 | verify: verified | ref: `crystal/crystal_simulation.gd:1` | sym: `class_name CrystalSimulation` | checked_on: 2026-10-14 | note: files: crystal_manager, crystal_sim_snapshot, crystal_simulation (RefCounted), crystal_fluid_sim, crystal_sim_events, crystal_presentation
- D-019 [crystal] Crystal presentation uses chunk MultiMeshes | status: built | 2026-08-15 | verify: verified | ref: `crystal/crystal_chunk_layer.gd:49` | sym: `MultiMeshInstance3D` | checked_on: 2026-10-14
- D-020 [crystal] Crystal state supports save/import | status: built | 2026-08-15 | verify: verified | ref: `crystal/crystal_manager.gd:2500` | sym: `func import_state` | checked_on: 2026-10-14 | note: export_state at :2467
- D-021 [crystal] Crystal should grow across exposed surfaces and enter cavities | status: proposed | 2026-08-31
- D-022 [crystal] Crystal should grow around obstacles and adapt to player-built structures | status: proposed | 2026-08-31
- D-023 [crystal] Crystal should transform susceptible terrain into crystalline terrain | status: proposed | 2026-08-31
- D-024 [crystal] Crystal may bridge small gaps, climb selected materials, encapsulate terrain, branch, split, reconnect, or accumulate into thicker structures | status: proposed | 2026-10-14
- D-025 [crystal] Crystal should not be treated merely as purple water; propagation modes should depend on material and environment | status: decided | 2026-10-14
- D-026 [crystal] Crystal growth should be a readable simulation with understandable causes and consequences | status: decided | 2026-10-14
- D-027 [crystal] Prioritize systemic crystal interactions over isolated visual effects | status: decided | 2026-10-14
- D-028 [crystal] Crystal enemy escalation becomes mostly numerical after the finite absorption-unlock list | status: bug | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:75` | sym: `_builtin_unlocks` | checked_on: 2026-10-14 | note: unlock table is still six fixed rows; only per-spawn elites/warden add variety (crystal_enemy_spawner.gd:397)
- D-029 [crystal] Open question: which propagation modes are actually required for the first systemic upgrade, and which remain future ideas? | status: proposed

## Voxels

- D-030 [voxels] The project moved from a Python/2.5D approach to a fully 3D Godot voxel engine using Vector3 coordinates | status: decided | 2026-04
- D-031 [voxels] The world should provide Minecraft-like editable 3D terrain while retaining Crystal Storm's distinct crystal-pressure gameplay | status: decided | 2026-08-31
- D-032 [voxels] The world is chunked rather than represented as one monolithic mesh | status: built | 2026-04 | verify: verified | ref: `chunks/chunk_manager.gd:918` | sym: `_greedy_mesh_plane_region` | checked_on: 2026-10-14
- D-033 [voxels] Greedy meshing groups faces to reduce render work | status: built | 2026-04 | verify: verified | ref: `chunks/chunk_manager.gd:1927` | sym: `func _greedy_mesh_plane_region` | checked_on: 2026-10-14
- D-034 [voxels] Face culling should render only visible faces | status: built | 2026-04 | verify: verified | ref: `chunks/chunk_manager.gd:1502` | sym: `func _flank_exposed` | checked_on: 2026-10-14 | note: side faces emitted only where the neighbour is lower
- D-035 [voxels] Chunk-level texture batching is used | status: built | 2026-04 | verify: verified | ref: `shaders/ChunkView.gdshader:14` | sym: `texture_atlas` | checked_on: 2026-10-14 | note: one atlas sampler per chunk material
- D-036 [voxels] Atlas shader supports separate cube-face textures for top, side, and bottom | status: built | 2026-04 | verify: verified | ref: `helpers/voxel_types.gd:80` | sym: `get_atlas_coord_for_face` | checked_on: 2026-10-14
- D-037 [voxels] Terrain textures are biome-dependent | status: built | 2026-04 | verify: verified | ref: `helpers/voxel_types.gd:288` | sym: `biome_to_voxel_id` | checked_on: 2026-10-14
- D-038 [voxels] Smooth lighting uses ambient and face shading | status: built | 2026-04 | verify: verified | ref: `helpers/chunk_surface_mesh_builder.gd:804` | sym: `_face_shade` | checked_on: 2026-10-14 | note: vertex AO in helpers/terrain_vertex_ao.gd
- D-039 [voxels] Macro terrain is a dense per-chunk surface/tile/flags grid | status: rejected | 2026-08-15 | verify: verified | ref: `helpers/macro_layer_grid.gd:18` | sym: `_surface_y` | checked_on: 2026-10-14 | superseded: 2026-10-14 by D-222, D-223, D-224 (was: built)
- D-040 [voxels] Sparse micro bricks are used for selected digging, building, and cliff details | status: rejected | 2026-08-15 | verify: verified | ref: `helpers/micro_layer_grid.gd:27` | sym: `_bricks` | checked_on: 2026-10-14 | superseded: 2026-10-14 by D-222, D-223, D-224 (was: built)
- D-041 [voxels] Micro voxels are not a uniformly finer voxel volume; they are sparse detail/meshing isolation over macro terrain | status: rejected | 2026-08-15 | superseded: 2026-10-14 by D-222, D-223, D-224 (was: decided)
- D-042 [voxels] Macro voxels should be approximately twice the size of the earlier normal voxel scale to reduce the amount of terrain represented | status: rejected | 2026-07-08 | superseded: 2026-10-14 by D-222, D-223, D-224 (was: decided)
- D-043 [voxels] Micro voxels should be used selectively for player digging and specific terrain features | status: rejected | 2026-07-08 | superseded: 2026-10-14 by D-222, D-223, D-224 (was: decided)
- D-044 [voxels] A proposal described each macro voxel as X times the size of a micro voxel; the exact final ratio is not established in this ledger | status: rejected | 2026-07-08 | superseded: 2026-10-14 by D-222, D-223, D-224 (was: proposed)
- D-045 [voxels] Terrain edits should rebuild affected chunks and neighboring geometry | status: built | 2026-08-15 | verify: verified | ref: `helpers/terrain_dirty_scope.gd:143` | sym: `_add_neighbor_band` | checked_on: 2026-10-14
- D-046 [voxels] Worker pipeline stages are snapshot, column, mesh, buffer, and apply | status: built | 2026-08-15 | verify: verified | ref: `chunks/chunk_pipeline.gd:5` | sym: `STAGE_SNAPSHOT` | checked_on: 2026-10-14
- D-047 [voxels] Worker jobs use frozen overlay stamps and stale jobs are dropped | status: built | 2026-08-15 | verify: verified | ref: `chunks/chunk_manager.gd:3317` | sym: `is_mesh_job_stale` | checked_on: 2026-10-14 | note: overlay stamp captured at chunk_data.gd:203
- D-048 [voxels] Collision is not derived solely from chunk mesh physics; floor probes use live world state and ramp information | status: built | 2026-08-15 | verify: verified | ref: `player/voxel_floor_probe.gd:25` | sym: `_ramp_frame` | checked_on: 2026-10-14
- D-049 [voxels] The player should be able to dig, remove, place, fill, raise/lower terrain, and form channels | status: decided | 2026-08-15
- D-050 [voxels] The player should be able to create walls, tunnels, ramps, bridges, channels, and defensive layouts | status: decided | 2026-08-31
- D-051 [voxels] Ramp eligibility must be determined by actual local terrain topology and support | status: decided | 2026-08-21
- D-052 [voxels] Corner ramps require genuine support, including the required diagonal plateau support | status: decided | 2026-08-21
- D-053 [voxels] Cardinal ramps must not create invalid face-to-face/back-to-side contacts | status: decided | 2026-08-21
- D-054 [voxels] Forced feature-backed ramps must be revalidated against current worker-snapshot topology | status: built | 2026-10 | verify: verified | ref: `chunks/chunk_manager.gd:1304` | sym: `_apply_forced_ramps` | checked_on: 2026-10-14
- D-055 [voxels] Forced ramp features remain registered as placement intent even when current topology suppresses their rendered ramp | status: built | 2026-10 | verify: verified | ref: `chunks/chunk_data.gd:250` | sym: `_worker_force_ramp` | checked_on: 2026-10-14
- D-056 [voxels] Adjacent parallel cardinal ramps previously produced an unwanted full square seam face | status: bug | 2026-10 | verify: stale | ref: `chunks/chunk_manager.gd:2031` | sym: `parallel far cardinal` | checked_on: 2026-10-14 | note: fixed: parallel far cardinal seam is left unfilled
- D-057 [voxels] Some cardinal ramps previously lost neighboring full-voxel faces, especially at chunk borders | status: bug | 2026-10 | verify: stale | ref: `chunks/chunk_manager.gd:2035` | sym: `_halo_landing_dir` | checked_on: 2026-10-14 | note: fixed: border fill uses halo landing direction
- D-058 [voxels] A mesh-plan cache hit previously failed to reconstruct `ramp_map` and could carry stale ramp metadata | status: bug | 2026-10 | verify: stale | ref: `chunks/chunk_pipeline.gd:137` | sym: `_rehydrate_ramp_map_from_quads` | checked_on: 2026-10-14 | note: fixed: cache hits rehydrate ramp_map
- D-059 [voxels] Mesh plan schema was bumped to version 3 and cached ramp state was rehydrated from cached ramp quads | status: built | 2026-10 | verify: verified | ref: `world/mesh_plan_cache.gd:4` | sym: `PLAN_VERSION: int = 3` | checked_on: 2026-10-14
- D-060 [voxels] A cross-border anti-parallel cardinal-ramp case required halo ramp-direction reconstruction | status: built | 2026-10 | verify: verified | ref: `chunks/chunk_manager.gd:2068` | sym: `func _halo_landing_dir` | checked_on: 2026-10-14
- D-061 [voxels] The ramp/mesh verification family was reported green after the ownership and cross-border fixes | status: built | 2026-10 | verify: not-found | ref: `scripts/verify_ramp_corner.gd:1` | checked_on: 2026-10-14 | note: run result; scripts exist but green status is not checkable in code
- D-062 [voxels] The initial camera-visible ramp state must be correct before the player breaks a block | status: decided | 2026-10
- D-063 [voxels] Breaking a block must not be required to make missing ramp faces appear | status: decided | 2026-10
- D-064 [voxels] Sword input must never accidentally trigger terrain digging/removal | status: decided | 2026-08-21
- D-065 [voxels] Terrain interaction range should be 8 voxel columns | status: decided | 2026-08-21
- D-066 [voxels] Weapon combat range should remain separate from terrain interaction range | status: decided | 2026-08-21
- D-067 [voxels] Open question: should the final world remain primarily a surface-heightfield with sparse micro bricks, or evolve toward more complete volumetric voxel occupancy? | status: rejected | superseded: 2026-10-14 by D-222, D-223, D-224 (was: proposed)
- D-068 [voxels] Open question: what exact macro-to-micro size ratio should be authoritative? | status: rejected | superseded: 2026-10-14 by D-222, D-223, D-224 (was: proposed)

## Water

- D-069 [water] Natural rivers and oceans are represented through terrain atlas tiles | status: built | 2026-08-15 | verify: verified | ref: `helpers/voxel_types.gd:42` | sym: `RIVER := 37` | checked_on: 2026-10-14
- D-070 [water] Water has a VoxelFluidService and VoxelFluidEngine with gravity/channel behavior | status: built | 2026-08-15 | verify: verified | ref: `fluids/voxel_fluid_engine.gd:202` | sym: `_tick_flow_gravity` | checked_on: 2026-10-14 | note: service: fluids/voxel_fluid_service.gd:1
- D-071 [water] Water state is persisted through ChannelRegistry fields such as water level and flow direction | status: built | 2026-08-15 | verify: verified | ref: `world/channel_registry.gd:29` | sym: `get_water_level` | checked_on: 2026-10-14
- D-072 [water] Digging or channel edits can trigger local fluid recomputation | status: built | 2026-08-15 | verify: verified | ref: `world/terrain_editor.gd:936` | sym: `recompute_region_now` | checked_on: 2026-10-14
- D-073 [water] Water should flow into player-made cavities rather than float above the terrain | status: decided | 2026-10
- D-074 [water] Digging a block beside river/channel/wet fluid should create a real water block in the dug cell, not only an invisible overlay | status: decided | 2026-10
- D-075 [water] A successful dig beside water stamps a WATER/RIVER tile, registers a channel, and remeshes | status: built | 2026-10 | verify: stale | ref: `world/terrain_editor.gd:839` | sym: `_replace_cell_with_water_block` | checked_on: 2026-10-14 | note: stamps WATER/RIVER override and a flood_from_dig feature, but does not register a ChannelRegistry channel
- D-076 [water] Filling should clear a stamped flood block | status: built | 2026-10 | verify: verified | ref: `world/terrain_editor.gd:863` | sym: `_clear_flood_water_block` | checked_on: 2026-10-14
- D-077 [water] Dry digs with no water neighbor should remain dry | status: built | 2026-10 | verify: verified | ref: `world/terrain_editor.gd:930` | sym: `_dug_below_adjacent_water` | checked_on: 2026-10-14
- D-078 [water] Water should occupy the actual available vertical interval and cavity rather than being represented only as a full-voxel lid at the source waterline | status: decided | 2026-10
- D-079 [water] A previous implementation made water flush with the terrain but could change untouched blocks to water when chunks updated | status: bug | 2026-10 | verify: not-found | checked_on: 2026-10-14 | note: runtime regression; no code marker (dig floods are now explicit flood_from_dig stamps, terrain_editor.gd:857)
- D-080 [water] A previous water regression test encoded the wrong expectation by requiring a dug indentation's water lid to remain at the source waterline | status: bug | 2026-10 | verify: not-found | checked_on: 2026-10-14 | note: no water-lid test with a source-waterline expectation found in scripts/
- D-081 [water] A later project update reported “waters fixed” after further work | status: built | 2026-10 | verify: not-found | checked_on: 2026-10-14 | note: project report; nothing to check in code
- D-082 [water] Water should interact with vegetation growth | status: built | 2026-07-15 | verify: verified | ref: `world/vegetation_growth_manager.gd:190` | sym: `growth_near_water_bonus` | checked_on: 2026-10-14
- D-083 [water] Water boosts plant growth | status: built | 2026-07-15 | verify: verified | ref: `world/vegetation_growth_manager.gd:199` | sym: `growth_near_water_bonus` | checked_on: 2026-10-14
- D-084 [water] Water state/channels influence crystal terrain-flow logic | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_terrain_query.gd:7` | sym: `_ChannelRegistry` | checked_on: 2026-10-14
- D-085 [water] Wet cells reduce crystal conductivity but do not necessarily stop crystal completely | status: built | 2026-08-15 | verify: verified | ref: `crystal/crystal_terrain_query.gd:259` | sym: `lerpf(1.25, 0.35, wet)` | checked_on: 2026-10-14
- D-086 [water] The `channel_fluid_changed` signal previously had no listeners and simulated water leaving painted river/channel tiles lacked visible fluid geometry | status: bug | 2026-08-15 | verify: verified | ref: `fluids/voxel_fluid_service.gd:15` | sym: `channel_fluid_changed` | checked_on: 2026-10-14 | note: signal still has no .connect anywhere; visible-geometry half not re-checked (helpers/water_surface.gd exists)
- D-087 [water] Lava, poison, and oil existed as stub fluid definitions, not complete systems | status: built | 2026-08-15 | verify: verified | ref: `helpers/fluid_registry.gd:15` | sym: `lava` | checked_on: 2026-10-14
- D-088 [water] Open question: does the current implementation render free-flowing water as actual volume, or do some areas still use terrain atlas tiles only? | status: proposed

## Combat

- D-089 [combat] Combat includes melee and ranged attacks | status: built | 2026-07-15 | verify: verified | ref: `weapons/weapon_controller.gd:353` | sym: `WeaponKind.MELEE` | checked_on: 2026-10-14
- D-090 [combat] Sword and bow are part of the practical starting item set | status: built | 2026-07-15 | verify: verified | ref: `player/player.gd:847` | sym: `wooden_sword` | checked_on: 2026-10-14
- D-091 [combat] The player can attack crystal spawn points | status: rejected | 2026-07-15 | verify: verified | ref: `weapons/weapon_controller.gd:429` | sym: `damage_spawn_at_world` | checked_on: 2026-10-14 | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-092 [combat] Destroying non-boss spawn points weakens crystal emission | status: rejected | 2026-07-15 | verify: verified | ref: `crystal/spawn_point_controller.gd:158` | sym: `weaken_factor` | checked_on: 2026-10-14 | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-093 [combat] The origin boss remains sealed until all non-boss/secondary spawn points are destroyed | status: rejected | 2026-07-15 | verify: verified | ref: `crystal/spawn_point_controller.gd:138` | sym: `Origin boss sealed` | checked_on: 2026-10-14 | note: origin warden must also be defeated (:139) | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-094 [combat] Destroying all crystal spawn points is the hard victory condition | status: rejected | 2026-07-15 | verify: stale | ref: `game/game_manager.gd:190` | sym: `notify_boss_defeated` | checked_on: 2026-10-14 | note: killing the origin warden is now a second victory path; all-spawns victory still at :180 | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-095 [combat] Player death is a loss condition | status: built | 2026-07-15 | verify: verified | ref: `game/game_manager.gd:205` | sym: `_on_player_died` | checked_on: 2026-10-14
- D-096 [combat] Combat should be responsive and readable and should feel like an action game rather than a purely strategic simulation | status: decided | 2026-08
- D-097 [combat] Effects and game-feel milestone M5 was reported merged | status: built | 2026-10-14 | verify: verified | ref: `systems/juice.gd:23` | sym: `set_preset` | checked_on: 2026-10-14 | note: merge itself not checkable; effects code present (juice.gd, vfx_pool.gd, hit_markers.gd)
- D-098 [combat] Combat milestone M3 was reported merged | status: built | 2026-10-14 | verify: verified | ref: `weapons/weapon_controller.gd:346` | sym: `weapon_kind` | checked_on: 2026-10-14 | note: merge itself not checkable; combat code present
- D-099 [combat] Sword LMB was routed through generic terrain removal/dig logic before weapon classification | status: bug | 2026-08 | verify: stale | ref: `weapons/weapon_controller.gd:110` | sym: `LMB is attack only` | checked_on: 2026-10-14 | note: fixed: combat weapons never dig
- D-100 [combat] Input dispatch should be mutually exclusive: weapons use combat, dig tools use terrain editing, and explicit build/remove actions use terrain structures | status: decided | 2026-08-21
- D-101 [combat] Killing enemies primarily removed threats and did not provide a clear reward/progression loop in the July gameplay audit | status: bug | 2026-07-15 | verify: stale | ref: `helpers/combat_rewards.gd:5` | sym: `grant_player_kill` | checked_on: 2026-10-14 | note: kills now grant loot and a toast
- D-102 [combat] Bow aim and use animations were still listed as failing in the 0.3.0 windowed verification | status: bug | 2026-10-14 | verify: not-found | checked_on: 2026-10-14 | note: windowed test result; not checkable in code
- D-103 [combat] Open question: should combat kills grant resources, relics, upgrades, information, or phase advantage? | status: proposed
- D-104 [combat] Open question: what are the origin boss's phases, signature mechanics, and arena changes? | status: proposed

## Enemies

- D-105 [enemies] Crystal enemies spawn as crystal spreads and absorption unlocks enemy types | status: built | 2026-07-15 | verify: verified | ref: `entities/crystal_enemy_spawner.gd:100` | sym: `pick_weighted` | checked_on: 2026-10-14
- D-106 [enemies] Crystal mite is associated with grass absorption | status: built | 2026-07-15 | verify: stale | ref: `crystal/crystal_evolution.gd:80` | sym: `&"grass"` | checked_on: 2026-10-14 | note: crystal_mite unlocks at start, not via grass
- D-107 [enemies] Farm bomber is associated with farmland absorption | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:77` | sym: `farm_bomber` | checked_on: 2026-10-14
- D-108 [enemies] Crystal stag is associated with tree absorption | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:78` | sym: `crystal_stag` | checked_on: 2026-10-14
- D-109 [enemies] Thornling is associated with bush absorption | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:79` | sym: `thornling` | checked_on: 2026-10-14
- D-110 [enemies] Corrupted beast is associated with animal absorption | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:81` | sym: `corrupted_beast` | checked_on: 2026-10-14
- D-111 [enemies] Shard guard is associated with ruin absorption | status: built | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:82` | sym: `shard_guard` | checked_on: 2026-10-14
- D-112 [enemies] Enemies spawn near the player and/or crystal according to the current spawner logic | status: built | 2026-07-15 | verify: verified | ref: `entities/crystal_enemy_spawner.gd:15` | sym: `spawn_near_player_min` | checked_on: 2026-10-14
- D-113 [enemies] Passive animals flee from the player and crystal | status: built | 2026-07-15 | verify: verified | ref: `entities/entity_brain.gd:11` | sym: `FLEE_CRYSTAL` | checked_on: 2026-10-14
- D-114 [enemies] Animals can feed crystal progression when absorbed | status: built | 2026-07-15 | verify: verified | ref: `entities/world_entity.gd:518` | sym: `record_absorption` | checked_on: 2026-10-14
- D-115 [enemies] Towns can request militia defenders when threatened | status: built | 2026-07-15 | verify: verified | ref: `world/town_defense_manager.gd:10` | sym: `militia_requested` | checked_on: 2026-10-14
- D-116 [enemies] Enemy escalation should eventually become a coherent director with composition pacing, objectives, and clear transitions rather than only increasing counts | status: proposed | 2026-07-15
- D-117 [enemies] The enemy ecosystem was judged thin after the finite absorption-unlock table was exhausted | status: bug | 2026-07-15 | verify: verified | ref: `crystal/crystal_evolution.gd:75` | sym: `_builtin_unlocks` | checked_on: 2026-10-14 | note: still a fixed six-row table
- D-118 [enemies] Creature animations were among the failures in 0.3.0 windowed verification | status: bug | 2026-10-14 | verify: not-found | checked_on: 2026-10-14 | note: windowed test result; not checkable in code
- D-119 [enemies] Open question: should animals become huntable/tameable/resource-producing, or remain primarily ecology and crystal fuel? | status: proposed

## World

- D-120 [world] The world is finite rather than infinite | status: decided | 2026-04
- D-121 [world] Ocean and mountain edges should bound the playable world | status: decided | 2026-07-17
- D-122 [world] Finite scope supports escalating crystal pressure and a meaningful end condition | status: decided | 2026-04
- D-123 [world] Terrain generation should be deterministic for a given seed | status: decided | 2026-04
- D-124 [world] Structures, towns, items, mobs, trees, and other content may use additional seeded/random placement | status: decided | 2026-04
- D-125 [world] Terrain should contain ravines and cracks | status: decided | 2026-04
- D-126 [world] Terrain should contain canyons with rivers | status: decided | 2026-04
- D-127 [world] Terrain should contain valleys with lakes | status: decided | 2026-04
- D-128 [world] Terrain should contain basins | status: decided | 2026-04
- D-129 [world] Terrain should contain plateaus | status: decided | 2026-04
- D-130 [world] Caves should be authored/baked as distinct set pieces or dungeon-like spaces rather than being assumed to emerge from the surface terrain generator | status: decided | 2026-04
- D-131 [world] Biomes should have distinct terrain/height traits | status: decided | 2026-04
- D-132 [world] Biomes should create gameplay variety rather than simply rank as stronger/weaker versions of each other | status: decided | 2026-07-17
- D-133 [world] Biomes should have similar average height while terrain features make them distinct | status: decided | 2026-07-17
- D-134 [world] A small number of temperature-themed biomes was preferred over a huge biome catalog | status: decided | 2026-07-17
- D-135 [world] Terrain features should influence crystal behavior so some variety emerges naturally from systems | status: decided | 2026-07-17
- D-136 [world] The world has a minimap and biome/debug status display | status: built | 2026-10-14 | verify: verified | ref: `ui/topographical_map.gd:12` | sym: `_minimap_rect` | checked_on: 2026-10-14 | note: biome HUD: ui/game_overlay.gd:29
- D-137 [world] Terrain generation includes rivers, shoreline, vegetation, ruins, and other features | status: built | 2026-10-14 | verify: verified | ref: `world/world_features.gd:158` | sym: `RuinManager` | checked_on: 2026-10-14 | note: rivers: world/river_drainage.gd; vegetation: world/vegetation_manager.gd
- D-138 [world] A finite world should support a longer maze/preparation phase and shorter assault endgame | status: decided | 2026-07-17
- D-139 [world] The earlier concept included an approximately 10-minute endurance phase through a heavily corrupted map before the boss | status: proposed | 2026-04
- D-140 [world] Infinite world generation was considered but rejected because it conflicts with finite-map crystal pressure and a clear victory/loss condition | status: rejected | 2026-04
- D-141 [world] Open question: what are the final world dimensions, number of biomes, and exact terrain-feature frequencies? | status: proposed

## Towns

- D-142 [towns] The design includes two small towns and one large port | status: decided | 2026-04
- D-143 [towns] Towns should resist the crystal but eventually be vulnerable/overwhelmed if the player fails to intervene | status: decided | 2026-04
- D-144 [towns] Town state progresses through safe, alert, besieged, and fallen | status: built | 2026-07-15 | verify: verified | ref: `world/town_defense_manager.gd:6` | sym: `enum TownState` | checked_on: 2026-10-14
- D-145 [towns] Towns can request militia when alert or besieged | status: built | 2026-07-15 | verify: verified | ref: `world/town_defense_manager.gd:172` | sym: `_request_militia` | checked_on: 2026-10-14
- D-146 [towns] A fallen town causes a loss | status: built | 2026-07-15 | verify: stale | ref: `game/game_manager.gd:141` | sym: `_on_town_fallen` | checked_on: 2026-10-14 | note: a fallen town now gives the crystal a power surge and dismisses defenders; it no longer ends the run
- D-147 [towns] Towns are strategic stakes in the world rather than only decorative settlements | status: decided | 2026-04
- D-148 [towns] Towns did not provide trade, quests, rewards, repairs, or progression in the July gameplay audit | status: bug | 2026-07-15 | verify: verified | ref: `world/town_defense_manager.gd:6` | sym: `enum TownState` | checked_on: 2026-10-14 | note: still no trade/quest/repair code in town_manager.gd or town_defense_manager.gd
- D-149 [towns] Open question: should town survival grant rewards or unlock support, trading, crafting, repairs, or other services? | status: proposed
- D-150 [towns] Open question: are the two-small-town/one-large-port counts still fixed, or may map generation vary them? | status: proposed

## Progression

- D-151 [progression] The run's central win condition is destroying all crystal spawn points, including the origin boss | status: rejected | 2026-07-15 | verify: stale | ref: `game/game_manager.gd:190` | sym: `notify_boss_defeated` | checked_on: 2026-10-14 | note: origin warden kill is now also a win; all-spawns path at :180 | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-152 [progression] Non-boss spawns must be destroyed before the origin boss becomes vulnerable | status: rejected | 2026-07-15 | verify: verified | ref: `crystal/spawn_point_controller.gd:77` | sym: `boss_sealed` | checked_on: 2026-10-14 | superseded: 2026-10-14 by D-225, D-226, D-227 (was: built)
- D-153 [progression] Excessive crystal coverage causes loss | status: built | 2026-07-15 | verify: verified | ref: `game/game_manager.gd:128` | sym: `max_crystal_coverage` | checked_on: 2026-10-14
- D-154 [progression] Player death causes loss | status: built | 2026-07-15 | verify: verified | ref: `game/game_manager.gd:207` | sym: `You died.` | checked_on: 2026-10-14
- D-155 [progression] Town loss causes loss | status: built | 2026-07-15 | verify: stale | ref: `game/game_manager.gd:141` | sym: `_on_town_fallen` | checked_on: 2026-10-14 | note: town loss is a penalty, not a run loss
- D-156 [progression] The game uses roguelike/procedural run elements | status: decided | 2026-04
- D-157 [progression] Save/load may be used during runs | status: decided | 2026-04
- D-158 [progression] The July design notes explicitly said no meta-progression | status: decided | 2026-07-17
- D-159 [progression] The July gameplay audit found no connected meta-progression, checkpoint, or difficulty-unlock system | status: built | 2026-07-15 | verify: verified | ref: `systems/save_game_service.gd:22` | sym: `STAGE_CHECKPOINT` | checked_on: 2026-10-14 | note: still no meta-progression or difficulty unlocks; only a session save checkpoint
- D-160 [progression] Relic definitions and stat modifiers exist | status: built | 2026-07-15 | verify: verified | ref: `relics/relic_registry.gd:45` | sym: `_make_crystal_ward` | checked_on: 2026-10-14
- D-161 [progression] Relic acquisition/earn-choose-equip loop was missing in the July audit | status: bug | 2026-07-15 | verify: stale | ref: `crystal/crystal_manager.gd:427` | sym: `_on_enemy_unlocked_grant_relic` | checked_on: 2026-10-14 | note: relics now granted on enemy unlocks and ruin discovery (living_world_director.gd:259) with a replace-choice panel
- D-162 [progression] The starting practical item set included sword, pick, bow, wood, stone, and herb | status: built | 2026-07-15 | verify: stale | ref: `player/player.gd:846` | sym: `_give_starting_loadout` | checked_on: 2026-10-14 | note: loadout now also has spear, crystal hammer, sling, crystal bombs, stone plate and leather armor
- D-163 [progression] No connected tool/weapon tier ladder was found in the July audit | status: bug | 2026-07-15 | verify: verified | ref: `helpers/item_types.gd:14` | sym: `wooden_sword` | checked_on: 2026-10-14 | note: still only wooden_sword/stone_pick, no tier ladder
- D-164 [progression] Herb existed as a gathered item but had no clear consume/heal/buff loop | status: bug | 2026-07-15 | verify: stale | ref: `weapons/weapon_controller.gd:289` | sym: `consume_item("herb"` | checked_on: 2026-10-14 | note: herb is now consumed on RMB to heal
- D-165 [progression] Combat kills lacked a clear reward loop | status: bug | 2026-07-15 | verify: stale | ref: `helpers/combat_rewards.gd:5` | sym: `grant_player_kill` | checked_on: 2026-10-14 | note: kills grant loot
- D-166 [progression] Plant maturity lacked a clear player-facing follow-up beyond possible crystal absorption | status: bug | 2026-07-15 | verify: verified | ref: `world/vegetation_growth_manager.gd:141` | sym: `mature` | checked_on: 2026-10-14 | note: maturity only changes crystal denial flow; no harvest or player reward
- D-167 [progression] Ruins primarily fed crystal/spawn systems and lacked a player exploration reward loop | status: bug | 2026-07-15 | verify: stale | ref: `world/living_world_director.gd:258` | sym: `_try_grant_ruin_relic` | checked_on: 2026-10-14 | note: ruin discovery now grants a relic and loot
- D-168 [progression] The phase cycle lacked a clear prepare → assault → survive → reward → rebuild cadence | status: bug | 2026-07-15 | verify: verified | ref: `game/game_manager.gd:8` | sym: `enum Phase` | checked_on: 2026-10-14 | note: still only MAZE / ASSAULT / VICTORY
- D-169 [progression] Open question: does the no-meta-progression decision remain authoritative, or has it been reconsidered? | status: proposed
- D-170 [progression] Open question: should a successful run provide any persistent unlocks, or should all power reset between runs? | status: proposed

## Art

- D-171 [art] The visual direction is stylized voxel terrain with readable surfaces and clear silhouettes | status: decided | 2026-04
- D-172 [art] The current visual reference shows an isometric view of grassy terrain, soil cuts, water, ruins/structures, vegetation, and crystal features | status: decided | 2026-08-31
- D-173 [art] The target is a convincing 3D voxel world with editable terrain, in the spirit of Minecraft but with Crystal Storm's own identity | status: decided | 2026-08-31
- D-174 [art] Crystal visuals should make spread, danger, boundaries, and state legible | status: decided | 2026-08-31
- D-175 [art] Terrain materials should eventually move beyond flat/noisy placeholders toward a cohesive stylized/pixel-art voxel look | status: proposed | 2026-10-14
- D-176 [art] Placeholder art should be replaced incrementally rather than through a wholesale replacement before gameplay is coherent | status: decided | 2026-10-14
- D-177 [art] Art milestone M4 was waiting for the user's style sign-off in the 2026-10-14 progress note | status: proposed | 2026-10-14
- D-178 [art] Smooth camera trailing/smoothing was implemented | status: built | 2026-04 | verify: verified | ref: `player/camera.gd:14` | sym: `use_smoothing` | checked_on: 2026-10-14
- D-179 [art] The camera was later changed to smooth behavior and the user specifically noted that it should be preserved during visual checks | status: decided | 2026-10
- D-180 [art] Open question: what final crystal geometry, color palette, lighting, and texture style should be signed off for the art pass? | status: proposed

## UI

- D-181 [UI] A minimap is present | status: built | 2026-10-14 | verify: verified | ref: `ui/topographical_map.gd:12` | sym: `_minimap_rect` | checked_on: 2026-10-14
- D-182 [UI] The HUD communicates assault/phase, crystal state, artifact/spawn context, biome, and controls | status: built | 2026-10-14 | verify: verified | ref: `ui/game_overlay.gd:18` | sym: `_phase_label` | checked_on: 2026-10-14
- D-183 [UI] The hotbar and inventory communicate tools/items and quantities | status: built | 2026-10-14 | verify: verified | ref: `ui/hotbar.gd:166` | sym: `slot.count` | checked_on: 2026-10-14
- D-184 [UI] Menus, tooltips, settings, and accessibility milestone M6 were reported merged | status: built | 2026-10-14 | verify: verified | ref: `ui/settings_menu.gd:109` | sym: `Accessibility` | checked_on: 2026-10-14 | note: merge itself not checkable; tooltips in ui/tooltip_panel.gd
- D-185 [UI] Debug display includes player/chunk/tile information and performance counters | status: built | 2026-04 | verify: verified | ref: `ui/debug_panel.gd:126` | sym: `get_frames_per_second` | checked_on: 2026-10-14
- D-186 [UI] UI should clearly communicate the crystal threat and the current gameplay phase | status: decided | 2026-10-14
- D-187 [UI] Open question: which debug overlays should be available in normal play versus developer-only mode? | status: proposed

## Tech

- D-188 [tech] Engine is Godot 4; the October 2026 repository inspection recorded Godot 4.7 | status: built | 2026-08-15 | verify: verified | ref: `project.godot:16` | sym: `4.7` | checked_on: 2026-10-14
- D-189 [tech] Rendering uses Forward+ and Jolt was configured in the recorded project inspection | status: built | 2026-08-15 | verify: verified | ref: `project.godot:224` | sym: `Jolt Physics` | checked_on: 2026-10-14 | note: Forward Plus at :16
- D-190 [tech] Main entry is `scenes/main.tscn` → `main.gd` → `CompositionRoot.boot_async()` | status: built | 2026-08-15 | verify: stale | ref: `project.godot:15` | sym: `frontend.tscn` | checked_on: 2026-10-14 | note: main scene is now scenes/frontend.tscn, which loads main.tscn (ui/frontend_root.gd:296); main.gd:26 still calls boot_async
- D-191 [tech] `ENGINE_REFERENCE.md` was declared authoritative for Engine 1.0 architecture and content work should preserve that architecture | status: decided | 2026-07-16
- D-192 [tech] Architecture should be changed only when a concrete limitation requires it; avoid broad rewrites | status: decided | 2026-07-16
- D-193 [tech] Runtime services include configuration/performance services, chunk management, terrain editing, entity management, crystal management, world visuals, and fluid services | status: built | 2026-08-15 | verify: verified | ref: `scenes/main.tscn:114` | sym: `CrystalManager` | checked_on: 2026-10-14 | note: ConfigService :56, PerformanceService :59, WorldVisuals :71, EntityManager :108, TerrainEditor :123, VoxelFluidService :126
- D-194 [tech] Chunk rendering uses greedy meshing and face culling | status: built | 2026-04 | verify: verified | ref: `chunks/chunk_manager.gd:918` | sym: `_greedy_mesh_plane_region` | checked_on: 2026-10-14
- D-195 [tech] Mesh plans are cached and schema-versioned | status: built | 2026-10 | verify: verified | ref: `world/mesh_plan_cache.gd:4` | sym: `PLAN_VERSION` | checked_on: 2026-10-14
- D-196 [tech] Chunk streaming and localized dirty rebuilds are core performance techniques | status: built | 2026-08-15 | verify: verified | ref: `chunks/chunk_manager.gd:2436` | sym: `_drain_stream_pipeline` | checked_on: 2026-10-14 | note: dirty scope: helpers/terrain_dirty_scope.gd:28
- D-197 [tech] Worker snapshots should isolate background work from mutable live state | status: decided | 2026-08-15
- D-198 [tech] SAFE/LOW/MEDIUM/HIGH performance presets exist | status: built | 2026-07 | verify: verified | ref: `config/performance_quality_config.gd:6` | sym: `enum Preset` | checked_on: 2026-10-14
- D-199 [tech] LOW is the target for the user's Intel Iris Xe laptop; MEDIUM is intended for the brother's PC | status: decided | 2026-07
- D-200 [tech] The user's development laptop is a Dell Latitude 5420 with 16 GB RAM, Intel i7, and integrated Intel Iris Xe graphics | status: built | 2026-07 | verify: not-found | checked_on: 2026-10-14 | note: hardware fact, not in code
- D-201 [tech] Runtime verification must be real; do not claim Godot/headless or camera tests passed if they were not executed | status: decided | 2026-08-21
- D-202 [tech] Investigation should precede edits; prefer the smallest root-cause fix, one task at a time, with no unrelated changes | status: decided | 2026-08-21
- D-203 [tech] Focused tests should be used during iteration and the full suite should run at meaningful milestones | status: decided | 2026-10
- D-204 [tech] The full verification suite has historically taken around 30 minutes | status: built | 2026-10 | verify: not-found | checked_on: 2026-10-14 | note: timing fact, not in code
- D-205 [tech] The project has a large, historically dirty working tree; agents must avoid overwriting unrelated changes and should not assume a clean tree | status: decided | 2026-08
- D-206 [tech] `studio/NOW.md` is the concise handoff for current task/state and should be kept short | status: decided | 2026-10
- D-207 [tech] Agents should not repeat the entire master document in every prompt; read the relevant notes and work from repository truth | status: decided | 2026-10
- D-208 [tech] The current codebase should be extended rather than replaced with a new voxel engine | status: decided | 2026-08-31
- D-209 [tech] Performance target is 60 FPS, but performance on current test hardware was reported below target | status: bug | 2026-10-14 | verify: not-found | checked_on: 2026-10-14 | note: runtime measurement, not in code
- D-210 [tech] The 0.3.0 local release was recorded on 2026-10-14 with windowed verification of 8 PASS and 4 FAIL; water flow remained untested in that report | status: built | 2026-10-14 | verify: not-found | ref: `project.godot:14` | sym: `0.3.0` | checked_on: 2026-10-14 | note: version string present; test results not checkable in code
- D-211 [tech] Creature animations, use animations, and bow aim were listed as failures in that release report | status: bug | 2026-10-14 | verify: not-found | checked_on: 2026-10-14 | note: windowed test result; not checkable in code
- D-212 [tech] `verify_ramp_flank_faces`, `ridge_cardinal`, and `side_cell` were reported as stale fixtures after a placement-rule change, not necessarily production regressions | status: bug | 2026-10 | verify: verified | ref: `scripts/verify_ramp_flank_faces.gd:1` | checked_on: 2026-10-14 | note: the three fixture scripts still exist (also verify_ramp_ridge_cardinal.gd, verify_ramp_side_cell.gd); failure not re-run
- D-213 [tech] Open question: what is the current authoritative state of the full suite after the most recent Crystal Storm changes? | status: proposed

## Design Pivot (2026-10-14)

Decided by Cole and his brother on 2026-10-14 (11:40 PM PT). These override the older entries marked `superseded` below and in their sections.

- D-221 [art] Player, creatures and characters are true voxelized 3D models (built from voxels, lit and shadowed like the world), not billboards, 2D sprites or sprite regions cut onto flat parts; the player rig and creature work steer toward this | status: decided | 2026-10-14
- D-222 [voxels] The macro/micro voxel split (macro heightfield plus sparse micro bricks, two voxel sizes) is rejected as a design direction; one block size for player-facing terrain | status: rejected | 2026-10-14 | note: replaced by D-223 and D-224; removal is planned in studio/plans/2026-10-14-design-pivot.md
- D-223 [voxels] Tools can break more than one block at a time (area/multi-block breaking, e.g. 1x2, 3x3, line, by tool tier) instead of relying on finer micro voxels for detail | status: decided | 2026-10-14
- D-224 [voxels] Players craft and place structures larger than one block, such as walls, in the style of Sanctum 2 (pre-shaped multi-block pieces snapped to the grid) | status: decided | 2026-10-14
- D-225 [crystal] There is exactly one crystal. Premise: the players are treasure hunters who accidentally released it. This replaces multiple crystal spawn points, secondary/ruin/artifact spawns and the origin-boss victory structure | status: decided | 2026-10-14
- D-226 [progression] Win condition: destroy the single crystal | status: decided | 2026-10-14
- D-227 [combat] The boss is a mob/entity that spawns when the player gets close to destroying the crystal, so it appears near the end of that fight; it is not a sealed origin spawn point | status: decided | 2026-10-14
- D-228 [world] The world feels empty; it needs more content and density (points of interest, props, wildlife, loot, encounters) | status: decided | 2026-10-14
- D-229 [art] Lighting and shadows must improve (real-time shadows, ambient occlusion, characters and structures casting shadows) | status: decided | 2026-10-14
- D-230 [progression] A level/XP system is the next confirmed system | status: decided | 2026-10-14
- D-231 [progression] Skill abilities follow the level/XP system | status: decided | 2026-10-14
- D-232 [progression] Loss condition: players lose only when they die (death-only loss; no crystal-coverage, town-loss or timer loss) | status: decided | 2026-10-14 | note: answers Q-027

## Rejected / Superseded Decisions

- D-214 [tech] A Python/2.5D implementation path was abandoned in favor of Godot 4 and a 3D voxel engine | status: rejected | 2026-04
- D-215 [world] Infinite world generation was rejected in favor of a finite world with crystal pressure, loss conditions, and a clear endgame | status: rejected | 2026-04
- D-216 [crystal] Treating crystal as only a purple water-like fluid is inconsistent with the intended design; crystal should have its own propagation/material rules | status: rejected | 2026-10-14
- D-217 [tech] Replacing the existing voxel engine with a new engine is not the current plan | status: rejected | 2026-08-31
- D-218 [tech] Broad refactors or unrelated changes during focused bug fixes are not acceptable | status: rejected | 2026-08-21
- D-219 [voxels] Assuming every ramp issue is a topology problem was superseded by investigations identifying mesh-face ownership and cache-state defects | status: rejected | 2026-10
- D-220 [voxels] Treating “break a block and the ramps look correct” as an acceptable workaround for initial-load mesh defects is rejected | status: rejected | 2026-10
- Superseded on 2026-10-14 (status changed in place, see their sections): D-002, D-091, D-092, D-093, D-094, D-151, D-152 -> D-225..D-227 (one crystal); D-039..D-044, D-067, D-068 -> D-222..D-224 (macro/micro). No billboard-sprite decision existed in the ledger; D-221 sets voxel models.
