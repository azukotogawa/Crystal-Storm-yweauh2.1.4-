# NOW

## State
Foundational terrain/runtime bug pass is complete (ramps, input contract, water indent lids, dig-beside-water replace, feature-tile remesh).

Playable-slice focus: **combat fuels the maze** + **wet ground is a readable crystal brake**.

## This pass
- Kill grants (stone/herb/wood) — combat buys walls
- Crystal on water: flattened "wet crawl" clusters + HUD `wet crawl` when the front sits on standing water
- Bank-to-water toasts as wet-ground routing, not a trench

## Remaining (highest value next)
1. Live window: kill toasts, water-replace texture, wet-crawl crystal on rivers.
2. Known pre-existing suite flakes: terrain_build, terrain_feel, terrain_input_single, crystal_mesh_floor, building_sprint, chunk_atlas, gate_bridge_visual_identity, save_transaction, save_slot_main.

## Rules
- Expand existing systems before inventing new ones.
- Every change should make the maze/combat/crystal loop more readable or more consequential.
- Smallest relevant verification while iterating. Full suite once per completed task, before commit.
