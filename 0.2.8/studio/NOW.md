# NOW

> **Before every task, read `studio/VISION.md`** (the Crystal Storm master vision).

## Playtest 2026-10-14 (0.3.0-nocomments)
Playtest 2026-10-14 (0.3.0-nocomments): Cole called it fantastic. Only issues: art design and sprite rigging. Next priority: character art plus rigging and animation (plan pending Cole's discussion).

## State
Foundational terrain/runtime bug pass is complete (ramps, input contract, water indent lids, dig-beside-water replace, feature-tile remesh).

Playable-slice focus: **combat fuels the maze** + **wet ground is a readable crystal brake**.

## This pass
- XP HUD: bar and level-up toast on the gameplay overlay; run summary prints level and XP
- Kill grants (stone/herb/wood) — combat buys walls
- Crystal on water: flattened "wet crawl" clusters + HUD `wet crawl` when the front sits on standing water
- Bank-to-water toasts as wet-ground routing, not a trench

## Remaining (highest value next)
1. Live window: kill toasts, water-replace texture, wet-crawl crystal on rivers.
2. Windowed art-voxel check (2026-10-15) passed for the player and the cube rigs (idle and walk, including corrupted forms). Town villager, origin warden, and spawn elite still use the old prop. Cube count 8 vs 16, and code grids vs `.vox`, stay open in `studio/QUESTIONS.md`. Evidence: `D:\ARCHIVE\CrystalStorm\verify-evidence\art-voxel`.
3. Known pre-existing suite flakes: terrain_build, terrain_feel, terrain_input_single, crystal_mesh_floor, building_sprint, chunk_atlas, gate_bridge_visual_identity, save_transaction, save_slot_main.

## Rules
- Expand existing systems before inventing new ones.
- Every change should make the maze/combat/crystal loop more readable or more consequential.
- Smallest relevant verification while iterating. Full suite once per completed task, before commit.
