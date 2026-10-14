# 0.2.9 Tier 3 — alive world (design only)

Status: plan. No code in this change. Branch `cs/playtest-0.2.9`. Godot 4.7 project under `0.2.8/`.

This tier makes the map feel inhabited: plants at real-life size, varied ground, wind and storms, animals that leave when the crystal arrives, townspeople who come help, and a few caves you can walk into and loot. It does not retune ramps or lighting, and it does not change `voxel_scale`.

Sources: `/mnt/d/LATEST/CrystalStorm/IDEAS-from-chats.md` (living world, volunteers, storm-as-event, cave set pieces, world-scale spec) and `/mnt/d/LATEST/CrystalStorm/CONTENT.md` (measured props on this branch). Studio art rules in `TERRAIN_ART_STYLE.md` still bind terrain tiles. Frame target stays **16.6 ms** (`PERFORMANCE_RUNTIME.md`, `FrameBudgetScheduler`).

## Locked constraints

- `WorldSettings.voxel_scale` stays **2.0 m** (`config/default_world_settings.tres`). One block is the scale everything else is measured against.
- Terrain stays a heightfield. `ChunkData.set_voxel` is a no-op. Dig is column layers. Do not turn on `mesh_caves` (false on every preset in `config/performance_quality_config.gd`).
- Ramps stay as they are: one continuous slope, face codes in `chunks/chunk_view.gd` / `helpers/terrain_ramps.gd`. Ramp UVs keep using the column's top atlas cell (`TERRAIN_ART_STYLE.md`). No second UV path.
- Lighting stays as it is. `helpers/terrain_lighting.gd` sun is `Vector3(0.55, 0.82, 0.38)`. Side faces stay at the shader's 0.68 multiplier. `terrain_cave_fog` stays 0.55 until a player is inside a set piece. Do not retune AO, contact shadows, or the default camera (the last commit moved it closer).
- Five interior biomes stay: plains, steppe, forest, marsh, highland (`world/biome_layout.gd`). No new biome, no season system, no "Australia / Europe / N. Russia" map-temperature roll in this tier. Weather only tints particles by the biome that already exists.
- Hand-authored, nearest-filter art. "Realistic counterparts" means the real species and the real size. It does not mean photo bark or a photoreal atlas. Terrain tiles stay duller than structures.
- Save authority stays `WorldState` schema v2 (`systems/save_schema.gd`). New fields are optional keys on the existing bundle. Bump the schema only if the importer drops unknown keys.
- Medium preset is the budget that must hold: `main_thread_budget_us` 8000, render distance 2, `max_entities` 128, `animals_per_biome_chunk` 2.

## Why the plants read wrong

`VoxelPropBuilder.unit()` is `voxel_scale * 0.62` (1.24 m). Mature tree boxes in `helpers/voxel_prop_builder.gd` then come out as measured in `CONTENT.md`:

| Id | Now | Real counterpart | Ship target |
| --- | --- | --- | --- |
| grass_tuft | 3.55 m blades | meadow bunchgrass, 0.4–0.9 m | **0.8 m** |
| tall_grass | 5.54 m | reed / wheatgrass, 1.2–1.8 m | **1.6 m** |
| wildflower | 1.73 m | meadow flower, 0.4–0.7 m | **0.6 m** |
| fern | 1.57 m, ~1.55 m wide | bracken, 0.8–1.4 m | **1.2 m** |
| bush | 2.79 m tall, ~3.6 m wide | hazel shrub, 1.5–2.5 m | **2.2 m tall, 2.8 m wide** |
| tree | **12.62 m** tall, trunk ~1.05 m wide, crown ~11.5 m | temperate oak or beech, 20–25 m, bole about 1–2 m, crown 14–20 m | **22 m tall (11 blocks), trunk 2.0 m wide (one block), crown 16 m** |
| shard_tree | 7.01 m | same oak, crystal-eaten | **22 m**, crystal silhouette kept |

Cole: trees are about **1/5 too small versus the voxels**. The chat line is the same complaint ("~1/5 voxel size → enormous terrain + tiny toys"). The measured crown is already 6.3 blocks, so the toy read is the **trunk** (about half a block wide) and the two-box canopy sitting on 2 m cubes, not a missing zero on `voxel_scale`.

A literal ×5 tree is 63 m. Terrain tops out at 20 layers × 2 m = **40 m**. A 63 m oak also fills the iso frame (ortho about −35.264 / 45, zoom ~10–18) and hides ramps and towns. Do not ship ×5.

Ship the oak in the table (about 1.7× today's height, about 2× trunk width, so the bole matches one voxel). Phase 1 also places a single **40 m** marker tree (the height cap, about 3.2× today) in the debug grove. If that marker is the one that finally reads right next to a cliff, the operator picks it and the grove uses 40 m. Default if there is no pick: **22 m**. Grass and flowers get smaller. Scaling every prop by 5 makes the meadow worse.

Crystal forms stay the corruption swap already in `crystal/crystal_corruption.gd`: tree → shard_tree, bush and fern → crystal_bush, other plants → crystal_grass. Same heights as the living plant they replace. Deer → crystal_stag, boar → corrupted_beast, rabbit → crystal_mite, bird → crystal_wisp. Do not add species.

Steppe and savanna recolor stays yellow-olive on grass. Forest, plains, and marsh stay green. One tree id, three silhouettes chosen by biome (oak in plains/forest, shorter wind-bent tree in steppe, wetter darker crown in marsh). Highland gets the oak with less understory. That is the "realistic counterpart" set. Art is boxes or a few authored meshes on `res://assets/art/voxel_brick.png` and the existing billboard paths under `res://assets/art/vegetation/`. Batch 1 twins stay behind `helpers/texture_set.gd`.

## Density without a plant per cell

Playable half is 1024 cells (`helpers/world_border.gd`). Scatter uses `half * 0.85` and **18000** attempts (`world/vegetation_manager.gd`). `tree_density` is 0.085, forest bias 1.8. Most cells are never rolled, so a forest chunk holds a fraction of a tree. The map looks empty. A real closed canopy cannot be one `FeatureRegistry` entry per visual tree: absorption already scans 64 cells a tick, and `max_feature_billboards_per_chunk` is 48.

Two layers:

1. **Gameplay plants** stay features. They absorb, deny (tree `denial_radius` 2), and save through WorldState tombstones. Forest groves replace the independent per-cell tree roll: a grove noise picks centers, then stamps **4–6** trees at least **4 cells** (8 m) apart so 16 m crowns touch and trunks do not stack. Cap registered trees at about **2×** today's count. Bushes stay a feature, a bit denser in forest and marsh only. Flowers, ferns, and the denial they already have stay features. Do not raise `scatter_attempts` above 18000 for the grass roll; groves are a second pass.
2. **Visual fill** is not a feature. One `MultiMesh` per chunk for ground cover (grass, short flowers) and, in forest, a canopy fill that has no collision and no absorb rate. Hide fill instances in a chunk when crystal depth covers that chunk, on the chunk dirty path, not per blade per frame. Cap **128** cover instances per chunk and **32** canopy-fill instances per forest chunk. Build them inside the existing `feature_visual` budget (2000 µs, 1 chunk a frame).

Town stamps stay clear of scatter, as they are now. Water, river, and stone still refuse plants.

Denial, flow factors, and absorb rates on `config/plantable_def.gd` do not change with the mesh size. A bigger oak is not a stronger wall unless a later pass says so. Fallen-log barriers from the gameplay doc are out of this tier (they need a new feature kind). Plants still absorb slowly and still grant the crystal a small boost when finished.

## Block texture variants

`helpers/voxel_types.gd` picks one atlas cell per tile. `Cube.png` is 7×10×32. `get_atlas_coord_for_face` already sends grass tops to the top cell and dirt/bark/rock to the side cell. Variants are a **deterministic hash of the column** (`world_x`, `world_z`, tile family) into 3 top cells of that family. The same function feeds the ramp, so a slope matches its landing. Sides stay the family side tile. Bottoms stay unauthored.

Families that get 3 tops: grass/plains, forest, steppe, marsh, sand, stone, snow, town path, farmland. Crystal, crystal vein, shard ground, and scar stay one cell each so corruption still reads as one material. Author the extra tops as hue shifts inside the family, 32×32, wrapping, marks inside the inner 30×30. Do not grow the atlas grid and do not add a shader branch for variants. The coord is written where quads are already built (`chunks/chunk_mesh_buffer_builder.gd` → `ChunkView._write_atlas_custom`). Remesh of the same column must emit the same cell. Greedy merges may only merge quads that share the variant, or the stretch will stripe. Prefer not merging across a variant change over adding a new shader.

Record the new cells in `docs/TEXTURE_MANIFEST.md` when the art lands. That file is not part of this plan's commit.

## Wind

One `wind_field` on the world: a horizontal direction plus a slow gust (period 6–10 s, amplitude small). It writes a shader global. It does not push the player, crystal, or rigid bodies.

- Vegetation sway is a **vertex offset on plant materials only**. Grass tips move about 0.15 m, crowns about 0.4 m. Terrain, ramps, structures, and crystal meshes do not sample it.
- Leaf and pollen specks are one `GPUParticles3D` parented to the camera, amount **128** on medium (48 low, 256 high, 0 on safe). No collision, no attractor, box about 24 m. Direction follows `wind_field`.
- Do not put this in `systems/vfx_pool.gd`. That pool is one-shot combat and shatter CPU particles with a small cap. Wind is ambient and GPU.

## Rain, weather, storms

`world/weather_director.gd`, ticked from a new scheduler bucket `weather` at priority 55, **400 µs**, max 1 unit a frame. It does not take time from crystal dispatch or chunk upload.

States, seeded from `world_seed` so a save restores the phase:

| State | Length | What changes |
| --- | --- | --- |
| clear | 3–6 min | wind only |
| rain | 45–90 s | rain particles, a wet darkening uniform, rain loop |
| crystal storm | 30–60 s | rain or shard particles, a growth pulse, one pickup |

Rain is a second `GPUParticles3D` on the camera. Medium **600** particles, low 200, safe 0. Box about 40×24×40 m. No per-drop script and no splash physics. Highland uses the same emitter with snow albedo. Steppe uses fewer, dust-colored particles. Marsh and forest use the rain look. Wetness is a single albedo multiply (`weather_wet` 0–1) applied equally on every terrain face so the 0.68 side ratio and the sun vector stay put. It fades out over 20 s after rain. It does not remesh.

Crystal storm is the chat's "storm as event", cut to what the sim already allows. For the duration, empty-cell inflow is multiplied by **1.35** and still clamped by `max_crystal_new_cells_per_tick` (24) and the existing spread damping in `performance_quality_config.gd`. Floating shards are 32 GPU particles. No terrain mutation, no physics change, no new enemy family. The "one rare resource" is a single pickup id `storm_mote` at the storm's marked cell. Grant it through the existing relic path if the player lacks it; do not add a new progression track. First storm of a run can be the alpha "First Storm" beat: one pulse plus that mote. Later storms repeat the pulse without a second unique item.

Audio slots go in `config/audio_manifest.gd` and `assets/audio/SOUNDS_NEEDED.md` (rain loop, distant thunder, storm start). Missing files stay silent. Do not block the feature on audio.

Map temperature bands, seasons, and rivers that rewrite vegetation are the living-world epic and are not this tier.

## Wildlife that leaves

Passive animals already flee. `entities/entity_brain.gd` uses `FLEE_CRYSTAL` when depth at the animal is at least `crystal_flee_depth` (0.15) and `FLEE_THREAT` when the player is inside `flee_distance`. They then wander back. That is why the corruption never looks like it empties a meadow.

Add a migration home, not a new body:

- While depth near the animal stays at or above 0.15, retarget `home_pos` **16–24 cells** away from the nearest crystal cell, opposite the depth gradient, at most once every **8 s**.
- Deer and rabbits in the same chunk share that home so they leave as a group. Boars flee on their own. Birds only raise a visual Y offset; do not add flying physics.
- If the animal is absorbed before it gets out, the current conversion stands.
- Do not raise `max_entities` or `animals_per_biome_chunk`. Life reads through motion. Rain World was the reference for "they have their own goal", and the goal here is graze, then leave.
- Killing town-tagged animals still feeds the crystal and still sours that town (see volunteers). No new faction simulator.

Debug: the existing entity state is enough. A one-line note on the debug panel (brain state + home cell) is optional and must sit behind the profiler flag.

## Town volunteers

Towns already exist: 3 small settlements (`world/town_manager.gd`), villagers and militia (`entities/entity_brain_registry.gd`), militia on alert (`world/town_defense_manager.gd`, 2 on alert, 4 when besieged). Volunteers are a separate, player-facing errand. They do not replace militia.

One active errand per town, **2–5 minutes**, at most **3** on the map (one per town). Offer when the town is not fallen and attitude is not sour. Sour if the player kills a town animal during the errand; militia still defends. Attitude is a field on the town dict, saved with WorldState.

| Role | Behavior | Uses |
| --- | --- | --- |
| Scout | Walks toward the nearest ruin or a point 40–80 cells out and drops a timed minimap disc | Existing map. There is no fog-of-war renderer; do not add one. |
| Porter | Walks to the player once and grants a small stack of an existing material, then returns | Inventory |
| Hunter | Walks to the nearest passive animal and pings it | Marker only. Does not kill. The moral choice stays with the player. |
| Engineer | Restores town health with `TownDefenseManager.restore_health`, or tops up one damaged player barricade | No new geometry, so ramps are untouched |
| Runner | Shorter villager (×0.75 on the same prop) carries a one-line rumor to another town: relic direction or a crystal warning | The chat's message-runner. No age system and no separate child rig. |

Reuse `town_villager` brains and `WorldEntity`. Three extra bodies at most. They despawn when the timer ends or the town falls. Names and the rumor string are data on the errand, not a dialogue tree.

## Caves as mini dungeons

Noise caves already generate (`config/world_gen_config.gd` `cave_*`, `caves_enabled` true) and are **not meshed**. Leave that alone. A carved tunnel in the heightfield is the wrong tool (`set_voxel` does nothing, and `mesh_caves` would remesh the map).

A set piece is an authored interior, placed like a ruin:

- New `world/cave_setpiece_manager.gd`, same pattern as `world/ruin_manager.gd`: seeded, count **4**, min separation about 100, not inside towns, prefer forest and highland edges. No clusters this tier (clustered ruins should look authored; four singles already can).
- The overworld shows a mouth marker and a short stair of existing blocks. Walking in hides the heightfield shell over that small footprint and instances a room scene. Walking out unloads it. Only **one** interior loaded.
- Collision is the room mesh. The heightfield outside the footprint is unchanged, so overworld ramps stay valid.
- Lights: at most **8** `OmniLight3D` torches in the active room. They do not alter `terrain_sun_dir`. Bump `terrain_cave_fog` only while the interior is loaded, then restore 0.55.
- Camera: if the player is more than 3 layers below the local surface at the mouth, add a local offset so the bowl reads. Do not change the default overworld camera.
- Deep trenches dug in the open stay on the current camera. This offset is the dungeon only.

Four templates, 2–3 rooms, a clear in well under a minute:

1. Root cellar. Stair, one room, chest. A mite only if corruption is already in the chunk.
2. Vein chapel. Crystal hazard in the room using the existing crystal visual. Chest tends to the flow-anchor family.
3. Flooded cleft. Shallow water in the room only. Crystal does not cross it (premise). Chest on the dry ledge.
4. Barricade tomb. One breakable wall through the existing building path. Chest behind it.

Loot is player loot, and it is not the ruin-artifact rule. Ruin artifacts stay extra crystal spawn points (`IDEAS-from-chats.md`, General Gameplay). Cave chests use a new `RelicRegistry.cave_loot_pool()` beside `ruin_loot_pool()` (pathfinder charm, ruin seal, flow anchor, mason glove are the ruin pool today). One relic grant through the existing relic path, plus a small material stack. Chest opened flag lives on WorldState. No boss, no new enemy.

Local light and the room mesh are the "torches and underground readability" note from the Discord log. They are not a global cave renderer.

## Perf budget

Target: **16.6 ms/frame**, medium preset, render distance 2, standing in a forest grove in the rain. Tracked main-thread work stays inside the 8000 µs soft cap. New work is capped on its own so it cannot borrow from chunk upload or crystal dispatch.

| Work | Cap | Where |
| --- | --- | --- |
| Wind uniform | 50 µs | main, no particles script |
| Leaf GPU particles | 0 script | 128 medium / 48 low / 0 safe |
| Rain GPU particles | 0 script | 600 medium / 200 low / 0 safe |
| Weather director | 400 µs, 1 unit/frame | new `FrameBudgetScheduler` bucket `weather` |
| Storm inflow | inside the crystal tick | ×1.35, still ≤ 24 new cells |
| Cover + canopy MultiMesh | inside `feature_visual` 2000 µs, 1 chunk/frame | 128 cover + 32 canopy fill |
| Gameplay plants | existing feature path | ≤ 14 features per visible chunk |
| Animal migration | existing entity tick | retarget every 8 s, ≤ 128 entities |
| Volunteers | ≤ 3 `WorldEntity` | reuse villager |
| Dungeon | 0 until entered | 1 interior, ≤ 8 omni lights |
| Atlas variant | 0 on the main thread | hash while the worker builds the mesh |

Safe preset: wind, rain, cover fill, and dungeon lights off. Gameplay trees may stay at today's density on safe. Low: half the particle counts, cover instances 64, no canopy fill.

Pass line for the operator (this plan does not launch Godot): `CRYSTALSTORM_PROFILE_SECONDS=45` on `scripts/profile_gameplay.gd`, grove in view, rain forced. p95 frame ≤ 16.6 ms, `feature_visual` ≤ 2.0 ms, crystal new cells still ≤ 24/tick. Existing ramp and lighting checks stay green.

## Phases

Each phase ships alone and keeps the budget. Do not start a phase by editing ramps, `terrain_lighting.gd`, `voxel_scale`, or the default camera.

### Phase 1 — Scale plate

Put the table's meters into the plant boxes. Spawn a debug grove: the 22 m oak and one 40 m marker. Headless check asserts extents at `voxel_scale` 2.

Files: `helpers/voxel_prop_builder.gd`, `world/plantable_registry.gd`, `config/plantable_def.gd` (store target height and footprint; do not change absorb or denial), new `scripts/verify_vegetation_scale.gd`.

### Phase 2 — Counterpart silhouettes

Three tree crowns by biome, shorter grass and flowers, crystal forms at the new height. Billboards and voxel props both. Nearest-filter, no photo sources. Batch 1 paths only when the file exists.

Files: `helpers/voxel_prop_builder.gd`, `systems/game_visual_registry.gd`, `world/feature_visual_layer.gd`, `assets/art/vegetation/` (and `assets/art_batch1/vegetation/` only as twins).

### Phase 3 — Groves and visual fill

Gameplay groves plus the non-feature MultiMesh. Crystal in a chunk hides that chunk's fill.

Files: `world/vegetation_manager.gd`, `config/world_gen_config.gd` (grove knobs, not a higher attempt count), `world/feature_visual_layer.gd`, new `world/vegetation_cover.gd`, `config/performance_quality_config.gd` (instance caps), `helpers/visual_proximity.gd` if the 56-column band should also gate cover.

### Phase 4 — Atlas variants

Three tops per family, hash at mesh build, ramps match the landing, sides unchanged.

Files: `helpers/voxel_types.gd`, `chunks/chunk_mesh_buffer_builder.gd`, `chunks/chunk_view.gd` only if `_write_atlas_custom` must read the column hash, `assets/tiles/` author scripts and `Cube.png`, `docs/TEXTURE_MANIFEST.md` when cells exist. New `scripts/verify_atlas_variant_stable.gd` (same column after remesh; ramp top equals landing top).

### Phase 5 — Wind

Wind field, plant sway shader, leaf particles. Terrain shader untouched.

Files: new `world/wind_field.gd`, new `shaders/vegetation_sway.gdshader`, new `systems/ambient_particles.gd`, `systems/composition_root.gd` (parent the emitters), `config/performance_quality_config.gd`.

### Phase 6 — Rain and crystal storm

Director, particles, wet uniform, inflow pulse, `storm_mote`, audio slots.

Files: new `world/weather_director.gd`, `systems/ambient_particles.gd`, `systems/frame_budget_scheduler.gd`, `config/crystal_sim_config.gd` or the small multiplier site in `crystal/crystal_manager.gd`, `crystal/crystal_simulation.gd` only for the clamped multiplier, `config/audio_manifest.gd`, `assets/audio/SOUNDS_NEEDED.md`, `systems/save_schema.gd` only if the phase must persist and unknown keys are dropped. WorldState export/import on `world/world_state.gd`.

### Phase 7 — Wildlife leaves

Migration home. No new species and no higher caps.

Files: `entities/entity_brain.gd`, `entities/entity_navigation.gd`, `config/entity_brain_config.gd`, `entities/entity_manager.gd` (shared herd home). `crystal/crystal_corruption.gd` stays the conversion table.

### Phase 8 — Volunteers

Errands, attitude, save the active errand.

Files: new `world/town_volunteer_manager.gd`, `world/town_manager.gd`, `world/town_defense_manager.gd` (call `restore_health` only), `entities/entity_brain_registry.gd`, `world/world_state.gd`, the minimap ping site in `systems/topographical_map_builder.gd` or the existing map UI.

### Phase 9 — Cave set pieces and loot

Four mouths, one loaded interior, chest pool.

Files: new `world/cave_setpiece_manager.gd`, new scenes under `scenes/caves/`, `world/feature_registry.gd`, `relics/relic_registry.gd` (`cave_loot_pool`), `world/world_state.gd` (chest opened), `player/camera.gd` and `helpers/camera_cutaway.gd` for the mouth offset only, `helpers/terrain_lighting.gd` only to toggle `terrain_cave_fog` while an interior is loaded and to restore 0.55 on exit. Do not edit `chunks/chunk_manager.gd` `_emit_cave_faces` and do not set `mesh_caves`.

## Out of scope

- Changing `voxel_scale`, ramp geometry, the sun vector, the 0.68 side factor, or the default camera.
- `mesh_caves = true`, volumetric caves, dig brushes, storm terrain mutation, floating-island physics.
- New biomes, seasons, vegetation that spreads on its own, rivers that rewrite plants, fallen logs.
- Photoreal tiles, a bigger atlas grid, Starweave music, respawn rules, a new boss.
- More than 128 entities, more than 3 volunteer bodies, more than 4 dungeons, more than one loaded interior.
- A literal 63 m (×5) tree.
- Multiplayer. Weather and wind are local presentation. The storm inflow multiplier is sim and must be host-owned later; do not build that here.

## Operator check

After Phase 1, look at the grove next to a 2 m cliff and a ramp: the 22 m oak's trunk should read as one block wide, and grass should be shorter than the player (player body is 3.2 m). Pick 22 m or the 40 m marker before Phase 3 multiplies the forest. After Phase 6, stand in that grove in the rain and read the profiler. After Phase 9, enter one dungeon, take the chest, leave, and confirm the overworld ramp and the sun direction did not change.
