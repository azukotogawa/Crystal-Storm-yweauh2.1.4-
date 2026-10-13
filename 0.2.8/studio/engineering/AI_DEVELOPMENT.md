# AI development guide

## First principles

Read `AGENTS.md`, the affected scene, the live implementation, and its verification scripts before changing behavior. This repository has accumulated historical documents and in-progress work; code and the suite runner determine current behavior.

Make the smallest coherent change. Preserve unrelated worktree changes. Do not modify `manual_verification.md` to claim a human result, and do not use legacy scenes under `archive/legacy/` in production paths.

## Godot conventions

- Write Godot 4 GDScript only; use `@export`, `@onready`, and new signal syntax.
- Use the established 3D voxel path for production gameplay.
- Treat `scenes/main.tscn` as the production entry point.
- Keep deterministic behavior seed-derived where world generation/features are involved.
- Do not mutate the scene tree from chunk-generation workers; defer main-thread tree work.

## Safe change paths

- Terrain: route edits through `TerrainEdits`, `TerrainEditor`, `ChunkData`, and `ChunkManager`; account for chunk rebuilds and border neighbors.
- Movement/targeting: inspect `VoxelFloorProbe`, `ActionTargeting`, and relevant ramp/collision probes together.
- Crystal: preserve simulation caps, loaded-chunk policy, dirty/rebuild budgets, and generic fluid-engine contracts.
- Visuals: place output in the correct `WorldVisuals` layer and respect performance flags.
- Configuration: prefer `GameConfig` and resource/config classes over scattered magic values.
- Saves: update snapshot and restore paths together; maintain JSON-safe encoding.

## Verification discipline

Run the narrowest relevant `scripts/verify_*.gd` tests first, then `godot --headless -s scripts/run_all_verify.gd` for cross-system changes. Tests that require a display or human perception do not replace `manual_verification.md`. When adding a regression-prone behavior, add or extend a focused verification script and include it in `scripts/run_all_verify.sh` if it is a durable gate.

Use the in-game dev chat (`T`) for local commands such as status, presets, teleport, scenarios, item grants, and bug reports. Non-slash chat is a JSONL file bridge for an external assistant; it is not a networked AI service. `F3` toggles debug UI and `F11` captures a bug-report bundle.

### Headless probe mouse discipline

`SmokeProbeHelpers.position_player_for_forward_dig` warps the mouse onto the resolved target column so forward-fallback raycasts agree with the intended cell. Any probe that asserts **no-mouse** or **forward-fallback** behavior must call `SmokeProbeHelpers.clear_mouse_offscreen(player)` afterward (warps to `(-1e6, -1e6)`). The smoke dig path and sustained melee loop follow this pattern; co-located player/entity placement bypasses arc range and must not stand in for honest melee coverage.

## Review checklist

- Does the scene boot without `_ready` errors?
- Is worker/main-thread ownership correct?
- Are performance presets and SAFE mode still valid?
- Are new visual nodes cleaned up and layered correctly?
- Is the change covered by an appropriate automated probe and, when needed, manual verification?
- Did documentation remain consistent with the actual architecture?
