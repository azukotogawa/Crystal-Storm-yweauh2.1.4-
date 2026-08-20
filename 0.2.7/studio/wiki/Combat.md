# Combat

## Current loop

Combat is centered on the player using hotbar-selected weapons/tools through `WeaponController`.

The current combat loop is:

1. Player selects a weapon/tool.
2. `ActionTargeting` resolves the intended forward/column target.
3. `WeaponController` performs melee or ranged attack.
4. `CombatHitResolver` finds `world_entity` and `crystal_enemy` targets.
5. Targets receive damage through `take_damage`.
6. Crystal spawn points can also be damaged by attacks near their world cell.
7. Destroying all crystal spawn points wins the run.

## Connected systems

- `Player` owns `WeaponController`.
- `Inventory` supplies active hotbar item.
- `ItemTypes` defines weapon/tool kind, damage, range, and cooldown.
- `CombatHitResolver` applies entity/enemy damage.
- `CrystalManager` routes spawn-point damage to `SpawnPointController`.
- `CombatVisualFeedback` listens to combat signals for VFX.
- `GameManager` ends the run when the player dies or all spawns are destroyed.

## Progression

Combat progression currently comes mainly from crystal absorption unlocking enemy types and from spawn-point destruction weakening crystal emission.

There is no complete combat reward loop yet. Killing regular enemies removes pressure, but does not clearly grant materials, relics, XP, score, unlocks, or phase rewards.

## Incomplete loops

- No enemy-kill reward economy.
- No ammo or ranged resource loop.
- No weapon upgrade path.
- No boss phase structure beyond spawn-point gating.
- No explicit wave completion/reward cycle.

## Isolated mechanics

- `CombatLog` records events, but does not feed progression.
- `RelicManager` can affect stats, but relic acquisition is not connected to combat.
- `herb` exists as a consumable item, but no combat-use loop is visible.

