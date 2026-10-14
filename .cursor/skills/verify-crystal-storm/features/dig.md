# Dig terrain

With a pickaxe, attacking a block lowers that column by one layer; the chunk mesh updates so the hole is visible and walkable ramps form at the edges. Only pickaxes/block-breaking tools break blocks (sword must not subtract terrain).

## Sub-features

- `dig-delta` a dig lowers the column by exactly one layer height.
- `dig-surface` edited surface is below natural.
- `dig-mesh` live chunk mesh `surface_y` matches the edit (smoke).
- `dig-sword-guard` swords never dig.

## How to get to it (user POV)

- Hold the pickaxe, aim at a block in range, left-click (`attack`).

## Driving it with cs-verify.sh

Preconditions:

- `doctor` OK, `quick` OK.

- **Rule check.** Run `bash $S feature dig`. `OK terrain dig delta=-<layer>`, `OK dig lowers surface natural=… edited=…`, `OK concave walkable=…`, marker `All terrain dig tests OK`.
- **Live dig.** Run `bash $S launch 8`. `**Dig OK**: WeaponController column (x,z) 8.00→6.00 delta=-2.00; chunk mesh surface_y=6.00`.
- **Sword guard.** Not in the helper map yet: `godot --headless --path 0.2.8 -s res://scripts/verify_sword_no_terrain_subtract.gd` (with `PATH` set as in SKILL.md), exit 0.

## Gotchas

- The rule suite exercises `world/terrain_edits.gd` directly; only the smoke Dig line proves the player path.
- An earlier VERIFY.md run (09:04) recorded `Dig FAIL delta=0.00`; the 20:35 run shows Dig OK. Check the line every time.
