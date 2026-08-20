# Performance

## Current performance model

Performance is controlled by `PerformanceService` and `PerformanceQualityConfig`. Presets affect chunk streaming, crystal simulation, map updates, entities, vegetation, visuals, combat VFX, and profiler behavior.

The game already includes several budget mechanisms:

- chunk render distance,
- max chunks per frame,
- max inflight chunks,
- chunk upload budget,
- crystal sim frequency/caps,
- crystal mesh rebuild caps,
- map rebuild cadence,
- entity and vegetation caps,
- safe mode.

## Connected systems

- `PerformanceService` applies runtime quality policy.
- `PerfProfiler` records timing and gauges.
- `ChunkManager` uses worker and upload budgets.
- `CrystalManager` uses sim and mesh budgets.
- `TopographicalMap` uses rebuild/sample budgets.
- `EntityManager` and `VegetationGrowthManager` use spawn/tick caps.
- `GameVisualRegistry`, `FeatureVisualLayer`, and `CombatVisualFeedback` use visual enable/limit flags.

## Gameplay impact

Performance settings directly affect:

- visible horizon,
- crystal simulation rate,
- enemy/entity density,
- vegetation growth,
- map fidelity,
- visual richness,
- combat feedback.

## Known risks

- Terrain edits fan out into chunk rebuilds, movement queries, crystal queries, visuals, map, and save state.
- Crystal simulation touches terrain, absorption, enemy unlocks, visuals, and player/town loss conditions.
- Visual refresh can cascade through registry, feature layers, entities, spawn markers, and VFX.

## Incomplete tooling

The profiler exists, but gameplay-facing performance budgets need clearer per-loop reporting: edit latency, crystal tick cost, chunk upload cost, visual refresh cost, and save/load restore cost.

