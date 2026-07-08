# Legacy / Archived Files

These files are **not used** by the active game (`scenes/main.tscn`).

| File | Reason archived |
|------|-----------------|
| `main.tscn` | Old root scene; used `test_visuals.gd` on Game root. Superseded by `scenes/main.tscn`. |
| `world_viewer.tscn` | Duplicate of `scenes/world_viewer.tscn` (2D texture biome viewer). |
| `src_world/infinite_noise_world.gd` | Godot 3–style 2D `NoiseWorld` prototype. Active 3D gen is `world/InfiniteNoiseWorld.gd`. |
| `verify_river_specs.gd` | Standalone river QA script (not part of CI verify suite). |
| `debug_drainage_patch.gd` | One-off drainage debug harness. |

Debug harness for visuals: `scripts/debug/test_visuals.gd` (attach to Game root temporarily).