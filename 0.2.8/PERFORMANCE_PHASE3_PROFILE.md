# Gameplay frame-time profile (Phase 2 attribution)

**Method:** Headless scripted session on production `main.tscn` (move, dig, jump, melee).
**Preset:** MEDIUM | **Duration:** 45s | **Frames sampled:** 819 | **Captured:** 2026-07-17T15:45:27

Instrumentation via `PerfProfiler` (main vs worker stages; function hotspots).
Measurement only — no gameplay optimization in this run.

## Overall frame time (main thread)

| Metric | ms |
|--------|-----|
| Average | 54.669 |
| 95th percentile | 334.819 |
| Worst frame | 957.136 |
| Implied avg FPS | 18.3 |
| **Unknown main (avg)** | **33.150** |
| Unknown main (p95) | 270.425 |
| Unknown main (worst) | 343.869 |

## Top 10 hottest subsystems (avg ms)

| Rank | Consumer | Avg (ms) | P95 (ms) | Worst (ms) |
|------|----------|----------|----------|------------|
| 1 | untracked | 33.150 | 270.425 | 343.869 |
| 2 | worker_total | 18.451 | 157.461 | 248.264 |
| 3 | chunk_mesh | 13.927 | 110.241 | 168.674 |
| 4 | living_world | 9.381 | 12.249 | 16.206 |
| 5 | chunk_column | 6.640 | 51.770 | 76.602 |
| 6 | crystal_sim | 5.195 | 45.185 | 650.971 |
| 7 | player_physics | 2.004 | 10.031 | 15.226 |
| 8 | entity_physics | 1.009 | 3.700 | 7.269 |
| 9 | town_defense | 0.943 | 1.558 | 2.537 |
| 10 | target_highlight | 0.755 | 1.558 | 2.408 |

## Top 10 hottest functions (avg last-frame ms)

| Rank | Function | Avg (ms) | Max (ms) |
|------|----------|----------|----------|
| 1 | `CrystalManager::_process` | 5.743 | 652.894 |
| 2 | `CrystalManager::_tick_crystal_sim` | 5.195 | 650.952 |
| 3 | `CrystalSimulation::tick` | 3.331 | 101.504 |
| 4 | `Player::_physics_process` | 1.980 | 15.072 |
| 5 | `CrystalManager::_dispatch_sim_events` | 1.261 | 590.089 |
| 6 | `TownDefenseManager::_process` | 0.931 | 2.518 |
| 7 | `ChunkManager::_process` | 0.850 | 9.153 |
| 8 | `ActionTargeting::resolve_action` | 0.719 | 2.355 |
| 9 | `CrystalManager::_build_sim_snapshot` | 0.599 | 15.301 |
| 10 | `CrystalPresentation::flush` | 0.339 | 5.127 |

## Top hitch functions (by max ms)

| Rank | Function | Max (ms) | Avg (ms) |
|------|----------|----------|----------|
| 1 | `CrystalManager::_process` | 652.894 | 5.743 |
| 2 | `CrystalManager::_tick_crystal_sim` | 650.952 | 5.195 |
| 3 | `CrystalManager::_dispatch_sim_events` | 590.089 | 1.261 |
| 4 | `CrystalSimulation::tick` | 101.504 | 3.331 |
| 5 | `CrystalManager::_build_sim_snapshot` | 15.301 | 0.599 |
| 6 | `Player::_physics_process` | 15.072 | 1.980 |
| 7 | `ChunkManager::_process` | 9.153 | 0.850 |
| 8 | `ChunkManager::_on_chunk_ready` | 6.964 | 0.192 |
| 9 | `CrystalPresentation::flush` | 5.127 | 0.339 |
| 10 | `CrystalPresentation::_rebuild_chunk_layer` | 5.067 | 0.316 |

## All tracked consumers (reference)

| Consumer | Avg (ms) | P95 (ms) | Worst (ms) |
|----------|----------|----------|------------|
| untracked | 33.150 | 270.425 | 343.869 |
| worker_total | 18.451 | 157.461 | 248.264 |
| chunk_mesh | 13.927 | 110.241 | 168.674 |
| living_world | 9.381 | 12.249 | 16.206 |
| chunk_column | 6.640 | 51.770 | 76.602 |
| crystal_sim | 5.195 | 45.185 | 650.971 |
| player_physics | 2.004 | 10.031 | 15.226 |
| entity_physics | 1.009 | 3.700 | 7.269 |
| town_defense | 0.943 | 1.558 | 2.537 |
| target_highlight | 0.755 | 1.558 | 2.408 |
| entity_navigation | 0.533 | 1.875 | 4.416 |
| stream_schedule | 0.354 | 2.130 | 5.522 |
| crystal_mesh | 0.343 | 1.946 | 5.141 |
| chunk_apply | 0.234 | 1.574 | 7.099 |
| chunk_buffer | 0.230 | 1.958 | 3.739 |
| chunk_upload | 0.197 | 1.497 | 7.010 |
| map_build | 0.157 | 2.525 | 2.747 |
| ui_overlay | 0.146 | 0.206 | 0.663 |
| debug_panel | 0.142 | 1.868 | 4.327 |
| combat_vfx | 0.065 | 0.093 | 0.329 |
| enemy_spawner | 0.063 | 0.045 | 19.659 |
| vegetation_growth | 0.027 | 0.254 | 0.593 |
| game_manager | 0.024 | 0.033 | 0.173 |
| chunk_view_setup | 0.020 | 0.169 | 1.044 |
| camera_update | 0.017 | 0.023 | 0.122 |
| weapon_controller | 0.014 | 0.019 | 0.067 |
| chunk_scenetree_insert | 0.004 | 0.036 | 0.137 |
| terrain_editor | 0.004 | 0.016 | 0.073 |
| entity_combat | 0.000 | 0.000 | 0.000 |
| stream_update | 0.000 | 0.000 | 0.000 |
| voxel_fluid | 0.000 | 0.000 | 0.000 |
| chunk_manager | 0.000 | 0.000 | 0.000 |
| crystal_manager | 0.000 | 0.000 | 0.000 |

## Notes

- **untracked** — main-thread ms not covered by named *main* sections (worker stages excluded).
- **worker_total / chunk_mesh / chunk_column / chunk_buffer** — worker-attributed; not subtracted from untracked.
- Function rows are per-frame last samples averaged over the session.