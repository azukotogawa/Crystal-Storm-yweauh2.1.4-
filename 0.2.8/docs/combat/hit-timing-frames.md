# Hit timing at 60 fps

One frame is 1/60 second. A clock lasts as many frames as it takes to subtract 1/60 until the time left is zero. Wind-up frames are that count minus the frame the hit lands. Recovery frames are that count for the recovery clock. Active frames are that count for the hit-stop on the matching row in `config/default_game_feel.tres`, or 1 frame when the swing connects on a single animation sample and does not play a feel hit-stop.

The numbers below are read from `GameFeelConfig` and from `weapons/weapon_controller.gd` (draw, feel cast, and the animation clock). They are not a second tuning pass. The crystal hammer still waits `1.1 * 0.62` seconds (0.682 s) before the slam.

| Weapon | Wind-up frames | Active frames | Recovery frames |
| --- | --- | --- | --- |
| wooden_sword | 9 | 4 | 9 |
| spear | 18 | 1 | 14 |
| crystal_hammer | 40 | 1 | 25 |
| stone_pick | 12 | 5 | 9 |
| shortbow | 65 | 1 | 10 |
| sling | 55 | 1 | 7 |

`wooden_sword` goes through `sword_swing`. `ToolFeelCast` replaces that row's 0.22 s telegraph with the sword's impact sample, `0.32 * 0.5` = 0.16 s (9 wind-up frames, hit on frame 10). Active frames are `sword_swing` hit-stop, 0.06 s. Recovery frames are `sword_swing` recovery, 0.14 s. The 0.32 s cooldown is armed when the swing starts, so it is still running for 10 frames after the hit. That cooldown, not the 0.14 s recovery, is what blocks the next press.

`spear` is a thrust, so it does not take `sword_swing`. The hit is the animation sample `0.55 * 0.56` = 0.308 s (frame 19). The active window is that one frame. Recovery is the rest of the 0.55 s cooldown (14 frames).

`crystal_hammer` is a splash, so it does not take `sword_swing`. The pre-hit delay is the impact sample `1.1 * 0.62` = 0.682 s (frame 41). The active window is that one frame. Recovery is the rest of the 1.1 s cooldown (25 frames). That delay is unchanged.

`stone_pick` is the dig tool. The break waits on `multi_block_break`: telegraph 0.21 s (12 wind-up frames, hit on frame 13), hit-stop 0.08 s (5 active frames), recovery 0.14 s (9 frames). The pick's own pose sample (`0.16 * 0.45`) is not the hit.

`shortbow` and `sling` charge through `RangedAim` before the animation clock. A full draw holds `draw_sec` (0.7 s). The frame that reaches a full charge is also the first animation step, then the shot waits out the impact sample (`0.56 * 0.70` for the bow, `0.35 * 0.62` for the sling). Wind-up in the table is that whole wait. The active window is the one frame the projectile is spawned. Recovery is the rest of the weapon cooldown. A release before `draw_min_charge * draw_sec` (0.14 s) cancels and does not shoot. The `bow_shot` telegraph (0.40 s) is not this path: attack starts a draw, and the draw consumes the press before `bow_shot` can begin.
