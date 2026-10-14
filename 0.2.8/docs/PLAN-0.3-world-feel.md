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
