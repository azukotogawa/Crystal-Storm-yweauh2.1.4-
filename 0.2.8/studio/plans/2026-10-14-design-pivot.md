# Design Pivot Plan (2026-10-14)

Plan only, no code. Source decisions: D-221..D-232 in `studio/DECISIONS.md`; open questions Q-027..Q-032 in `studio/QUESTIONS.md`. File paths are relative to `0.2.8/` and come from grepping the `cs/playtest-0.2.9` tree on 2026-10-14. Every queue step is 30 minutes or less, runs one at a time, keeps all code comment-free, reads `AGENTS.md` and `studio/VISION.md` first, and ends with the VERIFY.md QUICK_CHECK passing plus a local commit. Not queued yet: Cole decides when.

## 1. One-crystal refactor (D-225, D-226, D-227)

Target: one crystal entity (the released crystal) with health; destroying it wins; a boss mob spawns when the crystal is nearly destroyed. No secondary, ruin or artifact spawns; no sealed origin boss.

Affected code:
- `crystal/crystal_manager.gd`: `_initialize_spawns`, `_add_feature_ruin_spawns`, `_add_ruin_spawn_at`, `_add_artifact_spawns`, `_pick_artifact_spawn_position`, `_pick_ruin_spawn_position`, origin placement (`pick_origin_spawn_cell`, `_resolve_origin_spawn_position`, `origin_corner_for_seed`), `set_origin_warden_alive`, `_grant_relic_for_spawn`, spawn markers / HP bars, `damage_spawn*`, `get_spawn_progress`, `_on_all_spawns_destroyed`, save/import of spawn rows.
- `crystal/spawn_point_controller.gd`: `count_active_non_boss`, `can_damage_spawn`, `boss_sealed`, `weaken_factor`, `_is_boss_active`, `export_spawn_rows`/`import_meta`.
- `crystal/crystal_spawn_point.gd`, `config/spawn_point_def.gd`, `config/spawn_point_registry.gd`, `config/game_config.gd` (spawn counts), `systems/config_json_io.gd`, `systems/config_service.gd`.
- `crystal/crystal_fluid_sim.gd` `tick_emitters` (multi-emitter to single emitter).
- `game/game_manager.gd`: `_on_all_spawns_destroyed`, `notify_boss_defeated`, `victory_reason`, `run_summary` (`boss_defeated`), `note_spawn_destroyed`, `_on_spawn_destroyed_stat`.
- `entities/boss_brain.gd`, `entities/crystal_enemy.gd`, `entities/crystal_enemy_spawner.gd` (boss as a spawned mob).
- `weapons/weapon_controller.gd` `damage_spawn_at_world`; `world/ruin_manager.gd` (ruins fed spawns; repurpose as treasure/loot sites, see D-228).
- UI: `ui/game_overlay.gd` (objective lines, spawn context, 65 boss refs), `ui/run_summary_panel.gd`, `ui/crystal_palette.gd`, `systems/combat_visual_feedback.gd`, `systems/game_visual_registry.gd`, `systems/topographical_map_builder.gd`, `config/topographical_map_config.gd`, `config/audio_manifest.gd`.
- Tests to update or retire (do not delete; mark legacy and drop from run_all): `scripts/verify_boss.gd`, `verify_spawn_goal.gd`, `verify_spawn_dry_disk.gd`, `verify_combat_crystal_damage.gd`, `verify_combat_parse.gd`, `verify_corruption.gd`, `verify_crystal_breaking.gd`, `verify_playable_loop.gd`, `verify_run_summary.gd`, `verify_full_game_loop.gd`.

Queue steps:
1. Config: a single-crystal mode const in `game_config.gd` defaulting on; registry returns one crystal def (health, position rule). Old spawn code stays reachable behind the flag. Add `verify_single_crystal.gd`.
2. Placement: one crystal placed by the Q-029 rule (default: current origin cell); skip ruin/artifact spawns when the flag is on.
3. Emission: `tick_emitters` with one emitter; remove the weaken-on-secondary path under the flag; keep spread rate tuned so coverage pressure is similar.
4. Damage and win: crystal health, `damage_spawn_at_world` hits the crystal; destroying it sets `victory_reason = "crystal"` and `Phase.VICTORY`.
5. Boss mob: when crystal health drops below a threshold (default 25 %, Q-028), spawn the boss via `crystal_enemy_spawner.gd` / `boss_brain.gd` near the crystal; boss death is not the win, it is a reward/stat.
6. Save/load: one-crystal save rows with migration from multi-spawn saves.
7. UI: objective text, crystal HP bar, map marker, run summary; drop "spawns left" and "origin sealed".
8. Tests: update the listed scripts to the one-crystal flow; full suite once.
9. Cleanup: remove the flag and dead multi-spawn branches once 1-8 pass (separate task, after Cole signs off).

## 2. Macro/micro removal (D-222)

Affected code: `helpers/macro_layer_grid.gd`, `helpers/micro_layer_grid.gd`, `helpers/micro_column_brick.gd`, `helpers/micro_cliff_detector.gd`, `helpers/micro_terrain_mesh_compositor.gd`, `helpers/micro_terrain_perf_gate.gd`, `chunks/chunk_data.gd` (35 micro / 29 macro refs), `chunks/chunk_manager.gd` (15), `chunks/voxel_world.gd`, `player/voxel_floor_probe.gd`, `systems/save_schema.gd`, `world/InfiniteNoiseWorld.gd`, `world/world_bake_service.gd`; tests `verify_macro_layer_grid.gd`, `verify_micro_layer_grid.gd`, `verify_macro_micro_save_migrate.gd`, `verify_micro_column_mesh_parity.gd`, `verify_micro_terrain_perf.gd`, `verify_dug_strata_no_cap.gd`, `verify_terrain_loop_complete.gd`, `verify_world_state_stale_worker.gd`.

Risk: terrain, ramps, water and meshing all read through `chunk_data.gd`; this is the riskiest refactor and must go behind a flag first.

Queue steps:
1. Audit task (docs only): map every caller of the micro path and what each edit kind (dig, build, cliff detail) uses; write `studio/plans/micro-callers.md`.
2. Flag `USE_MICRO_BRICKS` off: digging and building write whole blocks only; micro mesh compositor skipped. Run the ramp/water/terrain verify set.
3. Save schema: load old saves by collapsing micro bricks to whole blocks.
4. Mesh path: drop micro compositor from the chunk mesh pipeline under the flag; perf compare with `verify_macro_terrain_perf.gd`.
5. Decide block size (keep the current macro scale; `voxel_scale` stays locked unless Cole says otherwise).
6. Remove dead micro code and tests (after sign-off), never in the same task as a behavior change.

## 3. Multi-block breaking and large-structure placement (D-223, D-224)

Breaking: entry points `weapons/weapon_controller.gd` `_try_dig_tool`, `dig_brush_radius`, `helpers/item_types.gd` `breaks_blocks`, `world/terrain_edits.gd` `dig`, `systems/block_break_fx.gd`.
1. Add a break-shape per tool (single, 1x2 vertical, 3x3 face, 3-line) in `item_types.gd`; tier upgrades widen the shape.
2. `terrain_edits.gd`: batch dig over a cell list with one remesh/water/crystal update per chunk.
3. Highlight preview of the full shape (`verify_dig_highlight_placement.gd` pattern).
4. Drops and FX scaled per block, capped.

Structures (Sanctum 2 style): entry points `weapon_controller.gd` `_try_place_selected`, `terrain_edits.gd` `build_wall`, `systems/game_visual_registry.gd` `build_structure_array_mesh`, existing wood/stone wall, gate, bridge, town hall tests.
1. Structure blueprint data: footprint (e.g. wall 3 wide x 2 high x 1 deep), cost, crafting recipe.
2. Ghost preview with snap, rotation and validity tint; place writes all cells in one edit.
3. Crafting entry in inventory; first set: wall segment, wall corner, gate, stairs, tower (Q-032).
4. Damage/repair for structures; crystal interaction (crystal grows around or erodes them).
5. Verify scripts per piece (authored + live place + collision).

## 4. Win and loss

Win (decided, D-226/D-227): destroy the single crystal. The boss mob spawns when the crystal is close to destroyed and fights near it.
Loss (open, Q-027), options for Cole:
- A. Death only: the run ends when the player (or whole party) dies.
- B. Overrun: crystal coverage passes a threshold (current `max_crystal_coverage` 0.72) plus death.
- C. Consumed: the crystal reaches the treasure hunters' camp/town (fits the premise) plus death.
- D. Storm clock: the crystal finishes charging after N phases/days (Vampire Survivors-style pressure).
Recommendation: B or C plus death; both reuse existing code (`_check_crystal_overrun`, `_on_town_fallen`).

## 5. World density (D-228)

- Repurpose ruins (`world/ruin_manager.gd`) as treasure sites with loot chests and lore, tying into the treasure-hunter premise.
- Points of interest per chunk budget: camps, abandoned digs, crystal-touched groves, shrines, caves; a seeded POI scatter with min spacing.
- Prop density: rocks, logs, bushes, flowers, mushrooms, fences via `helpers/voxel_prop_builder.gd` and `world/feature_visual_layer.gd`; tuned per quality preset.
- Wildlife herds and ambient creatures (birds, rabbits) with spawn budgets per biome.
- Loot: resource veins and rare ores visible on the surface; small random encounters (wandering traders, ambushes).
- Landmarks visible from distance so the map reads at ortho 16.
- Measure: props/POIs per chunk before vs after, frame budget on MEDIUM.

## 6. Lighting and shadows (D-229)

Queued now as 2 tasks: DirectionalLight3D shadows plus WorldEnvironment (SSAO, tonemap, ambient, fog) gated by quality preset, keeping the locked sun; then vertex AO on chunk meshes and shadow casting for voxel characters/structures. `scenes/main.tscn` holds the light; `helpers/chunk_surface_mesh_builder.gd` has face shading (D-038).

## 7. Level/XP system (D-230), then skills (D-231)

XP outline:
1. `systems/progression_service.gd`: xp, level, curve (e.g. 50 * level^1.5), signals `xp_gained`, `level_up`.
2. Sources (Q-031): enemy kills by tier, crystal damage, mining, building structures, discovering POIs/treasure.
3. Level rewards: small stat gains (HP, damage, mining speed) through the existing relic/stat layer, plus a skill point per level.
4. HUD: XP bar and level-up toast in `ui/game_overlay.gd`; run summary shows level.
5. Save/load in the run save; per-run unless Cole lifts D-158 (no meta-progression).
6. Verify script for the curve, sources and save round-trip.
Skills (after XP lands): skill points unlock 1-3 active abilities on hotkeys with cooldowns (e.g. dash, ground slam that breaks a 3x3 area, crystal pulse that slows spread, quick-build a wall) and a few passives; a small tree per playstyle (fighter, miner, builder). Each ability one queue task.

## Order

Art voxel queue (running now) -> lighting -> one-crystal steps 1-8 -> multi-block breaking -> structures -> XP -> macro/micro removal -> density passes -> skills. Macro/micro and one-crystal both touch save and crystal/terrain code; never run them in the same window.
