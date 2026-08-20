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
- `herb`: valid consumable item, but no visible use loop.

## Incomplete loops

- No crafting.
- No equipment tiers.
- No item drops from enemies.
- No vendor/town economy.
- No consumable activation path for herb.
- No inventory-driven progression beyond basic build costs.

## Isolated mechanics

Inventory is structurally ready for more item loops, but most current systems use it only for material counts and active weapon/tool selection.

