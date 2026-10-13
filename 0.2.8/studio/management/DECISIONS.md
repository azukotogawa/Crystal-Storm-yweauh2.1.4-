# Architectural and documentation decisions

## Current decisions

| Decision | Rationale | Evidence |
|---|---|---|
| `scenes/main.tscn` is the only production scene. | Prevents legacy prototype paths from re-entering active runtime. | `AGENTS.md`, `project.godot` |
| New gameplay uses the 3D voxel-heightfield path. | It is the active renderer, player, edit, and streaming architecture. | `chunks/`, `player/`, `world/` |
| Terrain state is column/surface based. | Performance depends on 16×16 maps, greedy surface mesh generation, and overlays rather than a stored full-volume grid. | `ChunkData`, `ChunkManager` |
| Chunk generation is asynchronous and tree changes stay main-thread. | Prevents streaming stalls and thread-unsafe node mutation. | `ChunkManager`, `AGENTS.md` |
| Performance is configured via named presets. | Streaming, fluids, visuals, entities, and map work need coordinated budgets. | `PerformanceService`, `PerformanceQualityConfig` |
| Human verification remains a release gate. | Automated probes cannot validate visual quality, control feel, or a real play session. | `manual_verification.md`, `STABILIZATION.md` |
| Developer assistance is local/file-bridged. | In-game messages write/poll JSONL and local slash commands operate in the scene; no external service is implied. | `DeveloperAssistant` |
| Persistent overlays are owned by session-scoped `WorldState`. | Single write authority with domain revisions, frozen worker snapshots, and façade compatibility; avoids dual static storage. | `world/world_state.gd`, façades, `ChunkData.capture_worker_snapshot` |

## Decisions requiring human clarification

- Is the target terrain model permanently a heightfield with limited cave support, or is full volumetric editing a future product requirement?
- What exact gameplay consequences and progression should absorption, towns, ruins, and relics provide?
- What are the acceptance criteria for crystal visual behavior, terrain texture style, and voxel-versus-billboard representation?
- What edit responsiveness target justifies incremental meshing rather than current chunk regeneration?
- Which old root documents should be formally updated, and who owns that reconciliation?
