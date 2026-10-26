# Multi-block brush

One brush for digging and building. No micro or macro modes for the player.

## What was already there

- `ItemTypes.BreakShape` with `break_cells` and `MULTI_BLOCK_BREAK` already drove a tier-based multi-block dig through `weapon_controller._try_dig_tool` and `TerrainEdits.dig_cells`.
- A separate `LivingForce` disk brush (radius, `[` and `]`, `try_dig_brush`) was left over from the earlier pivot.
- The micro/macro split was only environment variables (`CRYSTALSTORM_MICRO_TERRAIN`, `CRYSTALSTORM_MACRO_TERRAIN`) and `ChunkData.USE_MICRO_BRICKS`. There was no player-facing switch.
- Read: `docs/LIVING_FORCE_ALIGNMENT.md`, `STATE_OF_THE_GAME.md`, `studio/plans/2026-10-14-design-pivot.md`, decisions D-222 to D-224.
- `docs/design/balance-findings-2026-10-18.md` is not in the import. Only `balance-audit-input-2026-10-18.md` is. Costs here were set from the config defaults, not from that file.

## Decisions

1. One live system. The brush extends `ItemTypes.BreakShape` instead of adding a second shape type. The disk brush, the key polling for it, and the tier-based `break_cells_for` stay in place, unused by the live path.
2. Micro bricks off. `ChunkData.USE_MICRO_BRICKS = false`, and the micro env switches only act when it is true. The macro grid stays on, so terrain generation is unchanged. Legacy micro verify scripts set the flag true in `_init()`.
3. Shapes (`ItemTypes.BRUSH_ORDER`): Single, Line 3, Pad 3x3, Shaft 1x3, Cube 3x3x2. `[` and `]` (`brush_shrink`, `brush_grow`) step through the unlocked ones and show a toast.
4. Shapes follow each column's own surface. Dig goes down by layers from each column top. Place stacks up from each column top, one layer per block, at most 8 layers per column, never floating, never on water or protected columns, never on the player's own column.
5. Reach is 5 blocks (`brush_reach`), used for both the aim and the preview.
6. Unlocks come from mastery: blocks broken plus blocks placed this run. Thresholds are 0, 5, 20, 45, 80. No streaks, no timers, no loss when you stop. A toast tells you when a new brush opens.
7. Costs. Tool wear is one point per three blocks. A stroke adds a short cooldown per extra block, capped. Placing costs one stone per block (wood when stone runs out), and a stroke is trimmed to what you can pay for. The existing drop cap per swing is unchanged.
8. Feedback. Break and place show "Broke N blocks" and "Placed N blocks, spent N stone", with block effects capped per stroke.
9. Preview. Multi-block brushes draw one outline around the exposed faces of the planned cells (white to dig, blue to place, red when blocked). Edges shared by two faces on the same plane are dropped, so a pad shows its silhouette and not a grid. Single keeps the old marker.
10. Timings and tunables live in `config/game_feel_config.gd` and `config/default_game_feel.tres`: `brush_ids`, `brush_unlock_blocks`, `brush_reach`, `brush_block_sec`, `brush_time_cap_sec`, `brush_summary_sec`.

## Checks

- `scripts/verify_block_brush.gd`: shape sizes, wear, config, outline faces and edges, dig and place planning, micro off.
- `scripts/verify_multi_block_break.gd` and `verify_dig_brush.gd`: source checks updated to the new stroke path.
- Harness: `scenario multi_dig` and `scenario multi_build`, input only.

## Remaining

- New tool items and tiers that gate brush shapes (for example a mattock). Unlocks are mastery only for now.
- Wood and other materials in the place brush beyond the stone-then-wood rule.
- Brush sizes beyond the five shapes, and rotating a shape.
- Removing the dead disk brush and the legacy micro code. Nothing was deleted.
- Art pass for the outline and stroke effects in the real art set.
- Full-fidelity runs on the project machine with real art and audio. The checks here ran headless against stand-in art.
- `scenario build` fails the same way on the imported baseline when run with stand-in assets (stone is not spent), so it was not used as a signal.
