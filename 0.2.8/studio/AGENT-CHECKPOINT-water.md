# Water checkpoint (cs-sonnet/water)

Env: Godot 4.7.2 headless on a Linux VM, scratch copy with stand-in art, shaders and audio (never committed). Visual checks, windowed screenshots and real shaders need Cole's Dell. `cs-verify.sh` ran through a patched copy (PATH shim, scratch dir).

## cs-water-01
- Deleted: see D-234 in DECISIONS.md.
- Added: `VoxelFluidService.request_flow`, `water_dig` scenario (bot walks about 200 columns to a river, digs the bank cell with the pick, waits for the fill).
- verify_water_body, verify_water_active_region, verify_dig_flood_water_block, verify_dig_brush, verify_living_force rewritten where they tested the removed paths. Guard in verify_water_body fails if a banned second flow path reappears or tick_flow is called from more than one place.
- Known: with the old float automaton the scenario fill was flaky run to run. cs-water-02 replaces the automaton rules.
