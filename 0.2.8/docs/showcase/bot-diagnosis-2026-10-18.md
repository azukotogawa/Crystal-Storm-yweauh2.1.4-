# Honest showcase bot diagnosis (2026-10-18)

Task `cs-bot-diag-01`. No gameplay code was changed. The bot still has no unrecorded win. `showcase-report-v3.md` says `20261018-win-unrecorded-r4b` was never run, and `.agent-checkpoint.md` has no `UNRECORDED WIN` after `cf63bde`.

The latest finished run is headless `20261018-win-unrecorded-r4` (log `tmp-cs-showcase-fix-win-r4-run1.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-win-unrecorded-r4\honest-bot-showcase.log`). It ends `HONEST BOT SHOWCASE FAIL` (log line 354). There is no `DEATH`, no `BOSS KILL`, no `CRYSTAL DESTROYED`, and no `win_screen`.

`cf63bde` only stops the farm clock from expiring during the walk home. It does not move the bot, and it was not played again.

## What the r4 log actually did

| Evidence | Where |
| --- | --- |
| Grove leg is 1045.7 columns | log line 308: `OK density_poi crystal_grove dist 1045.7 limit 143` |
| Treasure opens with two guardians, then level 2 | log lines 312–313 and 320 |
| Farm starts 1145 columns from the heart and logs the walk once | log lines 321–322 |
| Farm fails at level 2 with 50 XP | log line 324: `FAIL farm short level 2 earned 50` |
| Mite chapter is the whole 900 s farm budget | `chapters.txt` line 19: `combat_crystal_mite 153.815 1053.841` (900.026 s) |
| No `SHOWCASE farm home` anywhere in the log | the arrival print in `HonestFight._hunt` never ran |
| No `STUCK nav` line | stuck lines are printed in `HonestShowcase._finish_segment`; none appear between the farm fail and `SHOWCASE combat_crystal_mite fail` (log lines 324–325) |
| Later enemy chapters are `absent`; XP is still level 2 / 50 | log lines 326–335 |
| Dash is announced, then the harness times out | log lines 336–338: `SKILL dash`, `ERROR: showcase timed out`, `FAIL showcase timed out` |
| Dash chapter stays open until the frame cap | `chapters.txt` line 28: `skill_dash 1085.998 1694.940` (608.942 s). No `OK dash slide` and no `FAIL dash slide` |
| Sidecar check wants a second skill chapter that never opened | log lines 351–352 |
| Run result | log line 354 |

Walk speed is `move_speed` 16 world units/s. `voxel_scale` is 2, so that is 8 columns/s, and `MoveFeel.SPRINT_MULT` 1.62 makes a sprint about 13 columns/s. A straight sprint covers 1145 columns in about 90 s. The 900 s mite chapter with no arrival line means the walker was not closing that gap.

## Ranked root causes

### 1. The walk home never arrives, and nothing paths it

**File / function:** `0.2.8/scripts/honest_bot/honest_fight.gd` `HonestFight._seek_xp` (the block that prints `SHOWCASE farm walk home` and calls `HonestPlayBot.set_target` on `HonestRoster.pool_goal`). Steering is `0.2.8/scripts/honest_bot/honest_nav.gd` `choose`. The long leg is chosen by `0.2.8/scripts/honest_bot/honest_traversal.gd` `exploration_chain` (`LEG_CAP` 1500, comment that the near ring is about 1100 columns).

**Evidence:** log line 308 (grove 1045.7 columns, under the 1500 cap) then log lines 321–322 (`farm before crystal dist 1145`, `farm walk home dist 1145`). `chapters.txt` line 19 spends 900.026 s on `combat_crystal_mite`. The log never prints `SHOWCASE farm home`. Log lines 333–334 are still `LEVEL 2 xp 0 earned 50`. The same walk is 1148, 1156, and 1160 columns in `20261017-win-unrecorded-f`, `-e`, and `-d` (`honest-bot-showcase.log` around the `farm walk home` line). None of those print `farm home` either.

`choose` holds `move_forward` only when the facing dot is at least `ALIGN_DOT` (about 18 degrees). Otherwise it only rotates (`YAW_SPEED_DEG` 90). There is no route around a ridge, a river, or a border. `pool_goal` is one point 18 columns from the crystal, so the whole return is a single straight steer.

**Why `cf63bde` does not fix this:** `HonestFarm.farm_clock_open` (used from `HonestFight.tick`) stops `age` from rising while `dist > HOME_COLUMNS` (36). The r4 fail happened on `d76f814`, before that commit. After it, the bot still has to enter 36 columns before any farm XP. The unit log `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-win-unit-r4` only checks the clock predicate. Report v3 says the live rerun was not started.

**Proposed fix:** Give the return its own budget and a progress sample, still input-only. Reuse `HonestTraversal.leg_limit` (pace 8 columns/s, clamp 20–180 s) for the walk home, and print distance every time the sample moves. If the straight steer does not close at that pace, sidestep a wider arc and then pick the next dry column that reduces distance to `pool_goal`, instead of resetting onto the same point. Do not teleport. Farm XP only after `SHOWCASE farm home`.

**Test:** Extend `0.2.8/scripts/verify_honest_bot_nav.gd` `_check_stuck` (or a sibling in `verify_honest_bot_showcase.gd` `_check_farm`) so a body that is 1145 columns out, blocked on the forward column, and ticking `HonestPlayBot` must reduce distance to the heart. A frozen or sideways-only body must fail the walk with a distance line before `HonestFarm.FARM_LIMIT`. Assert `farm_clock_open(2, 1145)` stays false (that part already exists in `_check_farm`).

### 2. Stuck detection treats a slow miss as movement

**File / function:** `honest_nav.gd` `StuckWatch.sample` and `stuck_line`. Caller: `honest_play_bot.gd` `tick` and `set_target`. The farm walk sets `stuck_limit` back to 0 in `HonestFight._drop_site` and never raises it in the walk-home branch of `_seek_xp` (the treasure branch sets it to 12).

**Evidence:** r4 log has no `STUCK nav` line. `sample` only returns true when displacement over `STUCK_WINDOW_SEC` (1.25 s) is under `STUCK_MIN_COLUMNS` (0.35). The window then resets, so a 0.4-column slide away from the heart counts as progress. `HonestPlayBot.tick` calls `note_idle` whenever no move key is held, which is every frame `choose` is still rotating, and that clears the window. `set_target` calls `watch.reset()`, and `_seek_xp` calls `set_target` whenever the goal shifts by more than 2 columns. Three reports (`MAX_STUCK_REPORTS`) give up the current point; the walk immediately aims at the same `pool_goal` again.

The existing nav check only freezes the body at one coordinate (`verify_honest_bot_nav.gd` `_check_stuck`). A body that creeps sideways passes it. That is why a 900 s miss produced no stuck line.

**Proposed fix:** Measure progress toward the goal, not raw displacement. If distance to the target does not fall by `STUCK_MIN_COLUMNS` inside the window, append `stuck_line` even if the body slid. Do not `reset` the watch when `set_target` is the same home point. After `MAX_STUCK_REPORTS` on the walk home, aim at a side column that still reduces distance, and keep the stuck count.

**Test:** In `verify_honest_bot_nav.gd`, tick a body that moves 0.5 columns perpendicular to a 1145-column goal for 20 windows. Require a `STUCK nav` line and `gave_up`. The frozen-body case that already passes must stay.

### 3. Shard-tyrant leash is 22 columns from the den, and the bot dodges the body

**File / function:** Game latch is `0.2.8/entities/crystal_enemy.gd` `_refresh_guardian_aggro` (`GUARDIAN_AGGRO_COLUMNS` 14, `GUARDIAN_LEASH_COLUMNS` 22, both versus `_heart_cell()`, the den). Bot dodge is `0.2.8/scripts/honest_bot/honest_hazard.gd` `leash_bubbles` / `leash_step` (`LEASH_CLEAR` 24 from the body) and `guardian_bubbles` (`TRAVEL_SKIRT` 16 from the body). The walk calls them from `HonestFight._leave_leash` and `_slip` before it steers home. `entity_brain_registry.gd` also gives the shard tyrant (`spawn_elite`) `chase_distance` 14; the latch that keeps it hostile is the 22-column den test, not that chase field.

**Evidence:** `20261017-win-unrecorded-e\honest-bot-showcase.log` lines 321–326: `SHOWCASE farm walk home dist 1156`, then `boss_telegraph`, `boss_slam`, `player_hurt`. The `-d` log (lines 321–325) and the `-c` log (lines 320–326) print the same slam on a 1160-column walk home. Checkpoint 2026-10-17 01:32 records the 22-column den latch. r4 itself has no slam line; the miss on r4 is cause 1. The slam runs show the walk is also intercepted when a tyrant is already hostile.

A body-centered 24-column bubble cannot be escaped while the tyrant is chasing: the body stays near the player, `dodge_point` keeps replacing `pool_goal`, and `set_target` clears the stuck watch (cause 2). The den latch drops only after the player is more than 22 columns from the tyrant's heart. Grove aggro is the same 14-column den test. The grove chapter is the long trip (log line 308); the 14-column bubble is what grabs a guardian whose den the route stands inside. r4's treasure line (log line 312) spawned two guardians at the chest the bot had just opened.

**Proposed fix:** Build the leash bubble from the den heart (`_heart_cell` / brain home), using the game's 22-column drop and 14-column latch, not 24 columns around the chasing body. While the player is inside that den leash, steer to the first column outside 22 on the way toward `pool_goal`, then resume the walk. Do not fight `spawn_elite` on the way home (the farm already skips them in `prefer_kind`). Keep slam-ring dodges (`hard` bubbles) as they are.

**Test:** A headless check in `verify_honest_bot_showcase.gd` `_check_hazard`: a tyrant body 2 columns from the player whose den heart is 30 columns away must not make `leash_step` steal the home goal. The same body with the player 10 columns from the den must dodge until the stand is past 22 from the den. Assert the radii match `CrystalEnemy.GUARDIAN_AGGRO_COLUMNS` and `GUARDIAN_LEASH_COLUMNS`.

### 4. A failed farm still opens dash, and dash spins until the frame cap

**File / function:** `honest_showcase.gd` `_finish_segment` sets `failed` but only stops the route when the segment is `crystal`, `boss`, or `win_screen`. `honest_skill_cast.gd` `_settle` prints `SKILL dash` and sets `phase` to `pause`. `_pause` then sets `phase` to `_armed_phase()`, which for dash is `clear`. `_clear` sends it back to `pause` when `pos.distance_to(origin) >= 18` and `tries == 0`. The harness cap is `verify_honest_bot_showcase.gd` `_check_live` (`LIVE_FRAMES` 180000, then `_fail("showcase timed out")`).

**Evidence:** log lines 334–338: `FAIL xp level 2 earned 50`, `SHOWCASE xp_level fail`, `SKILL dash`, `FAIL showcase timed out`. `chapters.txt` line 28 stays on `skill_dash` for 608.942 s. There is no `OK dash slide` and no `FAIL dash slide`, so `_watch` never ran. The player was still far from the heart (no `farm home` line), which is exactly the `_clear` condition. `pool_goal` stands at 18 columns, and the condition is `>= 18`, so a walk that did arrive on the stand point would spin the same way. Log lines 351–352 fail the sidecar because `skill_ground_slam` never opened. Crystal, boss, and win are absent from `chapters.txt`.

**Proposed fix:** In `_clear`, "already far enough" must advance to `pause` only once, or straight to the fire phase, and must not be re-entered from `_pause`. If the stand is the 18-column farm point, treat that as ready to cast. If `xp_level` failed, keep playing (death is still the only loss) but do not leave `skill_dash` open with no exit: return `fail` once the cast cannot start, so the frame cap is not the dash result. Do not grant a skill point.

**Test:** In `verify_honest_bot_showcase.gd` `_check_skill_pad`, tick `HonestSkillCast` at 1145 columns from the origin with dash already unlocked. Within 3 s of simulated steps the phase must reach `fire` or the tick must return `fail`. It must not still be alternating `pause` and `clear`. A second case at exactly 18 columns must do the same.

### 5. The farm clock was the r4 exit, and it is already paused

**File / function:** `honest_farm.gd` `farm_clock_open` and `FARM_LIMIT` (900). `honest_fight.gd` `tick` adds `age` only when that function is true. `honest_fight.gd` `_hunt` prints `FAIL farm short` when `age >= FARM_LIMIT`, and resets `age` when `_home_logged` becomes `_home_arrived`.

**Evidence:** log line 322 then log line 324, with the mite row on `chapters.txt` line 19 equal to 900 s. That is the clock, not a death. `cf63bde` ("Pause the showcase farm clock until the walk home arrives") is the change. `_check_farm` already rejects `farm_clock_open(2, 1145)`. It is not a live win. Leaving the clock paused while cause 1 remains means the next run sits in `combat_crystal_mite` until `LIVE_FRAMES` instead of failing at 900 s. That is better telemetry, not a win.

**Proposed fix:** Keep the pause. Do not raise `FARM_LIMIT` to hide the walk. The walk budget in cause 1 is the missing piece.

**Test:** The existing `_check_farm` assertions on `farm_clock_open`. Add the arrival assertion from cause 1 so a green unit check cannot be read as a win.

## What is not the cause

- The r4 run did not die. Log line 354 is a showcase fail. Telemetry `20261018-win-unrecorded-r4\telemetry\1792354609-e222202b.json` records 0 deaths and 50 XP, and its `elapsed_msec` stops near the level-up, so the log and `chapters.txt` are the end of the run.
- Night, torch, day-night, and glow are `absent` in this log (lines 288–291 and 318). They are closed chapters. They are not why the farm or the dash failed.
- `dig_tool` and `structure_place` passed (log lines 294–307).

## Helper inventory

Reuse these. Do not add a second walker, a second stuck watch, or a second leash.

### `0.2.8/scripts/honest_bot/`

| Module | Role |
| --- | --- |
| `honest_input.gd` | Presses and releases actions, aims the mouse at a column, spaces presses when `pace_presses` is on. |
| `honest_pace.gd` | Reads `config/default_game_feel.tres` for wind-up, banner, and the 4 s chapter floor. |
| `honest_nav.gd` | Camera-relative `choose`, `face_action`, and `StuckWatch`. The only steering math. |
| `honest_play_bot.gd` | Holds a target, calls `choose`, nudges, and gives up after stuck reports. The only body driver. |
| `honest_hazard.gd` | Burn depth, slam rings, and the body leash. Should be the only dodge. |
| `honest_traversal.gd` | Poi / treasure / landmark chain, leg cap, `leg_limit`, `approach`. |
| `honest_route.gd` | Parses the JSON block in `docs/showcase/ROUTE.md`. |
| `honest_roster.gd` | Enemy order, `pool_goal`, hunt timers. `SCAN_COLUMNS` is 32. |
| `honest_farm.gd` | XP ready (level 3, 191), home radius 36, farm clock, treasure pick. No movement. |
| `honest_fight.gd` | Live farm, hunt, chip, and walk home. Owns one `HonestPlayBot`. |
| `honest_combat.gd` | Older short fight (engage 2.4, retreat at 30% HP) with its own `HonestPlayBot`. |
| `honest_crystal.gd` | Heart HP and boss priority. Drives `honest_combat.gd`, not `honest_fight.gd`. |
| `honest_showcase_finale.gd` | Crystal, boss, and win segments. Wraps `honest_crystal.gd` and has a second leash (`LEASH_COLUMNS` 16). |
| `honest_skill_cast.gd` | Skill-tree keys and the dash / slam / pulse / wall casts. |
| `honest_progress.gd` | Separate skill-point spender used by the phased bot run, not by the showcase. |
| `honest_build.gd` | Dig and blueprint place for the showcase. |
| `honest_chapters.gd` | On-screen clock and `chapters.txt` / `chapters.json`. |
| `honest_showcase.gd` | Route player. One segment at a time. |
| `honest_showcase_hud.gd` | Chapter label and timer. |

### `verify_honest_bot_*.gd`

| Script | Role |
| --- | --- |
| `verify_honest_bot_nav.gd` | Formula, arrive, nudge, frozen stuck, and a short live walk. |
| `verify_honest_bot_combat.gd` | `honest_combat.gd` nearest, engage, retreat, kill. Copies `_integrate` instead of calling `HonestPlayBot` only. |
| `verify_honest_bot_crystal.gd` | `honest_crystal.gd` walk, chip, boss priority. Another `_integrate`. |
| `verify_honest_bot_progress.gd` | `honest_progress.gd` skill order. No world walk. |
| `verify_honest_bot_run.gd` | Phased live run: nav, then `honest_combat`, then `honest_progress`, then `honest_crystal`. Not the showcase route. |
| `verify_honest_bot_showcase.gd` | Route unit checks plus the live showcase (`_check_live`, `LIVE_FRAMES`). This is the run that printed the r4 fail. |

`cs-verify.sh` `bot-showcase` is the wrapper that launches `verify_honest_bot_showcase.gd`. New play-harness checks should be cases on that script, not a new runner.

### Overlap to collapse

- Two fighters: `honest_fight.gd` (showcase farm and hunt) and `honest_combat.gd` (phased run and `honest_crystal.gd`). Keep `honest_play_bot.gd` as the walker. Point the crystal and finale segments at `honest_fight.gd`, or make `honest_combat.gd` a thin target picker that fight already has (`pick_seek`).
- Two leashes: `honest_hazard.gd` `LEASH_CLEAR` 24 from the body, and `honest_showcase_finale.gd` `LEASH_COLUMNS` 16. One function should read `CrystalEnemy.GUARDIAN_LEASH_COLUMNS` (22) and `GUARDIAN_AGGRO_COLUMNS` (14) from the den heart.
- Stuck handling is split across `StuckWatch`, `HonestPlayBot.tick`, `HonestFight._recover` (one `unstuck` pulse), and `HonestShowcase._pulse_unstuck`. Reports and the sidestep belong in `StuckWatch` only.
- `verify_honest_bot_combat.gd`, `verify_honest_bot_crystal.gd`, and `verify_honest_bot_run.gd` each reimplement a tick loop. They should call `HonestPlayBot.tick`.
- `honest_progress.gd` and `honest_skill_cast.gd` both spend the same tree. The showcase should keep `honest_skill_cast.gd`. The phased run should call that spender instead of a second key list.
- `honest_roster.gd` `pick` and `honest_farm.gd` `pick_seek` both rank enemies. One rank function.

## Still open after this note

A live unrecorded showcase that prints `SHOWCASE farm home`, then a boss kill and the win screen. `cf63bde` is not that run. Do not record a movie until that log exists.

## cs-bot-win-run-02 (2026-10-18 18:16)

Headless `20261018-cs-bot-win-run-02` on HEAD `7131179` (tee `tmp-cs-bot-win-run-02-1.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-cs-bot-win-run-02\honest-bot-showcase.log`). Start `2026-10-18T18:11:35-07:00`, `# exit=0 end=2026-10-18T18:16:50-07:00`. Wrapper printed `BOT SHOWCASE FAIL chapter movement under 4s` and `SHOWCASE_RC=1`. The script itself printed `HONEST BOT SHOWCASE FAIL`. No `DEATH`, no `BOSS KILL`, no `CRYSTAL DESTROYED`, no `win_screen`.

### Cause: the mite stall watched the route bot

`SHOWCASE farm home dist 36` is log line 560. The player was already about 19 columns from the heart. The phase log then repeats `SHOWCASE phase combat_crystal_mite` with target `86.2,-200.6` and empty inputs (log lines 561–612). That target is the route bot's leftover home, 1145 columns away, not the fight bot. `stuck-314831-1.txt` records position `938.55,-965.48`, target `86.19,-200.58`, distance `1145.2`, inputs empty, reason `no progress phase combat_crystal_mite frames 17211 wall 150.0s`. Log line 616 prints `HONEST BOT SHOWCASE FAIL stuck combat_crystal_mite` at dist 19.0 (distance to the origin, not to that target). The 150 s wall in `default_game_feel.tres` (`showcase_phase_wall_sec`) fired because distance to the route home never fell, while the fight was circling the heart.

`honest_showcase.gd` `_guard_phase` now reads the fight bot during `combat_crystal_mite`, and the finale fight bot during `crystal`, `boss`, and `win_screen`. A real stall still writes the stuck report on that driver.

### Wrapper: movement is 4.000 s

`chapters.txt` line 2 is `movement 4.017 8.017` (span 4.000). The game log line 298 is `SHOWCASE movement pass`. The wrapper awk used `d + 0 < 4`, so a binary 4.000 that prints as just under 4 aborted the verdict before the stuck line. The compare is now `d + 0.001 < 4`. A chapter of 3.5 s still fails.

## cs-bot-win-run-03 (2026-10-18 18:48)

Headless `20261018-cs-bot-win-run-03` on HEAD `9de7b13` (tee `tmp-cs-bot-win-run-03-1.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-cs-bot-win-run-03\honest-bot-showcase.log`). Start `2026-10-18T18:34:08-07:00`, `# exit=0 end=2026-10-18T18:48:59-07:00`. Wrapper printed `BOT SHOWCASE FAIL rc=0` and `SHOWCASE_RC=1`. The script printed `HONEST BOT SHOWCASE FAIL`. No `DEATH`, no `BOSS KILL`, no `CRYSTAL DESTROYED`, no `win_screen`.

`SHOWCASE farm home dist 36` happened, and the walk home logged progress from 1145 down to the heart. The stop is later: `HONEST BOT SHOWCASE FAIL stuck combat_crystal_mite pos 937.0,-966.9 target 938.9,-968.8 dist 21.2`. `stuck-890574-1.txt` records position `937.03,-966.94`, target `938.93,-968.78`, distance `2.6`, inputs `rotate_right,move_left,sprint`, reason `no progress phase combat_crystal_mite frames 19441 wall 150.0s`. The phase log alternates targets around `935.2,-965` and `939,-969` with `rotate_left,move_right` then `rotate_right,move_left`. That is two mite stands, not the route home from run 02. `prefer_locked` keeps the current foe id inside the scan radius, and `keep_stand` keeps a still-legal stand unless the new one is more than 0.35 columns closer.

## cs-bot-win-run-04 (2026-10-18 19:31)

Headless `20261018-cs-bot-win-run-04` on HEAD `29f776d` (tee `tmp-cs-bot-win-run-04-1.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-cs-bot-win-run-04\honest-bot-showcase.log`). Start `2026-10-18T19:22:00-07:00`, `# exit=0 end=2026-10-18T19:31:48-07:00`. Wrapper printed `BOT SHOWCASE FAIL rc=0` and `SHOWCASE_RC=1`. The script printed `HONEST BOT SHOWCASE FAIL`. No `DEATH`, no `BOSS KILL`, no `CRYSTAL DESTROYED`, no `win_screen`.

`SHOWCASE farm home dist 36` is early, and the walk home reaches `SHOWCASE farm home dist 35` at log line 561. The stop is the mite chapter. `stuck-587547-1.txt` records position `938.93,-965.01`, target `942.78,-968.72`, distance `5.3`, inputs `rotate_right,move_left,sprint`, reason `no progress phase combat_crystal_mite frames 15742 wall 150.0s`. Log lines 565–598 alternate targets around `935.3,-961` and `942.7,-968` while the player stays near `938.9,-965`. The held keys are `rotate_left,move_back,sprint` toward one goal and `rotate_right,move_forward,sprint` toward the other. `move_back` and that sprint pair come from `flee_toward` inside `_slip` / `_leave_leash`, not from the strike walk. The two dodge goals sit on opposite sides of the player, so each new bubble wins the penetration sort and the turn never finishes. `0568c70` still kept the foe id, but the hunt slip ran before `_fight`, so the stand lock never got a frame.

A crystal mite no longer takes that slip. A dodge that does run keeps its goal until the player arrives or the new goal is at least 1.5 columns closer (`keep_dodge`).

### Rerun on 6d196ef still stuck

Headless `20261018-cs-bot-win-run-04b` on HEAD `80b3c20` (tee `tmp-cs-bot-win-run-04-2.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-cs-bot-win-run-04b\honest-bot-showcase.log`). Start `2026-10-18T19:39:48-07:00`, `# exit=0 end=2026-10-18T19:49:07-07:00`. Wrapper printed `BOT SHOWCASE FAIL rc=0` and `SHOWCASE_RC=1`. The script printed `HONEST BOT SHOWCASE FAIL stuck combat_crystal_mite pos 939.1,-965.0 target 935.3,-961.1 dist 18.3`. `stuck-558884-1.txt` is that report. The phase log still alternates `935.3,-961` and `942.x,-968.7` with `rotate_left,move_forward,sprint` and `rotate_right,move_back,sprint`. No `KILL`, no `BOSS KILL`, no win. `move_back` is still `flee_toward`, so a dodge path is still taking the mite frames. The unit check passed; this live path did not.

### Cause after 6d196ef

`6d196ef` skipped `_slip` only when the locked foe was a `crystal_mite`, and it cleared `_dodge` on every hunt frame before `_fight`. A non-mite inside 32 columns (or an empty pick that still called `_slip` / `_leave_leash`) still ran `flee_toward`. Clearing `_dodge` made `keep_dodge` take whichever bubble was deeper that frame, so the two goals around `935.3,-961` and `942,-968` swapped and the player stayed near `938.9,-965`.

Once the farm has arrived home and no mite kill is recorded, `orbits()` is false. Hunt, seek, site, and fight skips of `_slip` and `_leave_leash` stay off, including a stag or shard that is not a mite. A mite still never slips. The walk home, before arrival, still dodges. A saved dodge is cleared when the foe id changes, not every frame. Headless `CRYSTALSTORM_SHOWCASE_UNIT=1` on this change printed `HONEST BOT SHOWCASE UNIT OK` and `OK mite lock keeps one foe and one stand` (`tmp-cs-bot-win-run-04-unit2.log`).

### Live run after orbits() (2026-10-18 20:05)

Headless `20261018-cs-bot-win-run-04c` on HEAD `bf2c800` (tee `tmp-cs-bot-win-run-04-4.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-cs-bot-win-run-04c\honest-bot-showcase.log`). Start `2026-10-18T19:59:45-07:00`, `# exit=0 end=2026-10-18T20:05:49-07:00`. Wrapper printed `BOT SHOWCASE FAIL rc=0` and `SHOWCASE_RC=1`. The script printed `HONEST BOT SHOWCASE FAIL stuck combat_crystal_mite pos 939.0,-942.8 target 937.2,-941.8 dist 16.0`. `stuck-364093-1.txt` records position `938.98,-942.77`, target `937.18,-941.78`, distance `2.0`, inputs empty, reason `no progress phase combat_crystal_mite frames 5755 wall 150.0s`. No `KILL`, no `bow`, no `BOSS KILL`, no win. The dodge flip is gone. After `SHOWCASE farm home dist 36` the fight bot kept the walk target and released every key. Nothing inside 48 columns was chosen, and the pool hold stands still once the player is already inside 18 columns of the heart.

A mite kill that is still open now searches the sensed list out to `MITE_SEEK` (4096) before it gives up. If that list is empty and the player is still outside the clear rim, it walks inward with `stuck_limit` 24 instead of releasing input. The same unit check printed `HONEST BOT SHOWCASE UNIT OK` again, including the far-mite seek (`tmp-cs-bot-win-run-04-unit2.log`).

### Live run after the far seek (2026-10-18 20:17)

Headless `20261018-cs-bot-win-run-04d` on HEAD `f8a253a` (tee `tmp-cs-bot-win-run-04-6.log`, copy `D:\ARCHIVE\CrystalStorm\verify-evidence\20261018-cs-bot-win-run-04d\honest-bot-showcase.log`). Start `2026-10-18T20:10:59-07:00`, `# exit=0 end=2026-10-18T20:17:02-07:00`. Wrapper printed `BOT SHOWCASE FAIL rc=0` and `SHOWCASE_RC=1`. The script printed `HONEST BOT SHOWCASE FAIL stuck combat_crystal_mite pos 938.7,-942.6 target 937.2,-941.8 dist 16.3`. `stuck-362889-1.txt` records position `938.69,-942.58`, target `937.18,-941.79`, distance `1.7`, inputs empty, reason `no progress phase combat_crystal_mite frames 5558 wall 150.0s`. No `KILL`, no `bow`, no `BOSS KILL`, no win. The walk home still arrived. The target is the 18-column pool ring, and the player had already stepped inside it.

`MITE_SEEK` only ranks enemies that are already nodes. None were. The empty-list walk called `_clear_home`, which aims at that 18-column ring and treats a point already inside it as finished. Arrival (within about 2 columns of the ring) released every key. A mite spawns on crystal within 10 columns of the player, so standing on that ring never reaches the clear rim and never creates a foe.

The empty-list walk now uses `_rim_goal` at `HEART_STAND` (6 columns), and it still stops on the last cell before the burn. Headless `CRYSTALSTORM_SHOWCASE_UNIT=1` printed `HONEST BOT SHOWCASE UNIT OK` and `OK mite lock keeps one foe and one stand` (`tmp-cs-bot-win-run-04-unit3.log`).
