# Player

## Current role

The player is the active agent for movement, terrain editing, combat, inventory use, and run win/loss interaction.

`Player` extends `CharacterBody3D`, but gameplay movement currently uses custom voxel-aware position/collision logic rather than standard `CharacterBody3D.move_and_slide` motion.

## Current loop

1. Player moves through streamed terrain.
2. Camera rotates/zooms around an isometric view.
3. Targeting resolves the intended action cell.
4. Hotbar item determines attack/build/dig behavior.
5. Player digs, builds, channels, plants, or attacks.
6. Crystal/enemies/towns update run pressure.
7. Player wins by destroying all crystal spawns or loses by death/overrun/town fall.

## Connected systems

- `VoxelFloorProbe` samples walkable terrain, ramps, caves, and crystal height.
- `WeaponController` owns action execution.
- `Inventory` stores hotbar and bag slots.
- `StatComponent` supplies movement, defense, dig/build modifiers, and crystal resistance.
- `RelicManager` can apply stat modifiers.
- `Camera3D` controls isometric movement orientation.
- `TargetHighlight` provides action preview feedback.
- `GameManager` observes player death.

## Progression

The player has stat and relic support, but few complete progression sources. Starting equipment and gathered materials define most current player capability.

## Incomplete loops

- No full equipment upgrade path.
- No clear relic acquisition path.
- No consumable-use loop.
- No explicit player leveling or skill progression.
- No strong post-objective reward flow.

