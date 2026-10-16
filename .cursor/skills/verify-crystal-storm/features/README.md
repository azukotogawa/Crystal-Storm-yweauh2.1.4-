# Crystal Storm verification map

Maintained source for verifying Crystal Storm's player-facing behavior. Read this index, then use the feature file as the recipe.

## Baseline preconditions

- WSL shell at `/mnt/c/Users/cwith/Crystal-Storm-yweauh2.1.4-`, branch you are verifying checked out.
- `S=.cursor/skills/verify-crystal-storm/cs-verify.sh` and `export RUN_ID=<name>`.
- `bash $S doctor` prints `DOCTOR OK` and at least ~2 GB available memory.
- `bash $S quick` prints `QUICK OK` (scripts compile) before driving any feature.
- Never drive while another agent's Godot import is running.

## Driving conventions

- Run feature suites with `bash $S feature <name>`; end-to-end play with `bash $S launch 8`.
- Input handles are action names from `0.2.8/project.godot` (`toggle_map`=M, `jump`=Space, `attack`, `quick_save`, `quick_load`, `pause`), not raw keycodes.
- Treat marker strings as literal. Pass = marker present, no line starting `FAIL`, and exit 0 (or 134/137 after the marker for abrupt-exit suites).
- Every run starts from a fresh generated world; saves go to `APPDATA=D:\csmerge\appdata`, never Cole's profile.

## Proof and skip reporting

- Quote the `OK …`/`FAIL …` lines and `# exit=` from `/mnt/d/csmerge/verify-evidence/$RUN_ID/feature-<name>.log`.
- Mutations (dig, water spread, save) must show the stored result read back: height delta, wet cell count, reloaded snapshot.
- Visual-only behavior (textures, animation, camera feel) cannot be proven headless. Report it as unverified, never as passed via a suite.
- Each sub-feature slug is a named step. The suite `await`s `ProbeCapture.capture_step(slug)` when that step finishes. Headless and other non-rendering runs skip the png and still pass. `record` keeps the window, so the png lands in `<evidence>/<run-id>/steps/`.
- An unreachable path gets the attempted command plus the unmet precondition.

## Feature entry contract

H1 title, one paragraph of user-visible behavior, then exactly `Sub-features`, `How to get to it (user POV)`, `Driving it with cs-verify.sh`, `Gotchas`.

## Features

- [Boot and play session](./boot-and-play.md): menu to world, dig, combat, jump, streaming (`launch`).
- [Honest bot navigation](./honest-bot.md): walk toward a column using only mapped actions (`bot`).
- [Honest bot progression](./honest-bot-progress.md): level from kills and spend the point with the skill tree (`bot-progress`).
- [Full map toggle](./full-map.md): M opens/closes the fullscreen map and blocks actions (`full-map`).
- [Dig terrain](./dig.md): pickaxe lowers a column (`dig`, plus smoke Dig line).
- [Water flow](./water-flow.md): breaking into a gap floods the whole connected hole (`water`).
- [Save and Continue](./save-continue.md): quit alive, then Continue restores the world (`save-continue`, `frontend`).
