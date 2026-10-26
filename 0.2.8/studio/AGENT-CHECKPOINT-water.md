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
