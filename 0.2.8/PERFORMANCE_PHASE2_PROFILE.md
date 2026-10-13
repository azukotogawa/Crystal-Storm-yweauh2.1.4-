# Gameplay frame-time profile (Phase 2 attribution)

**Method:** Headless scripted session on production `main.tscn` (move, dig, jump, melee).
**Preset:** MEDIUM | **Duration:** 45s | **Frames sampled:** 799 | **Captured:** 2026-07-17T15:34:00

Instrumentation via `PerfProfiler` (main vs worker stages; function hotspots).
Measurement only — no gameplay optimization in this run.

## Overall frame time (main thread)

| Metric | ms |
|--------|-----|
| Average | 56.161 |
| 95th percentile | 291.521 |
| Worst frame | 578.573 |
| Implied avg FPS | 17.8 |
| **Unknown main (avg)** | **36.237** |
| Unknown main (p95) | 248.286 |
| Unknown main (worst) | 299.496 |

## Top 10 hottest subsystems (avg ms)

| Rank | Consumer | Avg (ms) | P95 (ms) | Worst (ms) |
|------|----------|----------|----------|------------|
| 1 | untracked | 36.237 | 248.286 | 299.496 |
| 2 | worker_total | 19.526 | 132.074 | 425.854 |
| 3 | chunk_mesh | 15.602 | 90.271 | 273.935 |
| 4 | living_world | 8.195 | 9.367 | 12.613 |
| 5 | chunk_column | 7.322 | 42.739 | 148.314 |
| 6 | crystal_sim | 4.964 | 41.879 | 562.520 |
| 7 | player_physics | 1.634 | 8.064 | 14.537 |
| 8 | town_defense | 1.585 | 2.622 | 3.242 |
| 9 | entity_physics | 0.913 | 3.386 | 8.842 |
| 10 | target_highlight | 0.698 | 1.333 | 1.884 |

## Top 10 hottest functions (avg last-frame ms)

| Rank | Function | Avg (ms) | Max (ms) |
|------|----------|----------|----------|
| 1 | `CrystalManager::_process` | 5.379 | 563.472 |
| 2 | `CrystalManager::_tick_crystal_sim` | 4.963 | 562.503 |
| 3 | `CrystalSimulation::tick` | 3.250 | 115.331 |
| 4 | `Player::_physics_process` | 1.614 | 14.423 |
| 5 | `TownDefenseManager::_process` | 1.577 | 3.227 |
| 6 | `CrystalManager::_dispatch_sim_events` | 1.167 | 514.502 |
| 7 | `ChunkManager::_process` | 0.798 | 10.719 |
| 8 | `ActionTargeting::resolve_action` | 0.667 | 1.843 |
| 9 | `CrystalManager::_build_sim_snapshot` | 0.544 | 12.072 |
| 10 | `CrystalPresentation::flush` | 0.342 | 5.807 |

## Top hitch functions (by max ms)

| Rank | Function | Max (ms) | Avg (ms) |
|------|----------|----------|----------|
| 1 | `CrystalManager::_process` | 563.472 | 5.379 |
| 2 | `CrystalManager::_tick_crystal_sim` | 562.503 | 4.963 |
| 3 | `CrystalManager::_dispatch_sim_events` | 514.502 | 1.167 |
| 4 | `CrystalSimulation::tick` | 115.331 | 3.250 |
| 5 | `Player::_physics_process` | 14.423 | 1.614 |
| 6 | `CrystalManager::_build_sim_snapshot` | 12.072 | 0.544 |
| 7 | `ChunkManager::_process` | 10.719 | 0.798 |
| 8 | `ChunkManager::_on_chunk_ready` | 8.566 | 0.202 |
| 9 | `CrystalPresentation::flush` | 5.807 | 0.342 |
| 10 | `CrystalPresentation::_rebuild_chunk_layer` | 5.741 | 0.320 |

## All tracked consumers (reference)

| Consumer | Avg (ms) | P95 (ms) | Worst (ms) |
|----------|----------|----------|------------|
| untracked | 36.237 | 248.286 | 299.496 |
| worker_total | 19.526 | 132.074 | 425.854 |
| chunk_mesh | 15.602 | 90.271 | 273.935 |
| living_world | 8.195 | 9.367 | 12.613 |
| chunk_column | 7.322 | 42.739 | 148.314 |
| crystal_sim | 4.964 | 41.879 | 562.520 |
| player_physics | 1.634 | 8.064 | 14.537 |
| town_defense | 1.585 | 2.622 | 3.242 |
| entity_physics | 0.913 | 3.386 | 8.842 |
| target_highlight | 0.698 | 1.333 | 1.884 |
| entity_navigation | 0.426 | 1.591 | 4.934 |
| stream_schedule | 0.372 | 1.818 | 4.501 |
| crystal_mesh | 0.346 | 1.824 | 5.821 |
| chunk_buffer | 0.245 | 1.789 | 3.605 |
| chunk_apply | 0.216 | 1.472 | 4.866 |
| chunk_upload | 0.206 | 1.444 | 4.836 |
| map_build | 0.162 | 2.541 | 2.689 |
| ui_overlay | 0.121 | 0.149 | 0.631 |
| debug_panel | 0.117 | 1.702 | 4.938 |
| combat_vfx | 0.053 | 0.071 | 0.089 |
| enemy_spawner | 0.030 | 0.037 | 8.302 |
| vegetation_growth | 0.026 | 0.252 | 0.371 |
| chunk_view_setup | 0.022 | 0.179 | 0.578 |
| game_manager | 0.021 | 0.025 | 0.176 |
| camera_update | 0.015 | 0.017 | 0.032 |
| weapon_controller | 0.012 | 0.014 | 0.022 |
| chunk_scenetree_insert | 0.004 | 0.031 | 0.064 |
| terrain_editor | 0.003 | 0.013 | 0.021 |
| entity_combat | 0.000 | 0.000 | 0.000 |
| stream_update | 0.000 | 0.000 | 0.000 |
| voxel_fluid | 0.000 | 0.000 | 0.000 |
| chunk_manager | 0.000 | 0.000 | 0.000 |
| crystal_manager | 0.000 | 0.000 | 0.000 |

## Notes

- **untracked** — main-thread ms not covered by named *main* sections (worker stages excluded).
- **worker_total / chunk_mesh / chunk_column / chunk_buffer** — worker-attributed; not subtracted from untracked.
- Function rows are per-frame last samples averaged over the session.