# Aim and combat feel checkpoint (run 4, branch cs-sonnet/aim off cs-sonnet/controls)

Cloud limits: `cs-verify.sh quick` cannot print QUICK OK here (import step fails in the stubbed-art tree), and bot scenarios cannot run. Each job is proved with headless verify scripts through a stub runner. `verify_multi_block_break` already failed before this run ("_try_dig_tool must resolve break cells toward the aim"); my assertions in it run and pass.

## cs-handfeel-01 pickaxe never breaks
- `stone_pick` durability 0 (unbreakable, same path as the hammer); `wear_tool` kept.
- `verify_multi_block_break.gd`: 80 swings of 3 cells never wear the pick and it stays in its slot.
- Q-061 added to QUESTIONS.md (wood+stone pick recipe alternative).
- Needs Dell: scenario `dig` (60 cells, pick still in hotbar), `build`. Cursor-aimed dig still goes through run 3's exposed-face pick unchanged.

## cs-aim-01 charge-shot launch
- New `weapons/ranged_aim.gd` (charge curve, cursor-ray launch direction, range sim). Config: `draw_sec`, `draw_min_charge`, `draw_min_speed`, `draw_max_speed`, `draw_curve` in `game_feel_config.gd` and the `.tres`.
- `weapon_controller.gd`: bow and sling hold to draw (`_begin_draw`/`_tick_draw`), string draw shown while held, release below min charge cancels with no ammo, cooldown or anim; release fires at `speed_for(charge)` along the cursor-plane direction. The cursor ground-point snap and XZ flatten for ranged were removed from `_aim_forward`. Bomb still uses its old lob path (not charged yet).
- `scripts/verify_ranged_aim.gd` passes (5 charge speeds increasing and within 1%, 6 launch directions within 2 degrees, range full > half > min, short draw keeps ammo and cooldown). `verify_held_item_use` updated to hold the bow (passes); `verify_item_animations`, `verify_hotbar_controls` pass.
- Needs Dell: scenario `combat` (has no bow step today). Q-062 about elevated targets.
- `cs-verify.sh quick` still cannot print QUICK OK in the cloud (import fails on stubbed art).

## cs-aim-02 hitbox hits
- New `systems/combat_hitbox.gd`: one sphere hitbox per enemy (`get_combat_center`, 0.65 x `get_combat_radius`, default 0.5) and an exact segment-sphere entry test.
- `projectile.gd`: entity hits are the first segment/hitbox intersection (contact point recorded in `last_hit`); terrain hits march the segment and bisect to the first solid sample, so walls and cliffs are hit on their face, not only from above. Arrows stick at contact, stones stop and drop there, bombs explode there. Projectile thickness is now 0.1 (bomb 0.3). No stop-at-cursor logic remains.
- `verify_ranged_aim.gd` extended and passes: contact within 0.1 of the hitbox surface for arrow, stone and bomb; arrow sticks at the wall face; a pass beside the hitbox records no hit; bomb explodes at the wall face. `verify_projectile` and `verify_combat_depth` still pass; `verify_cursor_aim` fails identically before this job.
- Needs Dell: scenario `combat`.

## cs-handfeel-03 mouse-aimed melee and dig
- Sword melee resolves the enemy whose hitbox is under the cursor ray (`CombatHitbox.pick_under_ray`, slack 0.4, within weapon range of the player) instead of the facing cone; with no mouse it falls back to the cone. Hammer and spear thrust keep their own paths (not part of this job). Dig and place already use run 3's exposed-face cursor pick, unchanged.
- `scripts/verify_melee_cursor.gd` passes (enemy beside and behind the player picked by cursor, empty ground and out-of-range enemy are not). `verify_combat_entity_hit` and `verify_held_item_use` still pass.
- Needs Dell: scenarios `combat`, `mite_fight`, `dig`.

## cs-handfeel-04 refuse use out of range
- Sword melee is refused before the swing when the cursor point (cursor ray on the attack-height plane) is beyond item range: no animation, no cooldown, toast "Out of range" plus a blocked marker (`_refuse_use`, `refused_count`). Bow and sling are never refused. Dig and place already refuse with no target (`_notify_terrain_fail`) but keep their tiny 0.035-0.04 s anti-spam cooldown; the highlight already shows blocked. Hammer and spear are not gated.
- `scripts/verify_use_refusal.gd` passes (cursor in/out of range, a refusal leaves cooldown and animation untouched, a bow release at a far cursor still fires). The refusal check calls `_refuse_use` directly because `_try_attack` needs a full Player.
- Needs Dell: new case in scenario `combat` (sword beyond range, then in range), `dig`, `build`.

## cs-handfeel-07 faster animations, longer melee range
- Cooldown/animation: sword 0.32, spear 0.55, shortbow 0.56, sling 0.35; hammer timings unchanged (locked, Q-063). Melee range floor `melee_min_range` 5.0 in `GameFeelConfig` (applied in `ItemTypes.get_def`); the 4.5 break/place reach is unchanged.
- `scripts/verify_weapon_speed.gd` passes; `verify_item_animations` updated to read the sword range from the item def and passes; `verify_held_item_use`, `verify_combat_entity_hit` still pass.
- Needs Dell: scenarios `combat`, `mite_fight` (log swing times and hit distance).

## Remaining (budget of 6 jobs reached)
cs-handfeel-06, cs-handfeel-05, cs-handfeel-13, cs-aim-03.
`cs-verify.sh quick` cannot print QUICK OK in the cloud (no godot on PATH, stubbed art/shaders) and no scenario was run. Pre-existing failures: verify_multi_block_break, verify_cursor_aim, verify_dig_brush, verify_stone_wall_live_place.
