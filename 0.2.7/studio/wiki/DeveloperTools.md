# Developer Tools

## Current tools

The project includes several developer-facing systems:

- `DebugPanel` for runtime diagnostics.
- `DevChatOverlay` and `DeveloperAssistant` for slash-command style interaction.
- `DevToolsCoordinator` for debug toggles and bug reports.
- `BugReporter` for state capture.
- `ScenarioPresets` for reproducible test/play states.
- `PerfProfiler` for timing and gauges.
- `scripts/run_all_verify.sh` and `scripts/run_all_verify.gd` for headless verification.
- display/smoke/manual probes under `scripts/`.
- `world_viewer.tscn` and `world/world_viewer.gd` for world-generation inspection.
- `addons/crystal_texture_tools` for texture generation/editor workflows.

## Connected systems

Developer tools touch most runtime systems through groups:

- player,
- world,
- chunk manager,
- crystal manager,
- performance service,
- visual registry,
- terrain editor,
- entity manager,
- save service.

## Gameplay value

These tools support gameplay iteration by making it easier to:

- reproduce seeds and scenarios,
- inspect chunk/crystal/player state,
- validate smoke paths,
- generate bug evidence,
- run targeted verification suites,
- tune performance presets.

## Current gaps

- No single command catalog for dev chat, scenarios, probes, and verification scripts.
- No CI/task-runner wrapper visible in the repo.
- Some main-scene probes rely on terminal OK markers because teardown can abort after success.
- Generated logs/artifacts are not clearly separated from source-controlled content.
- Tooling is broad but not yet organized as a coherent developer workflow.

