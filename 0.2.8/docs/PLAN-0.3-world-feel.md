# Plan 0.3 — world feel

Status: plan only. This change adds no scripts, scenes, shaders, or art.
Branch: `cs/playtest-0.2.9`. Godot 4.7 project under `0.2.8/`.
Backlog: `#13` vegetation scale, `#14` block texture variants, `#15` wind particles, `#16` rain and weather, `#17` ambient life, `#18` cave mini-dungeons with loot.

`docs/DESIGN_0.2.9_TIER3.md` is the same intent, written against resource-field defaults. This file is the 0.3 build plan. Where the two differ, follow this file. The live gate is the **medium** preset after `PerformanceQualityConfig` applies it (`VERIFY.md` sets `CRYSTALSTORM_PERF_PRESET=medium`).

Sources checked on this branch: `helpers/voxel_prop_builder.gd`, `world/vegetation_manager.gd`, `config/world_gen_config.gd`, `systems/config_service.gd`, `helpers/voxel_types.gd`, `config/performance_quality_config.gd`, `entities/entity_brain.gd`, `relics/relic_registry.gd`, and `/mnt/d/LATEST/CrystalStorm/IDEAS-from-chats.md`.

## Locked for every phase

- Frame target stays **16.6 ms** (60 Hz). Medium soft cap stays `main_thread_budget_us` **8000**. New work gets its own cap so it cannot borrow from crystal dispatch or chunk upload.
- `WorldSettings.voxel_scale` stays **2.0 m**. `max_world_height_voxels` stays **20** (40 m of terrain). One block is the ruler for every size below.
- Terrain stays a heightfield. `ChunkData.set_voxel` stays a no-op. Dig edits column layers. `mesh_caves` stays **false** on every preset, including medium where `caves_enabled` is already true.
- Ramps stay one continuous slope. Face codes stay in `chunks/chunk_view.gd` and `helpers/terrain_ramps.gd`. A ramp’s top UV stays the landing column’s atlas cell.
- Lighting stays as it is. `helpers/terrain_lighting.gd` sun is `Vector3(0.55, 0.82, 0.38)`. Side faces stay at the shader’s 0.68 multiplier. `terrain_cave_fog` stays 0.55 until a player is inside a loaded cave room, then returns to 0.55 on exit. AO, contact shadows, and the default camera stay. Ortho size stays **16**.
- Five interior biomes stay: plains, steppe, forest, marsh, highland. Weather only tints particles by the biome that already exists.
- Block rules from 0.2.9 stay. Only pickaxes and other dig tools break blocks, including a cave barricade. An item with a right-click ability uses that ability and never places a block. The crystal hammer keeps its wind-up: impact at **0.62** of a **1.1 s** swing.
- Art stays hand-authored and nearest-filter. “Realistic counterparts” means the real species and the real size. Terrain tiles stay duller than structures. Studio rules in `TERRAIN_ART_STYLE.md` still bind tiles.
- Saves stay `WorldState` schema **v2** (`systems/save_schema.gd`). New fields are optional keys on the existing bundle. Bump the schema only if the importer drops unknown keys.
- Medium numbers this plan budgets against: render distance **2**, `max_entities` **64**, `animals_per_biome_chunk` **1**, `max_feature_billboards_per_chunk` **40**, `max_crystal_new_cells_per_tick` **14**, `max_absorption_cells_per_tick` **64**, `feature_visual` **2000 µs**. The class fields (128 entities, 2 animals, 24 new cells, 48 billboards) are overwritten when the preset applies. Do not raise the medium numbers.

## 1. Vegetation scale (`#13`)

`VoxelPropBuilder.unit()` is `voxel_scale * 0.62` = **1.24 m**. Scatter writes a growth stage, and the box height is `(stage + 1) / 3`. Trees and bushes bake at stage 2 (full). Grass, tall grass, flowers, and ferns bake at stage 1. That is what the player sees today, next to a player who is `1.6 * voxel_scale` = **3.2 m** tall.

| Id | Placed now | Real counterpart | Ship target |
| --- | --- | --- | --- |
| grass_tuft | 3.55 m blades (stage 1) | meadow bunchgrass, 0.4–0.9 m | **0.8 m** |
| tall_grass | 5.54 m (stage 1) | reed / wheatgrass, 1.2–1.8 m | **1.6 m** |
| wildflower | 1.73 m (stage 1) | meadow flower, 0.4–0.7 m | **0.6 m** |
| fern | 1.57 m tall (stage 1) | bracken, 0.8–1.4 m | **1.2 m** |
| bush | 2.79 m tall, ~3.6 m wide (stage 2) | hazel shrub, 1.5–2.5 m | **2.2 m tall, 2.8 m wide** |
| tree | **12.62 m** tall, trunk ~1.05 m, crown ~11.5 m (stage 2) | temperate oak or beech, 20–25 m, bole 1–2 m, crown 14–20 m | **22 m tall (11 blocks), trunk 2.0 m (one block), crown 16 m** |
| shard_tree | 7.01 m at the same full growth | the oak, crystal-eaten | **22 m**, crystal silhouette kept |

Cole’s note that trees are about one fifth of voxel size is the same complaint: the bole is half a block wide and the canopy is two boxes on 2 m cubes. A literal ×5 oak is 63 m. Terrain tops out at 40 m, and a 63 m crown fills the iso frame (default ortho 16) and hides ramps and towns. Ship the 22 m oak (about 1.7× today’s height, about 2× trunk width). Phase 1 also places one **40 m** marker tree, the height cap, in a debug grove. If that marker is the one that reads right beside a 2 m cliff, the grove uses 40 m. Otherwise the grove uses 22 m. Grass and flowers get smaller. Scaling every prop by 5 makes the meadow worse: today’s grass already stands over the player’s head.

Crystal forms stay the swap in `crystal/crystal_corruption.gd`: tree → shard_tree, bush and fern → crystal_bush, other plants → crystal_grass. Same height as the living plant they replace. Deer → crystal_stag, boar → corrupted_beast, rabbit → crystal_mite, bird → crystal_wisp. No new species.

One tree id, three silhouettes by biome: oak in plains and forest, a shorter wind-bent crown in steppe, a darker wetter crown in marsh. Highland uses the oak with less understory. Steppe and savanna grass stays yellow-olive. Forest, plains, and marsh stay green. Art is boxes or a few authored meshes on `res://assets/art/voxel_brick.png` and the billboards under `res://assets/art/vegetation/`. Batch 1 twins stay behind `helpers/texture_set.gd` and load only when the file exists.

### Density

A booted game does not use `VegetationManager`’s export defaults (tree 0.085, grass 0.68, bush 0.11, 18000 attempts). `ConfigService` copies `WorldGenConfig`: grass **0.18**, tree **0.045**, bush **0.06**, attempts **12000**, then multiplies attempts by the preset (`vegetation_scatter_multiplier` **1.05** on medium, about 12600 rolls). Tall grass **0.38**, flower **0.10**, and fern **0.08** stay on the manager, because the service does not copy them. Rolls cover `PLAYABLE_HALF * 0.85`. Forest multiplies the tree roll by **1.8**, marsh by 0.35, steppe by 0.55. Town cells, river, water, and stone refuse plants. Most cells are never rolled, so a forest chunk holds a fraction of a tree.

A closed canopy cannot be one `FeatureRegistry` entry per visual tree. Absorption already scans up to 64 cells a tick, and medium allows 40 feature billboards per chunk.

Two layers:

1. **Gameplay plants** stay features. They absorb, deny, and save through WorldState tombstones. Denial and absorb stay as registered (`plantable_registry.gd`: tree denial radius 2, absorb 0.05 at the last stage). A bigger oak is a bigger mesh, not a stronger wall. Forest groves replace the independent per-cell tree roll: grove noise picks centers, then stamps **4–6** trees at least **4 cells** (8 m) apart so 16 m crowns touch and trunks do not stack. Cap registered trees at about **2×** today’s count. Bushes stay features, a little denser in forest and marsh only. Flowers, ferns, and their current denial stay features. Leave `vegetation_scatter_attempts` at 12000. Groves are a second pass. When that pass lands, copy tall-grass, flower, and fern density from `WorldGenConfig` too, so one resource owns the roll.
2. **Visual fill** is not a feature. One `MultiMesh` per chunk for ground cover (grass, short flowers) and, in forest, a canopy fill with no collision and no absorb rate. Hide that chunk’s fill when crystal depth covers the chunk, on the chunk dirty path. Cap **128** cover instances per chunk and **32** canopy-fill instances per forest chunk. Build them inside the existing `feature_visual` budget (2000 µs, one chunk a frame).

Fallen-log barriers are a later pass. They need a new feature kind. Plants still absorb slowly and still grant the crystal a small boost when they finish.

## 2. Block texture variants (`#14`)

`helpers/voxel_types.gd` maps each tile id to one cell of `Cube.png` (**7 × 10 × 32**). `get_atlas_coord_for_face` already sends grass tops to the top cell and dirt, bark, or rock to the side cell. Several families already own more than one top: grassland has five cells, forest hills have three unique cells, snow and desert have three. A column of one biome still repeats a single cell, which is the tiled read.

Variants are a **deterministic hash of the column** (`world_x`, `world_z`, family) into that family’s existing top cells, at least three when the family has them. The same function feeds the ramp, so a slope matches its landing. Sides stay the family side tile. Bottoms stay the current underside cell.

Author a new top only when a family has fewer than three unique tops and a cell in the 7×10 grid is unused or is a pure duplicate (ocean ids share `(0,0)`; river and water share `(1,0)`; `HILLS3` shares `(1,3)`). Hue shifts stay inside the family, 32×32, marks inside the inner 30×30. Leave the atlas grid at 7×10. Add no shader branch for variants. Write the coord where quads are already built (`chunks/chunk_mesh_buffer_builder.gd` → `ChunkView._write_atlas_custom`). Remesh of the same column emits the same cell. Greedy merges join quads that share the variant. A variant change starts a new run.

Crystal, crystal vein, shard ground, and scar stay one cell each so corruption still reads as one material.

Record new cells in `docs/TEXTURE_MANIFEST.md` when the art lands. That manifest is not part of this plan.

## 3. Wind particles (`#15`)

One `wind_field` on the world: a horizontal direction plus a slow gust (period 6–10 s, small amplitude). It writes a shader global. It does not push the player, the crystal, or any body.

- Vegetation sway is a vertex offset on plant materials only. Grass tips move about 0.15 m. Crowns move about 0.4 m. Terrain, ramps, structures, and crystal meshes do not sample the wind.
- Leaf and pollen specks are one `GPUParticles3D` parented to the camera. Medium amount **128**, low 48, high 256, safe 0. No collision, no attractor, a box about 24 m across. Direction follows `wind_field`.
- Leave `systems/vfx_pool.gd` alone. That pool is one-shot combat and shatter `CPUParticles3D` with a small cap and an idle `_process`. Wind is ambient and GPU.

## 4. Rain and weather (`#16`)

New `world/weather_director.gd`, ticked from a new scheduler bucket `weather` at priority **55** (between `living_world` at 50 and `entity_spawn` at 60), **400 µs**, max 1 unit a frame. It does not take time from crystal dispatch or chunk upload.

States are seeded from `world_seed` so a save restores the phase:

| State | Length | What changes |
| --- | --- | --- |
| clear | 3–6 min | wind only |
| rain | 45–90 s | rain particles, a wet darkening uniform, a rain loop slot |
| crystal storm | 30–60 s | rain or shard particles, a growth pulse, one pickup |

Rain is a second `GPUParticles3D` on the camera. Medium **600** particles, low 200, safe 0. Box about 40×24×40 m. No per-drop script and no splash physics. Highland uses the same emitter with a snow albedo. Steppe uses fewer, dust-colored particles. Marsh and forest use the rain look. Wetness is one albedo multiply (`weather_wet` 0–1) applied equally on every terrain face, so the 0.68 side ratio and the sun vector stay put. It fades out over 20 s after rain. It does not remesh.

Crystal storm is the chat’s “storm as event”, cut to what the sim already allows. For the duration, empty-cell inflow is multiplied by **1.35** and still stops at the active preset’s `max_crystal_new_cells_per_tick` (**14** on medium) and the existing spread damping. Floating shards are 32 GPU particles. The storm does not edit terrain, change physics, or add an enemy family. The one rare pickup is `storm_mote` at the storm’s marked cell, granted through the existing relic path when the player lacks it. The first storm of a run can be the alpha “First Storm” beat: one pulse plus that mote. Later storms repeat the pulse without a second unique item.

Audio slots go in `config/audio_manifest.gd` and `assets/audio/SOUNDS_NEEDED.md` (rain loop, distant thunder, storm start). A missing file stays silent. Audio does not gate the feature.

Map temperature bands, seasons, and rivers that rewrite vegetation stay in the living-world epic. They are not 0.3.

## 5. Ambient life (`#17`)

### Wildlife that leaves

Passive animals already flee. `entities/entity_brain.gd` uses `FLEE_CRYSTAL` when depth at the animal is at least `crystal_flee_depth` (0.15) and `FLEE_THREAT` when the player is inside `flee_distance`. They then wander back. The meadow refills, so corruption never looks like it emptied the place.

Add a migration home on the existing body:

- While depth near the animal stays at or above 0.15, retarget `home_pos` **16–24 cells** away from the nearest crystal cell, opposite the depth gradient, at most once every **8 s**.
- Deer and rabbits in the same chunk share that home so they leave as a group. Boars flee on their own. Birds only raise a visual Y offset. Flying physics stays out.
- If the animal is absorbed before it gets out, the current conversion stands.
- Leave medium `max_entities` at **64** and `animals_per_biome_chunk` at **1**. Life reads through motion. The goal is graze, then leave.
- Killing a town-tagged animal still feeds the crystal and still sours that town. No new faction simulator.

A one-line note on the debug panel (brain state and home cell) is optional and sits behind the profiler flag.

### Town volunteers

Towns already exist: `WorldGenConfig` places **3** small towns and **1** large port. Villagers and militia are in `entities/entity_brain_registry.gd`. Militia already alert (`world/town_defense_manager.gd`). Volunteers are a separate, player-facing errand. They do not replace militia.

One active errand per town, **2–5 minutes**, at most **4** on the map (one per settlement), and at most **3** extra bodies at once so the medium entity cap still holds. Offer when the town has not fallen and attitude is not sour. Attitude sours if the player kills a town animal during the errand. Militia still defends. Attitude is a field on the town dict, saved with WorldState.

| Role | Behavior | Uses |
| --- | --- | --- |
| Scout | Walks toward the nearest ruin or a point 40–80 cells out and drops a timed minimap disc | The existing map. There is no fog-of-war renderer. |
| Porter | Walks to the player once, grants a small stack of an existing material, and returns | Inventory |
| Hunter | Walks to the nearest passive animal and pings it | A marker. The hunter does not kill. The moral choice stays with the player. |
| Engineer | Restores town health with `TownDefenseManager.restore_health`, or tops up one damaged player barricade | No new geometry, so ramps stay valid |
| Runner | A shorter villager (×0.75 on the same prop) carries a one-line rumor to another town: a relic direction or a crystal warning | The chat’s message-runner. No age system and no separate child rig. |

Reuse `town_villager` brains and `WorldEntity`. They despawn when the timer ends or the town falls. Names and the rumor string are data on the errand.

## 6. Caves as mini-dungeons with loot (`#18`)

Noise caves already generate (`config/world_gen_config.gd`, and medium `caves_enabled` is true) and are not meshed. Leave that path alone. A carved tunnel in the heightfield is the wrong tool: `set_voxel` does nothing, and turning on `mesh_caves` would remesh the map.

A set piece is an authored interior, placed like a ruin:

- New `world/cave_setpiece_manager.gd`, same pattern as `world/ruin_manager.gd`: seeded, count **4**, min separation about 100, outside towns, prefer forest and highland edges. Four singles. Clustered ruins stay a later art pass.
- The overworld shows a mouth marker and a short stair of existing blocks. Walking in hides the heightfield shell over that small footprint and instances a room scene. Walking out unloads it. Only **one** interior is loaded.
- Collision is the room mesh. The heightfield outside the footprint is unchanged, so overworld ramps stay valid.
- Lights: at most **8** `OmniLight3D` torches in the active room. They do not alter `terrain_sun_dir`. `terrain_cave_fog` rises only while the interior is loaded, then returns to 0.55.
- Camera: if the player is more than 3 layers below the local surface at the mouth, add a local offset so the bowl reads. The default overworld camera stays. A trench dug in the open keeps the current camera. The offset is the dungeon only.
- A breakable barricade uses the existing build and dig path. Only a dig tool breaks it. A right-click item still cannot place a block inside the room.

Four templates, 2–3 rooms, a clear in well under a minute:

1. Root cellar. Stair, one room, chest. A mite only if corruption is already in the chunk.
2. Vein chapel. Crystal hazard in the room using the existing crystal visual. The chest tends toward the flow-anchor family.
3. Flooded cleft. Shallow water in the room only. Crystal does not cross water. The chest sits on the dry ledge.
4. Barricade tomb. One breakable wall. The chest is behind it.

Loot is player loot. Ruin artifacts stay extra crystal spawn points (`world/living_world_director.gd` calls `RelicRegistry.ruin_loot_pool()`: pathfinder charm, ruin seal, flow anchor, mason glove). Cave chests use a new `RelicRegistry.cave_loot_pool()` beside that pool. One relic grant through the existing relic path, plus a small material stack. The chest-opened flag lives on WorldState. No boss and no new enemy.

Local light and the room mesh are the “torches and underground readability” note. They are not a global cave renderer.

## Perf budget

Target: **16.6 ms/frame**, medium preset, render distance 2, standing in a forest grove in the rain. Tracked main-thread work stays inside the 8000 µs soft cap.

| Work | Cap | Where |
| --- | --- | --- |
| Wind uniform | 50 µs | main, no particle script |
| Leaf GPU particles | 0 script | 128 medium / 48 low / 0 safe |
| Rain GPU particles | 0 script | 600 medium / 200 low / 0 safe |
| Weather director | 400 µs, 1 unit/frame | new bucket `weather`, priority 55 |
| Storm inflow | inside the crystal tick | ×1.35, still ≤ 14 new cells on medium |
| Cover + canopy MultiMesh | inside `feature_visual` 2000 µs, 1 chunk/frame | 128 cover + 32 canopy fill |
| Gameplay plants | existing feature path | ≤ 14 features per visible chunk |
| Animal migration | existing entity tick | retarget every 8 s, ≤ 64 entities |
| Volunteers | ≤ 3 extra `WorldEntity` | reuse villager, inside the 64 cap |
| Dungeon | 0 until entered | 1 interior, ≤ 8 omni lights |
| Atlas variant | 0 on the main thread | hash while the worker builds the mesh |

Safe preset: wind, rain, cover fill, and dungeon lights off. Gameplay trees may stay at today’s density on safe. Low: half the particle counts, cover instances 64, no canopy fill.

Pass line for a later implementer (this plan does not launch Godot): `CRYSTALSTORM_PROFILE_SECONDS=45` on `scripts/profile_gameplay.gd`, grove in view, rain forced. p95 frame ≤ 16.6 ms, `feature_visual` ≤ 2.0 ms, crystal new cells still ≤ 14 per tick on medium. Existing ramp and lighting checks stay green.

## Phases

Each phase ships alone and keeps the budget. A phase does not start by editing ramps, `terrain_lighting.gd` (except the cave-fog toggle in phase 9), `voxel_scale`, the hammer wind-up, dig-tool rules, or the default camera.

### Phase 1 — Scale plate

Put the table’s meters into the plant boxes. Spawn a debug grove: the 22 m oak and one 40 m marker. A headless check asserts extents at `voxel_scale` 2.

Files: `helpers/voxel_prop_builder.gd`, `world/plantable_registry.gd`, `config/plantable_def.gd` (store target height and footprint; leave absorb and denial), new `scripts/verify_vegetation_scale.gd`.

### Phase 2 — Counterpart silhouettes

Three tree crowns by biome, shorter grass and flowers, crystal forms at the new height. Billboards and voxel props both. Nearest-filter. Batch 1 paths only when the file exists.

Files: `helpers/voxel_prop_builder.gd`, `systems/game_visual_registry.gd`, `world/feature_visual_layer.gd`, `assets/art/vegetation/` (and `assets/art_batch1/vegetation/` only as twins).

### Phase 3 — Groves and visual fill

Gameplay groves plus the non-feature MultiMesh. Crystal in a chunk hides that chunk’s fill. Move tall-grass, flower, and fern density onto `WorldGenConfig` and copy them in `ConfigService` with the densities it already copies.

Files: `world/vegetation_manager.gd`, `config/world_gen_config.gd`, `systems/config_service.gd`, `world/feature_visual_layer.gd`, new `world/vegetation_cover.gd`, `config/performance_quality_config.gd` (instance caps), `helpers/visual_proximity.gd` if the column band should also gate cover.

### Phase 4 — Atlas variants

Hash at mesh build into the family’s existing tops. Ramps match the landing. Sides unchanged. Author a cell only where the family has fewer than three unique tops and the 7×10 grid has room.

Files: `helpers/voxel_types.gd`, `chunks/chunk_mesh_buffer_builder.gd`, `chunks/chunk_view.gd` only if `_write_atlas_custom` must read the column hash, `assets/tiles/` and `Cube.png` when a cell is actually free, `docs/TEXTURE_MANIFEST.md` when cells exist. New `scripts/verify_atlas_variant_stable.gd` (same column after remesh; ramp top equals landing top).

### Phase 5 — Wind

Wind field, plant sway shader, leaf particles. Terrain shader untouched.

Files: new `world/wind_field.gd`, new `shaders/vegetation_sway.gdshader`, new `systems/ambient_particles.gd`, `systems/composition_root.gd` (parent the emitters), `config/performance_quality_config.gd`.

### Phase 6 — Rain and crystal storm

Director, particles, wet uniform, inflow pulse, `storm_mote`, audio slots.

Files: new `world/weather_director.gd`, `systems/ambient_particles.gd`, `systems/frame_budget_scheduler.gd`, `config/crystal_sim_config.gd` or the small multiplier site in `crystal/crystal_manager.gd`, `crystal/crystal_simulation.gd` only for the clamped multiplier, `config/audio_manifest.gd`, `assets/audio/SOUNDS_NEEDED.md`, `systems/save_schema.gd` only if the phase must persist and unknown keys are dropped, `world/world_state.gd` export/import.

### Phase 7 — Wildlife leaves

Migration home. No new species and no higher caps.

Files: `entities/entity_brain.gd`, `entities/entity_navigation.gd`, `config/entity_brain_config.gd`, `entities/entity_manager.gd` (shared herd home). `crystal/crystal_corruption.gd` stays the conversion table.

### Phase 8 — Volunteers

Errands, attitude, save the active errand.

Files: new `world/town_volunteer_manager.gd`, `world/town_manager.gd`, `world/town_defense_manager.gd` (call `restore_health` only), `entities/entity_brain_registry.gd`, `world/world_state.gd`, the minimap ping site in `systems/topographical_map_builder.gd` or the existing map UI.

### Phase 9 — Cave set pieces and loot

Four mouths, one loaded interior, chest pool. Dig tools break the barricade. Right-click items still do not place.

Files: new `world/cave_setpiece_manager.gd`, new scenes under `scenes/caves/`, `world/feature_registry.gd`, `relics/relic_registry.gd` (`cave_loot_pool`), `world/world_state.gd` (chest opened), `player/camera.gd` and `helpers/camera_cutaway.gd` for the mouth offset only, `helpers/terrain_lighting.gd` only to toggle `terrain_cave_fog` while an interior is loaded and to restore 0.55 on exit. Leave `chunks/chunk_manager.gd` `_emit_cave_faces` alone. Leave `mesh_caves` false.

## Out of scope

- `voxel_scale`, ramp geometry, the sun vector, the 0.68 side factor, the default camera, the hammer wind-up, and the dig-tool / right-click place rules.
- `mesh_caves = true`, volumetric caves, dig brushes, storm terrain mutation, floating-island physics.
- New biomes, seasons, vegetation that spreads on its own, rivers that rewrite plants, fallen logs.
- Photoreal tiles, a bigger atlas grid, Starweave music, respawn rules, a new boss.
- Raising medium caps: 64 entities, 1 animal per biome chunk, 14 new crystal cells per tick, 40 feature billboards per chunk.
- More than 3 volunteer bodies, more than 4 dungeons, more than one loaded interior.
- A 63 m (×5) tree.
- Multiplayer. Weather and wind are local presentation. The storm inflow multiplier is sim and must be host-owned later. That host path is not built here.

## Operator check

After phase 1, look at the grove next to a 2 m cliff and a ramp. The 22 m oak’s trunk should read as one block wide, and grass should be shorter than the 3.2 m player. Pick 22 m or the 40 m marker before phase 3 multiplies the forest. After phase 6, stand in that grove in the rain and read the profiler. After phase 9, enter one dungeon, take the chest, leave, and confirm the overworld ramp and the sun direction did not change. A pick still breaks the barricade. A herb, bomb, or piece of armor still does not place a block.
