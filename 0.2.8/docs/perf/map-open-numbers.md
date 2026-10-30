# Fullscreen map (M) open numbers

Task `cs-map-load-numbers`. Headless Godot 4.7.1 on this worktree. MEDIUM quality. No `CrystalStorm.exe` while measuring.

## Method

Script: `0.2.8/scripts/measure_map_open.gd` (SceneTree, `--headless`).

- World: `InfiniteNoiseWorld` seed 12349. Playable box 2048×2048 columns (4,194,304 cells).
- Crystal: a `CrystalManager` field filled as a disk to 0%, 1%, and 10% of that box (`41943` / `419430` cells). Overlay uses the same `depth_chunks_in_rect` / `collect_depth_chunk` path as live crystal.
- Quality: `PerformanceQualityConfig` MEDIUM (`map_pixels_per_frame=192`, `map_time_budget_us=2500`, `map_sample_stride=5`). Open budget scale 8.0 from `GameFeelConfig` (20 ms paint cap while M is open). Preview interval 250 ms.
- Fullscreen job: coarse 72² then fine 288² over half-extent 1088 (stride 8 on the fine pass). Display texture 512×512. Canvas after layout ~1084×532.
- Each open is cold: height/tile caches cleared, fullscreen tex dropped, map jobs emptied.
- **Time-to-first-image:** `open_metrics.first_draw_ms` (first textured canvas draw after toggle).
- **Time-to-full:** `open_metrics.refined_ms` when `_full_fine_done` and the active job is empty.
- **Build frame times:** `Time.get_ticks_usec()` around `await process_frame` until full. Phases are `collect_<size>` (crystal overlay gather) and `paint_<size>`.
- **Idle frame times:** 45 frames after full, map still open.
- **Input:** arrow/± keys through `parse_input_event`, drag and wheel through `MapCanvas._gui_input`. Latency is frames and ms until view_center/zoom changes and the canvas redraws.

Column sample microbench (400 unique cells): `get_surface_height`, `get_tile_type`, then both, then both after the 12288-entry height cache cap.

## Baseline (before hotspot fix)

| crystal | first image | full | build frames | build p50 / p95 / max | idle p50 / p95 / max | pan | zoom | drag | wheel |
| --- | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |
| 0% | 5 ms | 10640 ms | 522 | 20.45 / 20.65 / 22.10 ms | 15.59 / 30.50 / 30.91 ms | 1f 3 ms | 1f 28 ms | 1f 15 ms | 1f 15 ms |
| 1% | 22 ms | 10663 ms | 523 | 20.40 / 20.64 / 24.16 ms | 15.72 / 28.99 / 31.19 ms | 1f 15 ms | 1f 16 ms | 1f 15 ms | 1f 15 ms |
| 10% | 22 ms | 11805 ms | 575 | 20.47 / 21.02 / 36.55 ms | 15.65 / 29.65 / 31.37 ms | 1f 16 ms | 1f 14 ms | 1f 16 ms | 1f 15 ms |

Phase totals (0% / 1% / 10%):

- `paint_288`: 10042 / 9940 / 10483 ms (~490 frames, ~20.5 ms avg)
- `paint_72`: 586 / 652 / 603 ms
- `collect_288` + `collect_72`: 6 / 64 / 695 ms

Microbench: height 95.2 µs/cell, tile 107.7 µs, pair 114.4 µs (114.8 µs after cache cap). `set_pixel` 0.95 µs.

`paint_288` is ~90% of time-to-full at every crystal load. Crystal gather only shows up at 10% (~0.7 s). Each fine pixel is a unique column; the 20 ms open budget therefore yields ~170 pixels/frame and ~10 s of paint.

The sample path called `WorldBorder.zone_info` (a new Dictionary) several times per interior column: ridge scale, height, `is_playable` inside rim helpers, map border style.

## Fix

Keep the same heights, tiles, and map colors. Interior columns use an abs playable test instead of allocating `zone_info`. Height skips the border branch when playable. Map border styling returns the base color when playable and rim strength is 0.

## After

| crystal | first image | full | build frames | build p50 / p95 / max | idle p50 / p95 / max | pan | zoom | drag | wheel |
| --- | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |
| 0% | 2 ms | 8821 ms | 433 | 20.43 / 20.71 / 23.18 ms | 15.74 / 29.26 / 31.05 ms | 1f 16 ms | 1f 15 ms | 1f 15 ms | 1f 15 ms |
| 1% | 22 ms | 9350 ms | 456 | 20.51 / 20.75 / 25.39 ms | 16.66 / 16.70 / 16.76 ms | 1f 16 ms | 1f 16 ms | 1f 16 ms | 1f 16 ms |
| 10% | 22 ms | 9811 ms | 479 | 20.51 / 20.66 / 23.78 ms | 16.66 / 16.72 / 16.94 ms | 1f 27 ms | 1f 5 ms | 1f 16 ms | 1f 16 ms |

Phase totals (0% / 1% / 10%):

- `paint_288`: 8304 / 8752 / 8555 ms (~410 frames)
- `paint_72`: 495 / 527 / 516 ms
- `collect_288` + `collect_72`: 18 / 63 / 713 ms

Microbench: height 81.5 µs/cell, tile 95.4 µs, pair 96.2 µs (95.0 µs after cap).

## Readout

- First image stays a preview frame (2–22 ms). Fine paint still owns time-to-full.
- Time-to-full dropped ~17% (10.6 s → 8.8 s at 0%; 11.8 s → 9.8 s at 10%). Build p50 stays ~20.5 ms because the open time budget is still 20 ms; more pixels fit in that cap.
- 10% crystal idle p95 29.65 ms → 16.72 ms. Input stays one frame.
- Collect at 10% is still ~0.7 s and is not the dominant cost.
- Headless `process_frame` dt is not a presented GPU frame. Wedge ramps and terrain shading are unchanged (no mesh/shader edits).
