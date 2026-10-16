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

`bash $S bot-run` runs `0.2.8/scripts/verify_honest_bot_run.gd` on one boot of `main.tscn`. Phases are boot, nav, combat, progress, then crystal. Each prints `PHASE <name> reached|failed|not-reached ...`. The script writes `<run>/bot-report.md` (phases and the first place a phase did not reach) and flushes `DifficultyTelemetry` into `<run>/telemetry/*.json`. A phase that does not reach is recorded in the report; it does not by itself fail the command. Pass prints `HONEST BOT RUN DONE` and `BOT RUN OK`, with the report and at least one telemetry JSON present, and no line starting with `FAIL`. `bash $S record bot-run` is the windowed movie of that same session (mp4 plus `contact-sheet.png` in the run folder).

## Drive

`bash $S feature <name>` runs that feature's headless suite and checks its terminal marker and that no line starts with `FAIL`. Names: `full-map`, `water`, `save-continue`, `dig`, `frontend`. Each maps to a recipe in `features/`. These suites drive the real nodes (`ui/topographical_map.gd`, `fluids/voxel_fluid_service.gd`, `systems/save_game_service.gd`, `world/terrain_edits.gd`, `systems/world_manager.gd`) and the real input actions in `project.godot` (`toggle_map`, `attack`, `jump`, `quick_save`, `pause`…), not test-only endpoints. `launch` is the only end-to-end path through `main.tscn`.

## Record

`bash $S record <mode...>` wraps any existing subcommand (`quick`, `launch [SEC]`, `feature <name>`). It sets `RUN_ID` to `<YYYYMMDD-HHMMSS>-<mode>` (spaces become dashes), drops `--headless` so the GPU can capture frames (a Godot window opens), runs that mode with `--write-movie` / `--fixed-fps 30` / `--disable-vsync`, then converts each AVI (or PNG sequence) to mp4 with the portable ffmpeg at `C:\Users\cwith\pivot\ffmpeg\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe`. Output is `D:\ARCHIVE\CrystalStorm\verify-evidence\<run-id>\*.mp4` plus `contact-sheet.png` in that same folder: a grid of evenly spaced frames from those mp4s (up to 16), each stamped with its timestamp when Arial is available. Several movies share one sheet, and each cell is labeled with the movie name. Import is not recorded (no frame loop). Missing ffmpeg, a missing evidence directory, or a failed contact sheet prints `RECORD FAIL:` and exits 1. Success prints `RECORD OK`, the mp4 paths, and the contact-sheet path.

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
