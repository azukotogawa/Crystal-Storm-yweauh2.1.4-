# Boot and play session

The player starts a world and plays: the world streams in around them, they dig with the pickaxe, an enemy spawns, they swing at it, jump, and walk without falling through terrain.

## Sub-features

- `boot` main.tscn reaches a ready world (player, chunks, terrain, visuals, crystals).
- `dig` pickaxe lowers a column, mesh agrees.
- `entities` spawned entities have textured billboards.
- `combat` melee damages an entity and shows a damage label.
- `jump` Space leaves the ground and lands.
- `streaming` walking keeps chunks loaded with no holes.
- `session` the loop runs for the target seconds without hitching out.

## How to get to it (user POV)

- Launch the game, pick or create a world on the frontend, press Play.
- In world: WASD moves, left-click `attack` uses the held tool, Space `jump`.

## Driving it with cs-verify.sh

Preconditions:

- `doctor` OK, `quick` OK.

- **Boot and play.** Run `bash $S launch 8`. `scripted_smoke_evidence.md` lists `**Bootstrap OK**` and `**Session OK**: 8.xs / 8s target, N frames`.
- **Check each journey.** Read the `- **<Check> OK|FAIL**` lines it prints (Dig, Entities, Combat, Vegetation, Streaming, Jump, Combat VFX, Ramp, Crystal edge, Session). All must be OK.
- **Proof.** Final line `LAUNCH OK (SMOKE GAMEPLAY OK)`; evidence `smoke.log` and `scripted_smoke_evidence.md` in the run's evidence dir.

## Gotchas

- This skips the frontend menu: the probe instances `main.tscn` directly. Menu flow is covered by `save-continue`/`frontend`.
- 2026-10-13 proof run on `cs/playtest-0.2.9` @ b133bbc (with uncommitted edits to `entity_navigation.gd`, `crystal_fluid_sim.gd`, new `helpers/water_locomotion.gd` in the tree): `**Jump FAIL**: jump input air=false landed=false moved=true` twice in a row; every other check OK. Treat as a real regression until fixed, do not weaken the check.
- `SMOKE_SESSION_SEC` below 5 is raised to 5.
- `CRYSTALSTORM_SCRATCH` must be a `D:/...` path; `/tmp` makes Windows Godot fail to write evidence and the smoke reports FAILED.
