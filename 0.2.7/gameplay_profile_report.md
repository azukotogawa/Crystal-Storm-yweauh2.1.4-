# Gameplay frame-time profile

**Method:** Headless scripted session on production `main.tscn` (move, dig, jump, melee).
**Preset:** MEDIUM | **Duration:** 45s | **Frames sampled:** 754 | **Captured:** 2026-07-17T15:12:31

Instrumentation via `PerfProfiler` per-frame snapshots (last-frame section ms + worker + untracked).
No optimization applied — measurement only.

## Overall frame time (main thread)

| Metric | ms |
|--------|-----|
| Average | 59.529 |
| 95th percentile | 295.725 |
| Worst frame | 649.992 |
| Implied avg FPS | 16.8 |

## Top five frame-time consumers

| Rank | Consumer | Avg (ms) | P95 (ms) | Worst (ms) |
|------|----------|----------|----------|------------|
| 1 | untracked | 30.340 | 138.745 | 302.477 |
| 2 | worker_total | 21.209 | 138.363 | 222.745 |
| 3 | chunk_mesh | 16.328 | 92.765 | 150.578 |
| 4 | crystal_sim | 10.066 | 57.919 | 626.174 |
| 5 | chunk_column | 7.642 | 44.592 | 74.383 |

## All tracked consumers (reference)

| Consumer | Avg (ms) | P95 (ms) | Worst (ms) |
|----------|----------|----------|------------|
| untracked | 30.340 | 138.745 | 302.477 |
| worker_total | 21.209 | 138.363 | 222.745 |
| chunk_mesh | 16.328 | 92.765 | 150.578 |
| crystal_sim | 10.066 | 57.919 | 626.174 |
| chunk_column | 7.642 | 44.592 | 74.383 |
| entity_physics | 0.930 | 3.376 | 5.782 |
| crystal_mesh | 0.432 | 2.223 | 4.771 |
| entity_navigation | 0.432 | 1.609 | 3.280 |
| stream_schedule | 0.385 | 1.792 | 4.660 |
| chunk_buffer | 0.273 | 1.838 | 4.093 |
| chunk_apply | 0.228 | 1.485 | 6.600 |
| chunk_upload | 0.227 | 1.469 | 6.560 |
| map_build | 0.217 | 2.563 | 2.703 |
| debug_panel | 0.189 | 1.782 | 3.241 |
| vegetation_growth | 0.058 | 0.285 | 0.408 |
| entity_combat | 0.000 | 0.000 | 0.000 |

## Notes

- **untracked** — main-thread time not attributed to a named profiler section.
- **worker_total** — chunk mesh/buffer work attributed to worker threads (same wall period, not additive with frame budget).
- Section timings are per-frame last values; sparse work (e.g. chunk_mesh) averages low but P95/worst capture spikes.