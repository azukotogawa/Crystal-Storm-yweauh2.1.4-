# Current Alpha Brief

Status snapshot for the playable slice. Keep this short. Source: `NOW.md`, `SYSTEM_HANDOFF.md`, contracts, backlog.

## Goal

Stabilize the existing cross-slice so it survives live play. Do not add new systems or content architecture until the live slice is clean.

## Current state (as of latest handoff)

### Ramps
- Cardinal ramp: one-voxel footprint on the **landing** (higher) cell; approach cell stays normal floor.
- Corner ramp: diagonal half-block only when low cell has two equal-height plateau neighbors meeting at a corner. Not a V-shape.
- Geometry now uses terrain ArrayMesh triangles + unshaded hemisphere fill shaders.
- Collision walkable height interpolates the slope.
- Known issue: some generated corner cells on ruin/cliff steps still hard to read; mid-plateau corners clearer.

### Digging / terrain edit
- Edits go through `TerrainEdits` + `TerrainEditor` → adaptive rebuild ring (0 interior, 1 near chunk edge).
- Ordinary placement must **not** invent walls/bridges.
- Digging must affect only the intended region + required halo; no unrelated clearing.

### Building / removal
- Walls/bridges are WorldObjects (`raises_terrain=false`).
- LMB: always try structure remove first.
- RMB: place selected catalog item (Tab cycles: Fill, Ramp, Corner ramp, Wall, Gate, Bridge).
- Bridge walkable without a fill voxel.
- No unstack of supporting terrain on place/remove.

### Targeting / input
- WASD camera-relative, Space jump, Q/E yaw (`edge_scroll_enabled=false`).
- LMB = primary interaction/removal; RMB = placement; range 8 voxels.
- Sword attack must never dig or remove terrain/buildings.
- Forward fallback for dig/attack/build when mouse is unavailable.

### Water / crystal
- Channel water and crystal pressure exist and are contract-tested.
- Crystal cells/volume must be visible when present.
- Visual settling / frontier motion still needs human judgment (automated hole checks pass).

### Camera / movement
- Orthographic; yaw changes must keep WASD consistent with current camera.
- Live floor probe respects terrain edits without waiting for full remesh.

## Known failures / open visual checks

1. Human walk of mid-plateau generated corner ramp (next action from handoff).
2. Corner cell readability on ruin/cliff steps.
3. Crystal motion / checkerboard feel in real window (contracts pass; feel is human).
4. Any remaining P0/P1 gameplay-visible bugs found in live play.

## Explicitly not being worked on

- Frontend persistence / save UI polish
- Terrain art / texture atlas overhaul
- Full economy, crafting, weapon tiers, boss multi-phase
- Incremental mesh architecture (only after measured hitch)
- Underground/cave camera/occlusion
- Broad new content or systems

## Acceptance criteria (alpha truth)

A system is done only when **all** are true:

- Internal state correct
- Rendered representation matches camera (F4 alone is not enough)
- Collision / interaction correct
- Survives remesh / stream / reload where applicable
- A player can understand what happened

Headless suite pass is necessary but not sufficient. Live window verification is required for the items in `NOW.md`.

## Stop condition for any agent session

Report only:
- what changed
- what was live-verified
- what remains
- the single highest-value next step
