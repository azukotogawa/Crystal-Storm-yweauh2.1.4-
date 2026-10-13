# Technical architecture

## Runtime composition

Godot 4.6+ (Forward+, Jolt Physics) runs `scenes/main.tscn`, the only production main scene. The root boot contract is documented in `main.gd`:

`ConfigService → PerformanceService → GameVisualRegistry → WorldFeatures → VoxelWorld/ChunkManager → TerrainEditor and EntityManager binding → CrystalManager → WorldVisuals refresh`.

`WorldVisuals` separates entities, vegetation, buildings, spawn markers, combat VFX, and feature visuals. Preserve this separation when adding visual systems.

## Terrain and chunks

`InfiniteNoiseWorld` provides deterministic, cached height/tile/biome queries and worker-safe uncached variants. It uses FastNoiseLite, domain warping, biome layout, river carving, border treatment, and optional cave queries. Interior biome naming in live code includes plains, steppe, forest, marsh, and highland; border terrain adds ocean and border-mountain behavior. Do not simplify this to a generic random terrain generator.

`ChunkData` stores 16×16 surface and tile maps plus ramp/geometry metadata. Although legacy constants and cave APIs remain, the streamed renderer is a one-surface-layer heightfield path rather than a fully stored 3D block grid. Terrain edits and feature overrides are snapshotted before worker generation.

`ChunkManager` streams chunks around the player using `WorkerThreadPool`; worker results are tokened so stale work is discarded. It builds greedy top and side surfaces, optional cave faces, terrain-edit strata, and ramp geometry. Main-thread upload is throttled by performance configuration. `ChunkMeshBufferBuilder` prepares MultiMesh buffers; `ChunkView` uploads grouped `MultiMeshInstance3D` nodes and binds the atlas shader (`shaders/ChunkView.gdshader`).

Thread rule: workers may calculate data only. Scene-tree modifications happen on the main thread/deferred path. Always use `ChunkData`/`ChunkManager` APIs for terrain-aware features.

## Player, actions, and combat

`Player` is a `CharacterBody3D` but currently uses custom voxel-aware movement and collision rather than normal body motion. `VoxelFloorProbe` samples heightfield/ramp/crystal walking surfaces. `Camera3D` is orthographic and rotates in 90-degree steps. `ActionTargeting` resolves mouse rays against terrain columns and action mode; `TargetHighlight` renders the feedback box.

`WeaponController` delegates hits to `CombatHitResolver`, affects entities/crystal spawns, and emits feedback signals. Combat VFX are routed through `CombatVisualFeedback` under the `WorldVisuals/CombatVFX` layer.

## Systems and state

- `ConfigService` constructs `GameConfig` and applies world, combat, simulation, content, and performance configuration.
- `PerformanceService` applies LOW/MEDIUM/HIGH/SAFE presets from `CRYSTALSTORM_PERF_PRESET` or `CRYSTALSTORM_SAFE_MODE`.
- `CrystalManager`, `CrystalFluidSim`, and `CrystalChunkLayer` implement crystal pressure flow and its rendering; `VoxelFluidService` handles channels/water.
- `FeatureRegistry` and `TerrainEdits` are central static overlays for procedural terrain. Their snapshots/save encoding are important determinism boundaries.
- `SaveGameService` persists runtime state using JSON-safe codecs under `user://`.
- `GameVisualRegistry` and `CrystalTextureGenerator` supply generated textures/sprites; voxel props are built in `VoxelPropBuilder`.

## Verification and execution

Run the game with `godot .`. Run the current full headless suite with `godot --headless -s scripts/run_all_verify.gd` (which delegates to `scripts/run_all_verify.sh`). The shell runner currently enumerates 68 suites; do not quote an old suite count from `AGENTS.md` or `STABILIZATION.md`.

The runner has explicit terminal-marker handling for selected main-scene probes because Godot teardown can abort after a successful probe. This is harness behavior, not a production-runtime success condition. Use the manual checklist for human validation:

```bash
CRYSTALSTORM_PERF_PRESET=medium godot scenes/main.tscn
```

See `manual_verification.md` and `STABILIZATION.md` for the test gate and known visual/play-feel review items.
