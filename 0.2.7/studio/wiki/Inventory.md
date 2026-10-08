# Inventory

## Current loop

Inventory supports hotbar and bag slots. Items can be added, consumed, moved, swapped, and serialized.

The current item loop is:

1. Player starts with a basic loadout.
2. Digging grants materials.
3. Materials are spent on walls, channels, and planting.
4. Hotbar item controls attack/tool/build behavior.

## Connected systems

- `Inventory` stores item stacks.
- `ItemTypes` defines built-in item categories and weapon/tool metadata.
- `WeaponController` reads the active hotbar item.
- `TerrainEditor` consumes materials for build/channel/plant actions.
- `Hotbar` and `InventoryPanel` present inventory state.
- `SaveGameService` persists inventory.

## Current item roles

- `wooden_sword`: melee combat.
- `stone_pick`: digging tool.
- `shortbow`: ranged combat.
- `stone`: material for walls/channels.
- `wood`: material/fallback for walls.
- `herb`: consumable that heals when used from the hotbar.
- `crystal_shard`: material dropped when the player breaks crystal.
- `spear`, `crystal_hammer`, `sling`, `crystal_bomb`: extra weapons. See `studio/wiki/Combat.md` for roles. There is no crafting bench; they enter through the start kit and enemy drops.
- `leather_armor`, `stone_plate`, `crystal_weave`: one worn armor id on `Inventory.armor_id`. The inventory panel shows that slot. Click an armor stack to wear it. The worn id is saved inside the inventory dict.

## Incomplete loops

- No crafting bench and no recipes.
- No vendor/town economy.
- No inventory-driven progression beyond basic build costs, armor, and kill drops.

## Isolated mechanics

Hotbar selection still drives tools and weapons. Armor is a separate worn slot, not a hotbar mode.

