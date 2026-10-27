# Living-force alignment

No design note in this repo uses the phrase "living force". Cole's direction is a **living landscape**: terrain, water, and crystal react, spread, settle, and push back, instead of a static grid edited one cell at a time. This page is that reading, what the code does after this pass, and what is still a follow-up.

Constants live on `world/living_force.gd` (`class_name LivingForce`). They are static vars so Cole can retune them without a second code path.

## What the design says

- The studio exists "to create a living world" (`studio/STUDIO_CONSTITUTION.md:9`). "The world should feel alive." (`studio/STUDIO_CONSTITUTION.md:247`). Terrain should influence gameplay (`studio/STUDIO_CONSTITUTION.md:245`).
- The fantasy is "turning a living landscape into a temporary advantage against a spreading natural disaster" (`studio/design/IDENTITY.md:5`). The world "is rendered as a 3D voxel-like heightfield, not a general editable volumetric voxel volume" (`studio/design/IDENTITY.md:22`).
- "Terrain is the player’s primary strategic weapon." Crystal "spreads across the landscape, pools over terrain, absorbs world features" (`studio/design/VISION.md:3`).
- "Building and digging must create understandable route and elevation consequences." "The crystal should be understood through terrain-aware movement, depth, spread limits, and visible coverage. Water/channels, elevation, vegetation, and player-made terrain are all implementation-level inputs" (`studio/design/PILLARS.md:3` and `:9`).
- Week plan: "Make the world feel alive" using vegetation, crystal growth/spread, water movement, terrain variation, and towns — "Use existing systems first" (`studio/WEEK_PLAN.md:25-32`). The world should not become uniform Minecraft cubes (`studio/WEEK_PLAN.md:34-35`).
- Premise: the maze buys time; deeper digs take longer (`prompts/premise:1-6`). "if it senses a wall it forcuses crystal buildup there" and "Digging if there is enough vertical buildup" (`prompts/premise:19-20`). "The crystal cannot absorb water in any form, only build over it" (`prompts/premise:22`).
- Gameplay today was specified as column edits: "This is not arbitrary full-volume block placement or destruction" (`studio/design/GAMEPLAY.md:9`).
- `LIVING_WORLD_REPORT.md` is a content slice (biome HUD, ruins, towns, wildlife). It is not a terrain-physics design. `LivingWorldDirector` stays that content layer.

## How the systems behave

Terrain is one height per column. `ChunkData.set_voxel` is a no-op. Dig lowers a column by one layer (`world/terrain_edits.gd` `dig`, stored floor −6). Gameplay stops around −4 layers (`world/terrain_editor.gd` `try_dig`, `min_h`). Walls are WorldObjects and do not raise the heightfield (`AGENTS.md` Building). State of the game recorded this limit directly: dig is "one layer per dig, column only", and "A dig brush that carves a volume would be a new editor" (`STATE_OF_THE_GAME.md:67-69` and `:200`).

Before this pass, `TerrainEditor.try_dig` edited the aimed column only. A dig beside a natural water tile did not open a hole: it stamped that cell into a water tile and did not region-flood neighbors (`try_dig` adjacent-water branch, `scripts/verify_dig_flood_water_block.gd`). `VoxelFluidService` is the only water renderer (flood body plus chunk-mesher lids). Its flood fills columns whose visual top is below a natural river/water/ocean waterline and orthogonally connected inside the dirty box (`fluids/voxel_fluid_service.gd` `_flood_body`).

Crystal is a sparse 2D depth pool (`CrystalFluidSim`). `set_depth` will not invent a cell from nothing. Buildings already slow flow (`BuildingRegistry.flow_resistance`). Digging did not add pressure, and crystal did not consume player walls. Towns, ruins, and animals are not player buildings.

Input stays the contract in `studio/INPUT_CONTRACT.md.txt`: WASD, Space, Q/E, combat never digs, interaction range 8 voxels (`player/action_targeting.gd` `INTERACTION_RANGE`).

## What this pass changes

Three reactions, plus the heightfield brush. Each is deterministic, saved with the existing overlay, and capped.

### 1. Dig brush (heightfield disk, not a voxel sphere)

`ChunkData.set_voxel` cannot carve a tunnel, so the brush is a cylinder in plan: columns with `dx² + dz² <= (radius − 1)²`, skipped when the surface is more than `radius` layers away from the aimed column (`LivingForce.footprint`). Radius 1 is only the aimed column and calls the existing `try_dig`, so the water-tile stamp and the single-cell feel stay. Radius 2 is the center and four orthogonal neighbours (5 columns). Radius 3 adds the chebyshev ring that still fits inside the disk (13 columns). Each column loses one layer per stroke.

Radius comes from the tool's `dig_radius` plus `LivingForce.session_radius_bias`, clamped to 1..3. `stone_pick` is 1 (`helpers/item_types.gd`). `[` and `]` change the bias while a dig tool is held. They are dev keys, not input-map actions (`studio/INPUT_CONTRACT.md.txt`). Combat weapons never enter `WeaponController._do_dig_attack`.

Edits go through `TerrainEdits.dig` inside one `WorldState` batch. `TerrainEditor._remesh_cells` invalidates every touched column, then calls `ChunkManager.flush_rebuild_pending` once. Debug counters `edit_flush_count` and `edit_flush_chunk_count` record that flush. Radius above 1 will not dig natural water, towns, ruins, animal spawns, or player structures (`LivingForce.is_protected_column`). Radius 1 keeps the older single-cell rules. Crystal features are not cleared. Cells outside 8 voxels are skipped; if the aimed cell is out of range the stroke fails. The player-unstuck probe is unchanged.

The block highlight keeps the single box at radius 1. At radius 2 or 3 it shows a pool of extra unshaded boxes (`player/target_highlight.gd`, `cast_shadow` off, shared material). `get_brush_footprint()` is the hook. That file is also being reworked elsewhere; this pass only adds the pool.

### 2. Settle

`LivingForce.settle_enabled` (default true). After a stroke, an orthogonal neighbour whose **height-delta** is at least `settle_trigger_layers` (2) above a dug cell drops one layer. Natural noise is ignored, so a cliff that was never edited does not collapse just for being steep. At most `settle_max_cells` (4) neighbours, one ring, no cascade. Player buildings, build tiles, and water sources are skipped. The first dig on a fresh column (delta −1 beside delta 0) does not slump. The second dig on that column does. Stored digs still stop at −6; the editor still stops the aimed column around −4 layers. Settle cells are not extra loot.

### 3. Water into a dug column

`LivingForce.water_inflow_enabled` (default true). Every dug column calls `VoxelFluidService.request_flow`, the only flow entry point. Water spreads into a dug column when its floor is below the neighbouring water top, or level with it when the column was dug. Flowed cells keep a level from 1 to 7 and render a water lid from the hole floor up to `floor + level/8 layer`. That lid is swimmable from half a layer deep and targeting treats it as water. Locked by `verify_water_same_layer_break.gd` and `verify_water_body.gd`.

### 4. Crystal pressure and pushback

`LivingForce.crystal_react_enabled` (default true). A dig adds `crystal_dig_pressure` (0.06) and a new wall adds `crystal_build_pressure` (0.10) to crystal cells that already have depth, inside `crystal_react_radius` (2), at most `crystal_pressure_cells_per_stroke` (4) cells. `CrystalManager.nudge_depth` refuses to seed a new cell.

`LivingForce.pushback_enabled` (default true). Player-built cells near depth of at least `pushback_depth` (0.75) accumulate `crystal_push` by `pushback_step` (0.34) on the feature, every `pushback_interval` (0.5 s). At `pushback_break` (1.0) the crystal consumes one build and does not refund it. At most one break and 8 checks per tick. Towns, ruins, and animals are never consumed. Progress is `crystal_push` / `crystal_push_armed` on the feature, so save/load keeps it. The watch is rebuilt once when the terrain editor is ready and when `SaveGameService` applies a world payload. It is not scanned every frame. The tick runs only while the watch is non-empty.

About three ticks (about 1.5 s) break a wall beside deep crystal. That may be fast. Cole should retune `pushback_step`, `pushback_break`, and `pushback_interval`.

## Constants (defaults)

| Name | Default | Role |
| --- | --- | --- |
| `BRUSH_RADIUS_DEFAULT` / `BRUSH_RADIUS_MAX` | 1 / 3 | Clamp |
| `session_radius_bias` | 0 | `[` / `]` session add |
| `settle_enabled` | true | Rim slump |
| `settle_trigger_layers` | 2 | Delta gap that slumps |
| `settle_max_cells` | 4 | Cap per stroke |
| `water_inflow_enabled` | true | Dug columns call `request_flow` |
| `crystal_react_enabled` | true | Pressure on existing depth |
| `crystal_react_radius` | 2 | Chebyshev |
| `crystal_dig_pressure` | 0.06 | Per dug stroke |
| `crystal_build_pressure` | 0.10 | Per new wall |
| `crystal_pressure_cells_per_stroke` | 4 | Cap |
| `pushback_enabled` | true | Consume player builds |
| `pushback_depth` | 0.75 | Crystal must be this deep |
| `pushback_step` | 0.34 | Added each tick |
| `pushback_break` | 1.0 | Break threshold |
| `pushback_max_per_tick` | 1 | One structure |
| `pushback_checks_per_tick` | 8 | Watch cap |
| `pushback_interval` | 0.5 | Seconds |

`LivingForce.reset_session()` clears the bias and the watch. Tests call it. The terrain editor does not, so a running session keeps the bias.

## Gaps, in priority order

Shipped here: the disk brush, rim settle, river inflow on a wider dig, crystal pressure, and crystal pushback on player builds.

Left for Cole:

1. Freeform 3D tunnels. The mesh is still a heightfield. A real sphere would need `set_voxel` to store a volume.
2. Natural-noise cliffs collapsing on their own. Settle only looks at edit deltas, on purpose, so ramp and cliff tests stay put until the player digs a 2-layer contrast.
3. One merged fluid for crystal and water. The state-of-the-game note still treats that as a separate cut.
4. Crystal rewriting the heightmap. It still clears plants, farmland, animals, and ruins, and now consumes player builds, but it does not carve stone.
5. Player-authored ramps. Auto ramps on natural steps stay as they are. Ramp geometry was not touched.
6. Player channels as flood sources. Inflow uses natural river/water/ocean tiles only, matching `VoxelFluidService`.
7. Radius-1 digs beside a river still stamp a water tile. Widening that into a hole would break `verify_dig_flood_water_block.gd`.
8. Pushback timing. 1.5 s to eat a wall is a starting point, not a feel pass.
9. Loot. Each dug brush column still grants one material. A radius-3 stroke can grant about 13. Not capped, so Cole can see the rate.
10. A stronger pick. Only `dig_radius` was added. No new art. Brackets raise the session bias until an item ships with `dig_radius` 2 or 3.
11. Vegetation, towns, and wildlife already react through `LivingWorldDirector`. This pass does not add a second life sim.

## Perf

A stroke touches at most about 13 columns, one world-state batch, one mesh flush, and at most one water recompute. Settle adds at most 4 extra digs in that same batch. Crystal work is a capped neighbourhood read, not a new sim. Pushback does nothing while the watch is empty, and does not search the scene tree in that case. Highlight extras update when the cell or radius changes, and stay hidden at radius 1. No new lights. New highlight boxes use `SHADOW_CASTING_SETTING_OFF` and the existing unshaded material.
