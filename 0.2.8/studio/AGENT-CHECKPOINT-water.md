# Water checkpoint (cs-sonnet/water)

Env: Godot 4.7.2 headless on a Linux VM, scratch copy with stand-in art, shaders and audio (never committed). Visual checks, windowed screenshots and real shaders need Cole's Dell. `cs-verify.sh` ran through a patched copy (PATH shim, scratch dir).

## cs-water-01
- Deleted: see D-234 in DECISIONS.md.
- Added: `VoxelFluidService.request_flow`, `water_dig` scenario (bot walks about 200 columns to a river, digs the bank cell with the pick, waits for the fill).
- verify_water_body, verify_water_active_region, verify_dig_flood_water_block, verify_dig_brush, verify_living_force rewritten where they tested the removed paths. Guard in verify_water_body fails if a banned second flow path reappears or tick_flow is called from more than one place.
- Known: with the old float automaton the scenario fill was flaky run to run. cs-water-02 replaces the automaton rules.

## cs-water-02
- `fluids/voxel_fluid_engine.gd` replaced by the integer-level engine: natural water is level 8, flowed cells 7..1, a drop of half a layer or more gives level 7 and skips side spread, otherwise level-1 into floors below the surface, never uphill, no receding. Per-frame budget `max_cells_per_tick` with `leftover` carried into the next dirty set; tick rate is the fluid def `update_rate_hz`.
- Dug cells are never natural sources (`_is_natural_water_cell` requires zero height edit): the world recomputes the tile of a dug cell next to a river as RIVER, which made every dug cell an infinite source.
- New `verify_water_minecraft_rules.gd`: fall, spread distance 7 with levels 7..1, no uphill, dig fills the cavity, sources never drain, 24 cells max per frame over 600 frames. All PASS.
- `water_dig` scenario now digs 10 cells away from the lake and asserts levels 7/8..1/8 then dry. PASS headless (stand-in art).
- Rewrote the engine cases in `verify_voxel_fluid_engine`, `verify_water_sprint`, `verify_terrain_loop_complete`.
- Simplification: horizontal spread goes to every lower neighbour, not only toward the nearest drop.
- `verify_water_body` exits 1 in this scratch copy only because `water_surface.gd` cannot load with stand-in shaders; its assertions need the Dell.

## cs-water-03
- `SaveSchema.CURRENT_VERSION` and `MIN_SUPPORTED_VERSION` are 3; `migrate` and `_migrate_v1_to_v2` deleted. An older save returns `message` "world from an older version, create a new world", which `apply_snapshot_transactional` emits on `save_failed`.
- `verify_save_architecture`: old-version-refused case and a wet-cells save/JSON/reload case (7 flowed cells, identical levels). `verify_save_transaction` and `verify_macro_micro_save_migrate` moved to version 3 fixtures. All pass.
- Not run: the Continue/world-list UI showing the message to a player (needs the Dell and real UI art). `continue` simply finds no valid save for an old world.

## cs-water-04
- Deleted: `channel_water` action (project.godot, input_bindings), `_try_channel_water`, `_try_channel_water_at_target` and the Shift/Ctrl-dig route in weapon_controller, `try_channel_water`, `ChannelMode`, `_channel_*`, `_update_channel_metadata` and `get_channel_delay` in terrain_editor, and the doc lines for the channel key. T stays `dev_chat_toggle` with no modifier.
- Callers moved to `try_dig`: validation_yard, display_water_profile, profile_deferred_fill_workers/gameplay, autonomous_gameplay_audit. `try_channel_water` is banned in verify_water_body.
- `verify_dev_tools_input` now checks no `channel_water` action, no `try_channel_water` in game code, no duplicate key+modifier actions. It and `verify_dev_chat` pass.
- Scenario `dev_keys` (HonestInput; `pulse_key` gained a shift flag): Shift+T and plain T leave the terrain snapshot (height deltas and wet cell count) unchanged, plain T opens chat. PASS headless.
- Found, not changed: first Esc does not close the focused chat box, second does (Q-059).

## cs-water-05
- Scenario `water_trench` (same state machine as `water_dig`, mode flag): bot walks to a lake, digs a 10-cell trench with normal dig input, asserts levels 7/8..1/8 then three dry cells on flat ground, digs a second layer at cell 8 and asserts the fall continues (cell 8 = 7/8, cells 9 and 10 dry), places a stone wall across cell 4 with build input and asserts the lake-side cells 1-3 keep their levels.
- Past the wall nothing changes (no receding, Q-058): levels `[0.875, 0.75, 0.625, 0.5, 0.375, 0.25, 0.125, 0.875, 0.0, 0.0]` before and after the wall. Two runs gave identical levels.
- Not judged: the fill and after-wall screenshots (stand-in art, dummy renderer); they need the Dell.
