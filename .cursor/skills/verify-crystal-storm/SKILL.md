---
name: verify-crystal-storm
description: "Verify Crystal Storm (Godot 4.7 voxel game in 0.2.8/) the way a player would, headless from WSL on Cole's laptop: import/compile, boot res://scenes/main.tscn through the gameplay smoke probe, and drive mapped features (full map, water, save/continue, dig, world frontend) with their headless suites. Use before claiming any gameplay change works, or when the queue's QUICK_CHECK fails."
---

# Verify Crystal Storm

Godot 4.7 game, project dir `0.2.8/` (`project.godot` name `Crystalstorm`, main scene `res://scenes/frontend.tscn`, gameplay scene `res://scenes/main.tscn`). No npm/cargo/make: `godot --import` is the build, tests are headless `extends SceneTree` scripts in `0.2.8/scripts/`. The repo-root `VERIFY.md` is the long-form contract (markers, PASS/FAIL rules, release gate); this skill is the scripted path through it.

Everything goes through one helper, run from WSL at the repo root:

```bash
cd /mnt/c/Users/cwith/Crystal-Storm-yweauh2.1.4-
S=.cursor/skills/verify-crystal-storm/cs-verify.sh
export RUN_ID=my-check-$(date +%H%M%S)   # optional; groups evidence for one run
bash $S doctor           # read-only health check
bash $S quick            # import + stability + contracts  (~15 s) = QUICK_CHECK
bash $S launch 8         # headless boot of main.tscn + 8 s scripted play (~25 s)
bash $S bot              # honest-bot navigation on main.tscn (input only)
bash $S bot-combat      # honest-bot combat: nearest foe, sword, skills, retreat, kills, deaths
bash $S bot-progress    # honest-bot progression: kill XP, skill choice, telemetry XP rate
bash $S bot-crystal     # honest-bot crystal: walk to the crystal, attack, fight the boss
bash $S bot-run         # one live session: boot, nav, combat, progress, crystal; writes bot-report.md
bash $S bot-showcase    # honest-bot showcase: movement slice of ROUTE.md, timer, chapters sidecar
bash $S scenario dig    # play harness: seeded dig through the bot input layer
bash $S scenario build  # play harness: seeded stone wall through the same layer
bash $S scenario multi_dig    # unlock Line 3 by digging, then one stroke breaks 3 columns
bash $S scenario multi_build  # same unlock, then one stroke places 3 blocks and spends 3 stone
bash $S scenario break  # forced dig assertion; must print a stuck report and shot
bash $S scenario crystals    # find the heart, collect a shard, sword the heart
bash $S scenario corruption  # spread, burn after the warning, cleanse to a scar
bash $S scenario combat      # warned hit, sword, then Dash from a real skill point
bash $S scenario relic_esc   # relic offer stays up when Esc is pressed
bash $S scenario kite         # bow kite versus a melee foe, then the loop breaker. Does not boot the world.
bash $S record showcase # windowed >=1280x720 movie of that run, chapters, contact sheet
bash $S feature full-map # drive one mapped feature (names in features/README.md)
bash $S telemetry-summary path/to/session.json  # deaths, damage sources, avg time-to-kill, XP rate
bash $S record launch 2  # same as any mode, plus Godot --write-movie and an mp4
bash $S cleanup          # kill only our Godot pids, delete scratch, KEEP evidence
```

From a Windows shell (PowerShell eats `$`), put the commands in a `.sh` file and run `wsl -e bash /mnt/c/.../file.sh`.

## Launch

- Engine: `/home/cwith/csmerge-bin/godot` (console wrapper around `C:\Godot\Godot.exe`, converts `/mnt/x` paths, forwards `CRYSTALSTORM_*` and `APPDATA=D:\csmerge\appdata` so Cole's real saves are never touched). The helper prepends it to `PATH`. Never use `/home/cwith/bin/godot` (drops args, opens the editor).
- `launch [SEC]` runs `0.2.8/scripts/run_smoke_gameplay.sh`: instances production `main.tscn`, waits for player/chunks/terrain/world/visuals/crystals, then digs through `WeaponController`, spawns an entity, moves, jumps, swings. Ready = `Bootstrap OK` in the evidence file; pass = `SMOKE GAMEPLAY OK` and no `SMOKE GAMEPLAY FAILED`. A process exiting 137/134 after the marker is expected (`CRYSTALSTORM_PROBE_ABRUPT_EXIT=1`).
- Every launch starts from a fresh world (seeded bake radius 2, `CRYSTALSTORM_FULL_WORLD_BAKE=0`, `CRYSTALSTORM_BAKE_ON_NEW=0`, preset `medium`). No seed data needed.
- A windowed screenshot run exists (`scripts/display_gameplay_validation.gd`, see VERIFY.md section 4) but opens a window on Cole's desktop; do not run it unattended.
- Teardown: the probes quit themselves; `cleanup` kills any leftover pid we recorded.

## Doctor

`bash $S doctor` (read-only, ~1 s). Requires `OK godot wrapper`, `OK engine 4.7…`, `OK project 4.7`, then `DOCTOR OK`. It also prints branch/HEAD, `MemAvailable` and a count of Godot-like processes. The laptop has 7 GB RAM: if available memory is under ~2 GB or another agent's Godot is running, wait instead of stacking a second instance. Instances are isolated by `RUN_ID` scratch dirs, but `--import` writes the shared `0.2.8/.godot/` cache, so do not run two imports at once.

## Honest bot

`bash $S bot` runs `0.2.8/scripts/verify_honest_bot_nav.gd`. The bot under `0.2.8/scripts/honest_bot/` may only call `Input.action_press` / `Input.action_release` and `Input.parse_input_event` (`InputEventAction`). It does not teleport, grant XP, damage the crystal, or write world state. Navigation holds `rotate_left` / `rotate_right` until the camera yaw faces the target, then holds `move_forward`. If that column barely moves it also holds a strafe. After 1.25s with under 0.35 columns of travel it prints a `STUCK nav ...` line, sidesteps, and taps `jump`. Three stuck reports and it gives up on that target. Pass prints `HONEST BOT NAV OK`. A 137/134 exit after that marker is the abrupt probe quit. One line that starts with `FAIL` fails the command.

`bash $S bot-combat` runs `0.2.8/scripts/verify_honest_bot_combat.gd`. The same input driver aims at the nearest sensed foe (`crystal_enemy` columns, or a sense the probe passes in), pulses `hotbar_1` once so the sword is selected, then pulses `attack` and `skill_1` / `skill_2` / `skill_3` while inside 2.4 columns and facing. At 30% health or below it walks away and does not attack. A foe id that disappears prints `KILL <id>`. Health at or below zero prints `DEATH hp ...` once and releases every action. Pass prints `HONEST BOT COMBAT OK` plus at least one `KILL` line and one `DEATH` line. The live sword check is a real `WeaponController` cooldown after `attack`, not a direct damage call.

`bash $S bot-progress` runs `0.2.8/scripts/verify_honest_bot_progress.gd`. The same input driver levels only from kill tiers (`ProgressionService.xp_for_kill` and `xp_to_advance`). Mine, place, ruin, crystal, and non-hostile kills do not add XP and do not open the tree. A spare skill point pulses `skill_tree`, moves with `ui_down` / `ui_right`, and pulses `ui_accept` on the real skill-tree panel. The XP line is `DifficultyTelemetry.xp_snapshot()`, not a second timer. Pass prints `HONEST BOT PROGRESS OK` plus a `LEVEL` line, a `SKILL` line, and an `XP_RATE` line. One line that starts with `FAIL` fails the command. This part does not boot `main.tscn`.

`bash $S bot-crystal` runs `0.2.8/scripts/verify_honest_bot_crystal.gd`. The same input driver walks to the observed crystal column, pulses `hotbar_1` then `attack` (and skills) inside 2.4 columns, and fights a `boss-` foe before it finishes the crystal. Crystal HP is observed, never written. A vanished boss id prints `BOSS KILL`. Observed HP at or below zero prints `CRYSTAL DESTROYED`. Pass prints `HONEST BOT CRYSTAL OK` plus `CRYSTAL DESTROYED`, `BOSS SPAWN`, and `BOSS KILL`. The live boot of `main.tscn` walks toward `get_origin_cell()`, attacks for 8s after it is inside 2.4 columns, and prints `STOP live reach remaining ...` at the exact column if the crystal is not destroyed. One line that starts with `FAIL` fails the command.

`bash $S bot-run` runs `0.2.8/scripts/verify_honest_bot_run.gd` on one boot of `main.tscn`. Phases are boot, nav, combat, crystal, then progress. Each prints `PHASE <name> reached|failed|not-reached ...`. The script writes `<run>/bot-report.md` (every phase, and `Result: failed at ...` for the first failed phase) and flushes `DifficultyTelemetry` into `<run>/telemetry/*.json`. No enemy in range, or no skill point after the crystal attempt, is `not-reached` rather than a failed fight or spend. A failed phase is recorded in the report and does not by itself fail the command. Pass prints `HONEST BOT RUN DONE` and `BOT RUN OK`, with the report and at least one telemetry JSON present, and no line starting with `FAIL`. `bash $S record bot-run` is the windowed movie of that same session (mp4 plus `contact-sheet.png` in the run folder).

`bash $S bot-showcase` runs `0.2.8/scripts/verify_honest_bot_showcase.gd`. The same input driver plays `0.2.8/docs/showcase/ROUTE.md` in order and stops at the first segment that is not ready yet. This slice plays `boot_tutorial`, `movement` (sprint, at least 8 columns, one jump), `lighting` (locked sun and the shadow light, held in frame), `day_night` (`absent`), `dig_tool` (stone pick, one dug column), and `structure_place` (one stone wall, a ghost of each blueprint, then a crafted wall segment). Traversal (`density_poi`, `density_treasure`, `density_landmark`) plays after the build: the shortest poi-then-treasure-then-landmark chain among the 8 nearest of each kind, sprinting, with a 1500-column cap per leg. Standing inside the ruin radius lets the director discover the treasure. Night and torch lines are `absent` until the game has them. A crystal-glow landmark logs `SHOWCASE glow`. It then farms to level 3 (191 XP earned) before any heart swing: other crystal kinds inside 220 columns, wildlife already in range, and up to four more treasure chests. Mites and the bow shot still happen. It does not stop at the old hunt timer while that bar is short. The first mite also takes one bow shot. After level 3 it chips crystal mass with the stone pick, only on cells at least 3.6 columns from the origin, until level 6 so the later skills have points. With those points it opens the tree, moves with `ui_down` / `ui_right`, and confirms with `ui_accept`, then casts dash, Ground Slam (the 3×3, held again as multiblock break), Crystal Pulse, and Quick Wall. The passive beat spends the miner passive and holds that node. Each of those logs `SHOWCASE STAMP` plus the on-screen clock. It then chains the crystal driver: mouse on the origin column, sword swings from a dry pad (depth under 0.25, never the burn pool), carving the rim with the pick if that pad is missing, the warden at about 25% heart HP, then the victory title held for 5 seconds. Feature chapters after the mite (bow, skills, structures, treasure, landmark, crystal, boss, win) pause about a second before the action, leave the result up for about 2.5 seconds, then settle for a second. Distinct presses are at least 150 ms apart. `chapters.txt` fails the rerun when any chapter is under 4 seconds. A relic offer is dismissed with a mouse click. Mouse aim, the craft-button click, and the X key are input events. An on-screen label shows the run timer and the current chapter. The run writes `chapters.json` and `chapters.txt` (feature, start time, end time) into the evidence folder, which is the same folder as a recording. Pass prints `HONEST BOT SHOWCASE OK`, a `KILL crystal_mite` line, `SKILL dash`, `SKILL ground_slam`, `CRYSTAL DESTROYED`, `BOSS SPAWN`, and `BOSS KILL`. One line that starts with `FAIL` fails the command.

## Play harness

`bash $S scenario <dig|build|multi_dig|multi_build|break|crystals|corruption|combat|mite_fight|relic_esc|kite>` runs `0.2.8/scripts/verify_honest_bot_scenario.gd` at `--fixed-fps 60` with physics jitter fix off. The contract is `0.2.8/docs/showcase/HARNESS.md`. World scenarios boot `main.tscn` from seed 12349 and play through `honest_bot` (`HonestInput`, `HonestBuild`, `HonestPlayBot`, `HonestCombat`, `HonestSkillCast`). Pass prints `HARNESS SCENARIO OK <name>`, `HARNESS SHOT`, and `PROBE CAPTURE`, and the shot file must exist. `mite_fight` loops seeds 12349–12353 (or `CRYSTALSTORM_HARNESS_SEED` / `CRYSTALSTORM_HARNESS_SEEDS`) through `HonestFight`. `relic_esc` uses those same seeds: it opens the relic offer, sends Esc, and keeps the pause menu closed until a relic is picked. `break` does not boot. It must print `FAIL harness assertion`, `STUCK REPORT`, and `STUCK SHOT`, and the wrapper then prints `SCENARIO BREAK OK`. `kite` does not boot. It must print `HARNESS kite retreat`, `HARNESS kite reengage`, `LOOP BREAK`, and `HARNESS SCENARIO OK kite`. One line that starts with `FAIL` fails a world scenario and fails `kite`. Stuck reports and their screenshots are `HonestPlayBot.fail_closed`.

## Drive

`bash $S feature <name>` runs that feature's headless suite and checks its terminal marker and that no line starts with `FAIL`. Names: `full-map`, `water`, `save-continue`, `dig`, `frontend`. Each maps to a recipe in `features/`. These suites drive the real nodes (`ui/topographical_map.gd`, `fluids/voxel_fluid_service.gd`, `systems/save_game_service.gd`, `world/terrain_edits.gd`, `systems/world_manager.gd`) and the real input actions in `project.godot` (`toggle_map`, `attack`, `jump`, `quick_save`, `pause`…), not test-only endpoints. `launch` is the only end-to-end path through `main.tscn`.

## Record

`bash $S record showcase` runs the same honest showcase with a window of at least 1280x720. Godot locks the movie size from the project viewport before the script can resize it (the unset default is 1152x648), so the wrapper writes a temporary `0.2.8/override.cfg` for that process only (`viewport_width/height` and window overrides at 1280x720) and removes it when Godot exits. It refuses to start if an `override.cfg` is already there. The on-screen timer and chapter label are in the frames. After a passing run it copies the mp4, contact sheet, and chapter sidecar into `verify-evidence/showcase/`, and copies the mp4 to `D:\LATEST\CrystalStorm\showcase-speedrun.mp4`. If any of those names already exist, the copy uses the next free name (`showcase-speedrun-v2.mp4`, `contact-sheet-v2.png`, and the same for the sidecar). It never overwrites or deletes an existing evidence file. Chapter times are also muxed into the mp4 when ffmpeg can do that without re-encoding.

`bash $S record <mode...>` wraps any existing subcommand (`quick`, `launch [SEC]`, `feature <name>`, `showcase`, `clip`). It sets `RUN_ID` to `<YYYYMMDD-HHMMSS>-<mode>` (spaces become dashes), drops `--headless` so the GPU can capture frames (a Godot window opens), and runs that mode with `--fixed-fps 30` before `--write-movie` (so the movie step is 1/30s) plus `--disable-vsync`. The showcase clock is that same engine step, not wall time. After Godot exits, the script waits until the AVI is closed and no longer growing, drops the blank first frame, and encodes to a temporary mp4. If the kept frames run short of the game clock (`chapters.txt` end, or a `MOVIE_GAME_SEC` line), it stretches those frames so the video lasts as long as the game. ffmpeg writes `+faststart`, then ffprobe must show a duration within 8% of that game clock (at least 0.45s). Only then is the temp file renamed to the mp4. Output is `D:\ARCHIVE\CrystalStorm\verify-evidence\<run-id>\*.mp4` plus `contact-sheet.png`: a grid of evenly spaced frames (up to 16), each stamped with its timestamp using `fonts/DejaVuSans.ttf` beside this script (Arial only if that file is missing). Several movies share one sheet, and each cell is labeled with the movie name. The sheet is written even when the game command fails; a failed showcase is not copied to `verify-evidence/showcase/`. Import is not recorded (no frame loop). Missing ffmpeg, a missing evidence directory, a duration mismatch, or a failed contact sheet prints `RECORD FAIL:` and exits 1. Success prints `RECORD OK`, the mp4 paths, and the contact-sheet path. `bash $S record clip` is the short check: about three seconds, a crystal-HP stand-in, and the chapter label on the right.

## Evidence

- Location: `/mnt/d/ARCHIVE/CrystalStorm/verify-evidence/$RUN_ID/` (Windows `D:\ARCHIVE\CrystalStorm\verify-evidence\`). Outside the repo, survives cleanup. Never commit it.
- Files: `<step>.log` per Godot run (the command line, start time, full stdout/stderr, `# exit=N`), `smoke.log`, and `scripted_smoke_evidence.md` copied out of the scratch dir (per-check `**X OK**`/`**X FAIL**` lines: Dig, Entities, Combat, Vegetation, Streaming, Jump, Ramp, Crystal edge, Session).
- Step shots: `cs-verify.sh` exports `CRYSTALSTORM_EVIDENCE` (Windows path of this run's folder) and `CRYSTALSTORM_RUN_ID`. Named steps call `await ProbeCapture.capture_step("step_name")` (`0.2.8/helpers/probe_capture.gd`). A windowed run writes `<index>_<step_name>.png` in `<run>/steps/`. The index continues from pngs already in that folder. Headless runs, and any run whose root viewport is missing, return `""` and do not touch the viewport texture, so `quick`, `feature`, and `launch` still pass with no window. Self-test: `godot --path 0.2.8 -s res://scripts/verify_probe_capture.gd` (prints `PROBE CAPTURE OK`, including `OK probe capture headless skip`).
- Names already wired: feature slugs in `features/` (`dig-delta`, `dig-surface`, `dig-sword-guard`, `map-binding`, `map-coverage`, `map-open`, `map-close`, `map-auto-close`, `water-flood`, `water-level`, `water-dry`, `water-gap-fill`, `save-alive-quit`, `continue-restore`, `continue-dead`, `continue-disabled`, `frontend-catalog`) and the smoke journey (`boot`, `dig`, `dig-mesh`, `entities`, `combat`, `combat-vfx`, `vegetation`, `streaming`, `jump`, `ramp`, `crystal-edge`, `session`). Each call is at the end of that check, pass or fail. A new named step should `await` the same call with its slug; do not fail the step when the returned path is empty.
- Proof standard: quote the marker lines and the exit code. A dig counts only with a column height delta and mesh `surface_y` corroboration (smoke Dig line). A save counts only after reload (save-continue suite). Exit 0 alone is never proof; one `FAIL` line fails the step. Never set `SMOKE_FORCE_FAIL`, never loosen a marker, never re-run only the green steps.
- Headless Godot cannot screenshot. Visual claims (textures, animations, lighting) stay unverified unless Cole runs the windowed script.

## Cleanup

`bash $S cleanup` kills only pids listed in `/tmp/cs-verify/pids`, deletes `/mnt/d/csmerge/verify-scratch/$RUN_ID`, and forgets the run id. It never touches evidence, never kills by name, never touches `0.2.8/.godot/`, and never touches other agents' Godot or the `grok` CLI. Run it after every attempt, failed ones too. Killing the WSL wrapper pid may leave a Windows `Godot.exe`; if `doctor` still counts one after cleanup, report it instead of `taskkill /IM`.

## Telemetry summary

`bash $S telemetry-summary <session.json|dir> [more...]` reads one or more `DifficultyTelemetry` session files (`user://telemetry/<session_id>.json`, or the copy under a verify-evidence run). It does not start Godot. It prints player deaths, the top damage dealt by source, damage taken by source, the kill-weighted average time-to-kill (and the mean per enemy type), and XP per minute (`gained * 60000 / elapsed_msec`, summed across files). A directory argument includes every `*.json` in that directory. `python3 0.2.8/tools/telemetry_summary.py --self-test` writes a throwaway session and checks those numbers (`TELEMETRY SUMMARY OK`).

## Helpers

- `cs-verify.sh` (this dir, executable): the subcommands above. `quick` with no `RUN_ID` uses its own `quick-<timestamp>` evidence dir so the queue feeder's runs never collide.
- `QUICK_CHECK` in repo-root `VERIFY.md` calls `cs-verify.sh quick`; the feeder (`~/agent-queue/feeder.sh`) runs it from the repo root after each job with a 10 min timeout.
- Full gate: `cd 0.2.8 && bash scripts/run_all_verify.sh` (~120 suites, slow; only when asked).

Keep `features/` honest as the game changes (`/maintain-verification-skill`).
