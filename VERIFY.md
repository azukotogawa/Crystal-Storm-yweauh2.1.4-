# VERIFY: Crystal Storm

Verification skill for this repo. An agent follows this file as a contract: same commands, same markers, same PASS rule. A window that opens, or a single script that exits 0, is not a pass.

This tree is a Godot 4.7 game. There is no Cargo, npm, or Makefile build. Importing `0.2.7/` is the build. Tests are headless Godot scripts. The playable check is a headless smoke of `res://scenes/main.tscn`.

## Repo

- Git root: `/mnt/c/Users/cwith/Crystal-Storm-yweauh2.1.4-`
- Project directory for every command in this file: `0.2.7/`
- `project.godot`: name `Crystalstorm`, features `4.7` / Forward Plus, main scene `res://scenes/frontend.tscn`
- Engine binary that actually works from WSL: `/home/cwith/csmerge-bin/godot` (Godot 4.7.x console wrapper around `C:\Godot\Godot.exe`)

## Do not

- Do not read or print `.env`, `~/.grok/auth.json`, `export_credentials.cfg`, or any key or token file.
- Do not merge. Do not checkout, reset, or commit on `main`.
- Do not call bare `godot` until `PATH` starts with `/home/cwith/csmerge-bin`. `/home/cwith/bin/godot` runs `Godot.exe` with the argument list dropped, which opens the editor and does not run your script.
- Do not leave `CRYSTALSTORM_PROBE_ABRUPT_EXIT` exported in the shell. Suites that need it set it on that one process. A leftover `=1` makes later probes SIGKILL themselves and look like crashes.
- Do not point `APPDATA` back at the real user profile. The wrapper sets `APPDATA=D:\csmerge\appdata` so probes cannot write Cole's saved games. Leave that override in place.
- Do not commit Godot import caches, logs, or smoke evidence. The only file this skill writes into the repo is `VERIFY.md`.

## Setup

Run this once per shell, from any directory:

```bash
export PATH="/home/cwith/csmerge-bin:$PATH"
export WSLENV="SMOKE_SESSION_SEC${WSLENV:+:$WSLENV}"
hash -r
command -v godot
godot --version
```

`command -v godot` must print `/home/cwith/csmerge-bin/godot`. `godot --version` must print a `4.7` line.

The wrapper converts `/mnt/<drive>/...` arguments to Windows paths. It forwards `APPDATA` and every `CRYSTALSTORM_*` variable into Windows Godot. Any other variable reaches Godot only when it is already listed in `WSLENV`. `SMOKE_SESSION_SEC` is listed above so the smoke duration crosses that boundary.

```bash
ROOT="/mnt/c/Users/cwith/Crystal-Storm-yweauh2.1.4-/0.2.7"
cd "$ROOT"
mkdir -p /tmp/crystalstorm-verify /mnt/d/csmerge/verify-scratch
export CRYSTALSTORM_SCRATCH='D:/csmerge/verify-scratch'
export CRYSTALSTORM_BAKE_RADIUS=2
export CRYSTALSTORM_FULL_WORLD_BAKE=0
export CRYSTALSTORM_BAKE_ON_NEW=0
export CRYSTALSTORM_PERF_PRESET=medium
unset CRYSTALSTORM_PROBE_ABRUPT_EXIT
```

Two directories, on purpose:

- `/tmp/crystalstorm-verify/` holds shell logs. Bash writes these. Godot's stdout comes back through the wrapper, so `tee` and `>` work.
- `CRYSTALSTORM_SCRATCH` is `D:/csmerge/verify-scratch` (WSL path `/mnt/d/csmerge/verify-scratch`). The probe writes `scripted_smoke_evidence.md` with Godot's `FileAccess`, inside Windows `Godot.exe`. A `/tmp/...` value is not a Windows directory. Godot then errors with `Could not create directory: '/tmp'`, the smoke treats the missing evidence file as failure, and it prints `SMOKE GAMEPLAY FAILED` even when the play session ran. Use a `D:/...` path. Forward slashes survive `WSLENV`.

## 1. Build

Import compiles scripts and refreshes assets, then quits. This is the build.

```bash
godot --headless --path "$ROOT" --import > /tmp/crystalstorm-verify/import.log 2>&1
echo "import_exit=$?"
```

PASS for this step:

- `import_exit=0`
- `import.log` does not contain `SCRIPT ERROR`
- `import.log` does not contain `Parse Error`
- `import.log` does not contain `Failed to load script`

Godot prints warnings and resource lines on a healthy import. Those are not failures. A non-zero exit is a failure even if the log looks chatty.

## 2. Tests

The release gate is the full suite (section below). It is about 120 processes and is the wrong default on a busy machine. The required test slice is two suites that load scripts and check contracts. They call `quit(0)` on success, so the exit code counts.

```bash
godot --headless --path "$ROOT" -s res://scripts/verify_stability_perf.gd \
  > /tmp/crystalstorm-verify/stability.log 2>&1
echo "stability_exit=$?"
godot --headless --path "$ROOT" -s res://scripts/verify_content_contracts.gd \
  > /tmp/crystalstorm-verify/contracts.log 2>&1
echo "contracts_exit=$?"
```

PASS for this step:

- `stability_exit=0` and `stability.log` contains the line `All stability/perf tests OK`
- `contracts_exit=0` and `contracts.log` contains the line `All content contract tests OK`

`push_error` lines and the word `FAIL` in either log are failures even if you also see an OK line from an earlier check.

Other suites in `scripts/run_all_verify.sh` are different. The ones listed in `ABRUPT_OK_MARKER` print a marker such as `All composition boot tests OK` and then the harness kills the process (`CRYSTALSTORM_PROBE_ABRUPT_EXIT=1`) so Godot's teardown cannot turn a pass into abort 134. For those suites the marker is the result. Exit 137 or 134 after the marker is still a pass. Exit 137 without the marker is a fail. Do not apply that rule to the two suites in this section.

## 3. Headless smoke

This launches the game. `scripts/smoke_gameplay.gd` instances production `res://scenes/main.tscn`, waits until the player, chunk manager, terrain, world, visuals, and crystal manager are ready, digs through `WeaponController`, spawns one entity, and simulates a few seconds of movement, digging, jumping, and a melee swing. It is not a human playtest.

```bash
SMOKE_SESSION_SEC=8 SMOKE_LOG=/tmp/crystalstorm-verify/smoke.log \
  bash scripts/run_smoke_gameplay.sh
echo "smoke_exit=$?"
```

`run_smoke_gameplay.sh` exports `CRYSTALSTORM_PROBE_ABRUPT_EXIT=1` for that process only, keeps the Godot output, and decides pass from the text:

- log contains `SMOKE GAMEPLAY FAILED` → script exits 1
- log contains `SMOKE GAMEPLAY OK` → script exits 0
- neither marker → script exits 1

PASS for this step:

- `smoke_exit=0`
- `/tmp/crystalstorm-verify/smoke.log` contains `SMOKE GAMEPLAY OK`
- `/tmp/crystalstorm-verify/smoke.log` does not contain `SMOKE GAMEPLAY FAILED`
- `/mnt/d/csmerge/verify-scratch/scripted_smoke_evidence.md` exists and contains `Bootstrap OK`

The evidence markdown is the captured log of what the smoke actually did (dig column, entity sprites, session frame count). Quote its `**Dig OK**` / `**Session OK**` lines when you report the run. Godot may then die with signal 137 because the probe kills itself after the marker. That signal is expected. The shell script's exit code is the one that counts.

`SMOKE_SESSION_SEC` shorter than 5 is raised to 5 inside `smoke_probe_helpers.gd`. 8 seconds is the recipe value. Do not set `SMOKE_FORCE_FAIL`.

## 4. Screenshot evidence

Headless Godot has no image to save. Screenshot evidence is a separate windowed run. It opens a game window on the Windows desktop. Skip it when a visible window is not acceptable. It is not part of the PASS rule below.

```bash
CRYSTALSTORM_PROBE_ABRUPT_EXIT=1 \
  godot --path "$ROOT" -s res://scripts/display_gameplay_validation.gd \
  > /tmp/crystalstorm-verify/display.log 2>&1
```

That script saves PNGs under `CRYSTALSTORM_SCRATCH` and prints `SHOT <path>` for each one. Its terminal marker is `DISPLAY GAMEPLAY VALIDATION OK` (failure marker: `DISPLAY GAMEPLAY VALIDATION FAILED`). A screenshot step passes only when the log contains the OK marker and at least one `SHOT ` path exists as a non-empty PNG.

`scripts/run_display_session.sh` is the other windowed corroboration. It looks for `DISPLAY SESSION OK` in `display_session.log` and writes `display_session_evidence.md`. It does not save PNGs. Use `display_gameplay_validation.gd` when the evidence you need is a picture.

## PASS

The recipe passes only when all of these are true:

1. Import exit 0, and `import.log` has none of `SCRIPT ERROR`, `Parse Error`, `Failed to load script`.
2. Stability suite exit 0 and log contains `All stability/perf tests OK`.
3. Content-contract suite exit 0 and log contains `All content contract tests OK`.
4. Smoke script exit 0, `smoke.log` contains `SMOKE GAMEPLAY OK`, and it does not contain `SMOKE GAMEPLAY FAILED`.

Screenshot evidence is extra. Record it when you captured it. Do not fail the recipe for skipping it, and do not pass the recipe on screenshots alone.

## FAIL

Any broken condition above is FAIL. Stop. In the report, include the step name, the exit code, and the last lines that show the error or the missing marker. Do not loosen a marker. Do not hide a failure by re-running only the green steps.

## Release gate

Not the default recipe. Run it only when someone asked for the full suite.

```bash
unset CRYSTALSTORM_PROBE_ABRUPT_EXIT
bash scripts/run_all_verify.sh | tee /tmp/crystalstorm-verify/all.log
```

The script lives at `0.2.7/scripts/run_all_verify.sh`. It runs 120 headless suites. Suites in `ABRUPT_OK_MARKER` pass on their marker string. Every other suite must exit 0; their output is discarded, and a failure is printed as `FAIL (exit N)` or `FAIL (missing OK marker)` plus the last 8 lines. PASS for the gate is exit 0 and a final line:

```text
=== ALL VERIFY SUITES PASSED (120) ===
```

If the suite list changes, the number in that line changes with `"${#SUITES[@]}"`. Trust the printed number, then confirm it matches the length of `SUITES` in the script you just ran.

## Last run

Date: 2026-10-13T09:03:51-07:00 to 2026-10-13T09:05:41-07:00 (local). Branch `verify/skill` at parent `59160e5` (`0.2.7`). Godot `4.7.1.stable.official.a13da4feb` via `/home/cwith/csmerge-bin/godot`. Screenshot step skipped (headless recipe only).

Commands (from `0.2.7/`, after the Setup block in this file):

```bash
godot --headless --path "$ROOT" --import > /tmp/crystalstorm-verify/import.log 2>&1
godot --headless --path "$ROOT" -s res://scripts/verify_stability_perf.gd > /tmp/crystalstorm-verify/stability.log 2>&1
godot --headless --path "$ROOT" -s res://scripts/verify_content_contracts.gd > /tmp/crystalstorm-verify/contracts.log 2>&1
SMOKE_SESSION_SEC=8 SMOKE_LOG=/tmp/crystalstorm-verify/smoke.log bash scripts/run_smoke_gameplay.sh
```

Results:

| Step | Exit | Marker | Verdict |
| --- | --- | --- | --- |
| Import | 0 | no `SCRIPT ERROR`, `Parse Error`, or `Failed to load script` | pass |
| `verify_stability_perf.gd` | 0 | `All stability/perf tests OK` | pass |
| `verify_content_contracts.gd` | 0 | `All content contract tests OK` | pass |
| `run_smoke_gameplay.sh` | 1 | `SMOKE GAMEPLAY FAILED` | fail |

Smoke evidence `/mnt/d/csmerge/verify-scratch/scripted_smoke_evidence.md` (session 8s, captured 2026-10-13T09:04:49) contains `Bootstrap OK`. Dig did not change the terrain:

```text
- **Dig FAIL**: target_col=(0,2) before=8.00 after=8.00 delta=0.00 mesh_sy=8.00
```

The same file records Entities OK (21/21), Combat OK, Vegetation OK (167/167), Streaming OK (36→42), Jump OK, Combat VFX OK, Ramp OK, Crystal edge OK, and Session OK (9.1s, 138 frames). One `FAIL` line is enough: the smoke script exits 1.

**FAIL.** Import and both contract suites passed. The headless smoke launched `main.tscn` and played, then failed because the pickaxe did not lower column (0,2).

A throwaway attempt immediately before this run set `CRYSTALSTORM_SCRATCH=/tmp/crystalstorm-verify`. Windows Godot printed `Could not create directory: '/tmp'` and `Could not write /tmp/crystalstorm-verify/scripted_smoke_evidence.md`, then `SMOKE GAMEPLAY FAILED` with no gameplay verdict. That attempt is not this result. The scratch path in Setup is the one this run used.
