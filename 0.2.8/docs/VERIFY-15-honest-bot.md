# Verify-15 — honest bot full run

Recorded playthrough after `61545c6` (the How to play panel is dismissed with two `pause` taps before the boot shot). No gameplay numbers were changed. The bot still only sends `Input.action_press`, `Input.action_release`, and `InputEventAction`.

## Evidence

`D:\ARCHIVE\CrystalStorm\verify-evidence\20261016-005507-bot-run\`

| File | What it shows |
| --- | --- |
| `honest-bot-run.mp4` | 4,593,301 bytes, 12.97 s, 1152×648, 30 fps. ffmpeg 9.0.2 from the AVI. |
| `contact-sheet.png` | 1,056,145 bytes, 16 frames from that mp4, timestamps 0.000 through 12.933. Loading, then the walk onto the purple pool. No How to play panel. |
| `steps/1_honest-bot-boot.png` | Stream ready, panel gone. The earlier run `20261016-004944-bot-run` still shows "How to play / Step 1 of 6" on this shot. |
| `steps/2_honest-bot-nav.png` | After the short walk. |
| `steps/3_honest-bot-combat.png` | No foe. |
| `steps/4_honest-bot-crystal-run.png` | Player on the purple pool, hammer raised, Crystal HP 500/500. |
| `steps/5_honest-bot-progress.png` | Same place. Skill tree never opened. Level still 1, XP bar empty. |
| `telemetry/1792137309-c71f8f58.json` | Flushed session. |
| `bot-report.md` | Phase table below. |
| `honest-bot-run.log` | `# exit=0` at 2026-10-16T00:55:30-07:00. `HONEST BOT RUN DONE`. No line starts with `FAIL`. No `STUCK`. |

`cs-verify.sh telemetry-summary` on that telemetry directory:

```
sessions: 1
deaths: 0
top_damage:
  (none)
damage_taken_sources:
  (none)
avg_time_to_kill_msec: n/a
time_to_kill:
  (none)
xp_per_minute: 0
xp_gained: 0
elapsed_msec: 20683
```

## Phases

From `bot-report.md` and the log:

- boot: reached — stream ready at 1008.50,-951.50, origin 952.00,-952.00
- nav: reached — moved 1.44 columns to 1007.11,-951.86
- combat: not-reached — no enemy within 32 columns
- crystal: failed — attacks did not chip; remaining 1.53 at 953.49,-952.36 hp 500.0/500.0 swings 12
- progress: not-reached — no skill point

`STOP live remaining 1.53 at 953.49,-952.36 hp 500.0/500.0 swings 12`

Result line: `failed at crystal: attacks did not chip; remaining 1.53 at 953.49,-952.36 hp 500.0/500.0 swings 12`

The command still passes. A failed phase is recorded and does not by itself fail `bot-run`.

## Where the bot fails, and why

**Crystal heart never loses HP.** The bot walks to the origin (about 56 columns from the stream-ready cell) and holds `attack` once it is inside 2.4 columns. It selects `hotbar_1` first, which is the wooden sword. Twelve swings left `crystal_health` at 500/500, so the boss never spawned. The boss watch starts a warden only when that heart is at or under 25% HP.

The sword does not strike the cell the bot is facing. `WeaponController._do_melee_attack` breaks crystal mass on `ActionTargeting.target_cell`, which is the mouse highlight, and `damage_spawn_at_world` uses that same cell. The bot is not allowed to move the mouse. This run's telemetry gained 0 XP, so the highlight was not even a crystal-mass cell.

Two earlier windowed runs show the split between mass and the heart. `20261016-004944-bot-run` gained 42 XP as three events of 14. A broken mass cell is 4 XP plus 10 XP, and the heart still read 500/500 (9 swings, remaining 1.97). `20261016-004519-bot-run` gained 70 XP, reached level 2, and still reported heart 500/500 (11 swings, remaining 1.97). A mass chip is not a heart chip unless the aimed cell is inside the sword's heart radius of the origin. None of the three recordings moved the heart.

Changing sword reach, heart HP, or the aim rule would be a balance change. Giving the bot a mouse motion would break the input-only rule. Neither was done.

**Progress never opens, because this run earned no XP.** Level 2 costs `round(50 * 1^1.5)` = 50 XP. With 0 XP the service has no skill point, and the run marks progress `not-reached` instead of failing the tree. The spend path itself works: `20261016-004519-bot-run` printed `SKILL dash` and `PHASE progress reached SKILL dash` after 70 XP. That run is why a later run with no XP is "not reached" rather than a broken `ui_accept`.

**Combat is not reached because the sense happens in the wrong place.** After the 5-second nav (it stops at 1.0 column of travel; this run moved 1.44), the bot looks once for a living `crystal_enemy` inside 32 columns. It is still next to the stream start, about 55 columns from the origin. Nothing is there. It does not look again on the crystal. No damage, no kill, no death. Telemetry matches that: deaths 0, no damage dealt, no time-to-kill.

**Cliffs are still unsolved, and this run did not hit one.** Navigation still sidesteps and jumps after 1.25 seconds of poor travel, then gives up on that target after three `STUCK` lines. The straight walk to this origin printed no `STUCK`.

**Dig, build, and the bag are not driven.** The crystal hammer (3×3 mass splash) starts in the bag, not on `hotbar_1`. The bot never opens the inventory.

## What was not changed

The only bot edit in this part is the earlier pause-toggle that closes How to play. The `20261016-005507-bot-run` boot shot and contact sheet show the panel gone. No weapon, XP, or crystal numbers were edited.
