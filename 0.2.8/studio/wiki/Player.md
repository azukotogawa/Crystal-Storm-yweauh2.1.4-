# Player

## Current role

The player is the active agent for movement, terrain editing, combat, inventory use, and run win/loss interaction.

`Player` extends `CharacterBody3D`, but gameplay movement currently uses custom voxel-aware position/collision logic rather than standard `CharacterBody3D.move_and_slide` motion.

## Current loop

1. Player spawns on dry land near the corner crystal heart. Feet are placed on the rendered slab top (`surface + layer`). A low height hint must not treat the interior of that top voxel as a cave floor. Chunk streaming follows that column before the body is marked ready, then the player moves through streamed terrain.
2. Camera yaws with Q/E and pitches with Page Up, Page Down, or a middle-mouse drag. Pitch is clamped (about -78° to -18°) so the view does not go under the ground or straight down. Zoom is the mouse wheel. The default pitch keeps the old isometric offset. The pitch is stored in `PlayerSettings` (`camera_pitch_degrees`) and restored on the next boot, clamped to those limits. It is written when the tilt settles, not every frame.
3. Targeting resolves the intended action cell. A ray that just misses snaps to the nearest in-range cell within a fraction of a column. Exact hits stay on that cell. Reach stays 8 voxels. The highlight is one reused box (`TargetBox`) with a thick outline and a marker on the face the action will hit.
4. Hotbar item determines attack/build/dig behavior.
5. Player digs, builds, channels, plants, or attacks.
6. Crystal/enemies/towns update run pressure.
7. Player wins by destroying all crystal spawns, or loses by death or crystal coverage. A fallen town is a power-surge penalty, not a loss.
8. Jump is Space. Enter still confirms UI.

## Connected systems

- `VoxelFloorProbe` samples walkable terrain, ramps, caves, and crystal height.
- `WeaponController` owns action execution.
- `Inventory` stores hotbar and bag slots.
- `StatComponent` supplies movement, defense, dig/build modifiers, and crystal resistance.
- `RelicManager` can apply stat modifiers.
- `Camera3D` controls isometric movement orientation, pitch, and the cave cutaway uniforms.
- `TargetHighlight` provides action preview feedback (outline + target face).
- A fall or jump lands on the walkable feet height, so a step into the top slab does not count as standing inside it. Collision still allows a small sink for ramps; the landing check does not use that slack.
- Overlap with solid terrain lifts the player to `nearest_safe_stand`. V (`unstuck`) does the same on demand, with a short cooldown.
- `GameManager` observes player death and records the run summary.
- Settings, keybinds, the first-run tutorial, and UI scale live in `studio/wiki/UI.md`. Walk bob follows `Juice.walk_bob_allowed()` so Reduce motion can turn it off.

## Progression

The player has stat and relic support, but few complete progression sources. Starting equipment and gathered materials define most current player capability.

## Incomplete loops

- No full equipment upgrade path.
- Relics are gained by destroying crystal spawn points and by exploring ruins.
- No consumable-use loop.
- No explicit player leveling or skill progression.
- No strong post-objective reward flow.

