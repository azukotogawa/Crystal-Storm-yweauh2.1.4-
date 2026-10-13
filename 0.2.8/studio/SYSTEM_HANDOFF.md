# System handoff

## Current task
Alpha integration: building input, ramps, lighting, camera. No frontend persistence / terrain art.

## Changed IDs/files
- `building/building_registry.gd` — walls/bridge `raises_terrain=false`
- `world/terrain_editor.gd` — WorldObject-only place/remove; no unstack of supporting terrain
- `chunks/chunk_data.gd` — do not retile floor from build_tile unless height actually changed
- `weapons/weapon_controller.gd` — LMB always tries structure remove first
- `player/action_targeting.gd` — bridge walkable without a fill voxel
- `player/camera.gd` — `edge_scroll_enabled=false`; Q/E yaw
- `shaders/ChunkSurfaceMesh.gdshader`, `ChunkView.gdshader`, `ChunkRamp.gdshader` — unshaded hemisphere fill
- `helpers/chunk_surface_mesh_builder.gd` — corner half-block: slope triangle + low floor triangle
- `studio/PLAYTEST_VISUAL_CONTRACT.md`

## Screenshots
`C:\Users\cwith\AppData\Local\Temp\grok-goal-961aca94c53e\implementer\`
- `natural_cardinal_36_14.png` / `natural_approach_37_14.png` / `natural_corner_47_-3.png`
- `build_wall_-12_8.png` (WorldObject, Δh=0) / `build_removed_-12_8.png`

## Known problems
Corner cell (47,-3) still sits on a ruin/cliff step; a nearby dark diamond may be a cliff lip, not a missing floor triangle. Mid-plateau corners are easier to read.

## Next action
Human walk of a mid-plateau generated corner ramp. Do not start persistence or terrain-art.
