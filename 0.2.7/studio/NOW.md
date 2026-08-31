# NOW

## State
Foundational terrain/runtime bug pass is complete (ramps, input contract, water indent lids, dig-beside-water replace, feature-tile remesh).

Playable-slice focus: **combat fuels the maze**. Player kills of crystal hostiles and wildlife grant materials (stone/herb/wood) with toasts; militia/villagers do not. Relics, ruins, and spawn destruction already existed — kills now connect combat to walls/trenches.

## This pass
- `CombatRewards` + crystal_enemy/world_entity player-kill grants
- Crystal enemy `killed` signal; spawner `enemy_killed`
- `verify_combat_rewards.gd` in the suite

## Remaining (highest value next)
1. Live play: confirm kill toasts + HUD relics + water-replace texture in a real window.
2. Crystal-water strategic read (player should feel why a trench/channel changes the purple front).
3. Known pre-existing suite flakes: terrain_build, terrain_feel, terrain_input_single, crystal_mesh_floor, building_sprint, chunk_atlas, gate_bridge_visual_identity, save_transaction, save_slot_main.

## Rules
- Expand existing systems before inventing new ones.
- Every change should make the maze/combat/crystal loop more readable or more consequential.
- Smallest relevant verification while iterating. Full suite once per completed task, before commit.
