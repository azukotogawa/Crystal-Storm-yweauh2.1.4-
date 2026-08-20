# Water live profile

**Driver:** `scripts/display_water_profile.gd` on production `scenes/main.tscn`.  
**Cell:** gameplay `(46, 10)` via `TerrainEditor.try_channel_water`.  
**Screenshot:** scratch `water_profile_cell.png` (F4 agree, water 0.55, mesh covered).

## What used to cost ~357 ms/frame

Not simulation. Every frame the service:

1. Treated any overlay water as “must tick”
2. Copied **every** `ChannelRegistry` water cell plus 4 neighbors (~2482 + ~4626)
3. Called `world.get_tile_type` on that set
4. Ran gravity on the copy
5. Did this up to 3 times per hitch

`is_cell_active` only skipped *flow* on unloaded cells. Visuals were not the cost: `channel_fluid_changed` still has **0 listeners**.

## Live breakdown (current shipped path)

Phases are on `VoxelFluidService.get_sim_diagnostics().phase_us`.

| Phase | Idle playable (15 frames) | One interactive channel tick | Next 20 frames |
|---|---|---|---|
| process | 20 µs | 17 µs | sleep |
| gather (dirty box) | 0 | 79 µs | 0 |
| copy (engine clear + depth + subset) | 0 | 10.6 ms | 0 |
| sim (`tick_flow`) | 0 | 281 µs | 0 |
| persist | 0 | 11 µs | 0 |
| visual (signal) | 0 | 0 (0 listeners) | 0 |
| off-screen in subset | 0 | 0 | 0 |
| tile samples | 0 | 1 | 0 |
| sleeping | **15/15** | one-shot then **20/20** | **20/20** |
| `last_tick_us` | **0** | leftover 0 after sleep | **0** |

F3 on the same frame: `main 6.3 ms` (crystal + entities). No `RIVER main 357 ms SPIKE`.

Headless `verify_water_active_region`: idle 4 µs; 500 overlay channels + one dirty cell → subset 21, gather 18 / copy 109 / sim 465 / persist 134 / visual 6 µs.

## Root cause / change

Gameplay water is **edit-driven**. Empty dirty set sleeps. `mark_region_dirty` / `recompute_region_now` load only the dirty box. Natural river tiles inject only on those dirty cells. Walking does not wake the sim.

The 10.6 ms `copy` is a **single** interactive `recompute_region_now` (local 121-cell box), not a per-frame tax.

A yard session on **river tiles** (tile 37) first re-awoke the 200 ms class: F4 `sleep=false tick_us=226991 dirty=3464`. Injecting 0.95 on every dirty river neighbor let gravity register a marsh.

After restricting inject to cells that already have a player `water_level`:

| | Idle | Dry channel `(46,10)` | River channel `(24,24)` tile 37 |
|---|---|---|---|
| sleep | 15/15 | 20/20 | **25/25** |
| worst `last_tick_us` | 0 | 0 | **0** |
| dirty after | 0 | 0 | **0** |
| overlay channels | 0 | 1 | **2** (not 3500) |
| interactive copy | 0 | 2.1 ms | 0.97 ms |
| visual/off-screen | 0 | 0 | 0 |

`scripts/verify_water_active_region.gd` asserts the phase keys and that a radius-8 dirty box cannot explode past 400 subset cells.

## Remaining limitation

`engine.clear()` + subset copy on a large interactive radius is still the biggest slice of an *edit*. It is not paid every frame. Do not reintroduce a world gather to “keep rivers flowing” in the background.
