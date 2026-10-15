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
bash $S feature full-map # drive one mapped feature (names in features/README.md)
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

## Drive

`bash $S feature <name>` runs that feature's headless suite and checks its terminal marker and that no line starts with `FAIL`. Names: `full-map`, `water`, `save-continue`, `dig`, `frontend`. Each maps to a recipe in `features/`. These suites drive the real nodes (`ui/topographical_map.gd`, `fluids/voxel_fluid_service.gd`, `systems/save_game_service.gd`, `world/terrain_edits.gd`, `systems/world_manager.gd`) and the real input actions in `project.godot` (`toggle_map`, `attack`, `jump`, `quick_save`, `pause`…), not test-only endpoints. `launch` is the only end-to-end path through `main.tscn`.

## Record

`bash $S record <mode...>` wraps any existing subcommand (`quick`, `launch [SEC]`, `feature <name>`). It sets `RUN_ID` to `<YYYYMMDD-HHMMSS>-<mode>` (spaces become dashes), drops `--headless` so the GPU can capture frames (a Godot window opens), runs that mode with `--write-movie` / `--fixed-fps 30` / `--disable-vsync`, then converts each AVI (or PNG sequence) to mp4 with the portable ffmpeg at `C:\Users\cwith\pivot\ffmpeg\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe`. Output is `D:\ARCHIVE\CrystalStorm\verify-evidence\<run-id>\*.mp4` plus `contact-sheet.png` in that same folder: a grid of evenly spaced frames from those mp4s (up to 16), each stamped with its timestamp when Arial is available. Several movies share one sheet, and each cell is labeled with the movie name. Import is not recorded (no frame loop). Missing ffmpeg, a missing evidence directory, or a failed contact sheet prints `RECORD FAIL:` and exits 1. Success prints `RECORD OK`, the mp4 paths, and the contact-sheet path.

## Evidence

- Location: `/mnt/d/ARCHIVE/CrystalStorm/verify-evidence/$RUN_ID/` (Windows `D:\ARCHIVE\CrystalStorm\verify-evidence\`). Outside the repo, survives cleanup. Never commit it.
- Files: `<step>.log` per Godot run (the command line, start time, full stdout/stderr, `# exit=N`), `smoke.log`, and `scripted_smoke_evidence.md` copied out of the scratch dir (per-check `**X OK**`/`**X FAIL**` lines: Dig, Entities, Combat, Vegetation, Streaming, Jump, Ramp, Crystal edge, Session).
- Proof standard: quote the marker lines and the exit code. A dig counts only with a column height delta and mesh `surface_y` corroboration (smoke Dig line). A save counts only after reload (save-continue suite). Exit 0 alone is never proof; one `FAIL` line fails the step. Never set `SMOKE_FORCE_FAIL`, never loosen a marker, never re-run only the green steps.
- Headless Godot cannot screenshot. Visual claims (textures, animations, lighting) stay unverified unless Cole runs the windowed script.

## Cleanup

`bash $S cleanup` kills only pids listed in `/tmp/cs-verify/pids`, deletes `/mnt/d/csmerge/verify-scratch/$RUN_ID`, and forgets the run id. It never touches evidence, never kills by name, never touches `0.2.8/.godot/`, and never touches other agents' Godot or the `grok` CLI. Run it after every attempt, failed ones too. Killing the WSL wrapper pid may leave a Windows `Godot.exe`; if `doctor` still counts one after cleanup, report it instead of `taskkill /IM`.

## Helpers

- `cs-verify.sh` (this dir, executable): the subcommands above. `quick` with no `RUN_ID` uses its own `quick-<timestamp>` evidence dir so the queue feeder's runs never collide.
- `QUICK_CHECK` in repo-root `VERIFY.md` calls `cs-verify.sh quick`; the feeder (`~/agent-queue/feeder.sh`) runs it from the repo root after each job with a 10 min timeout.
- Full gate: `cd 0.2.8 && bash scripts/run_all_verify.sh` (~120 suites, slow; only when asked).

Keep `features/` honest as the game changes (`/maintain-verification-skill`).
