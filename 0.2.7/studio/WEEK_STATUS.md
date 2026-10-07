# Week Status

Compact status derived from `BACKLOG.md`, `PROJECT_KNOWLEDGE.md` sessions (through 2026-07-15), `SYSTEM_HANDOFF.md`, and `NOW.md`.

## Accomplished

### Stabilization (P0 foundation)
- Forward targeting / melee / build highlight contracts and probes
- Live floor-probe collision with terrain edits (no stale snapshot walk-through)
- Ramp step-corner walk probes (isolated + main scene)
- Crystal frontier density (no checkerboard holes under production tick)
- Adaptive rebuild ring (0 interior / 1 edge band) for ramp lips
- Building input: walls/bridges as WorldObjects, LMB remove-first, bridge walkable without fill
- Camera: Q/E yaw, edge scroll off; WASD stays camera-relative
- Corner / diagonal ramp mesh: slope + low floor triangles, unshaded hemisphere fill
- P2 core loop (headless): terrain→crystal routing, viscous flow, spawn combat→victory, progression HUD (unlocks + relic grants + loss reason)

### Tooling
- Runtime profiler in F3 (FRAME / CHUNKS / CRYSTAL / ENTITIES / RENDER / WORLD) — measurement only
- Large headless suite (95–97 probes recorded in knowledge; keep runner list current)
- Smoke + display session paths with honest forward-arc and collision markers

### Human gate
- Earlier foundation human pass recorded in knowledge (Kuroe). Live visual/feel items remain open for the current integration slice.

## Remains (active)

1. **Live window verification** of the recent integration (from `NOW.md`):
   - cardinal + corner ramps (footprint, approach floor, shading)
   - dig region correctness
   - ordinary place ≠ accidental structure
   - crystal visibility
   - camera yaw + movement consistency
   - LMB/RMB building contract
2. Human walk of a mid-plateau generated corner ramp (`SYSTEM_HANDOFF` next action)
3. Any real P0/P1 gameplay-visible bugs found during that play
4. Crystal motion / settling feel (contracts pass; human judgment still needed)

## Current priority

**Stabilize the current cross-slice in a real window.**  
Fix only real P0/P1 visible bugs. Do not start new features, persistence UI, or terrain art.

After the live slice is clean → begin reusable content architecture (data-driven items/relics/enemies/etc.), not large content dumps.

## Deferred (explicitly out of scope now)

- Full economy / crafting / weapon tiers
- Boss multi-phase, expanded enemy roster, long relic trees
- Town/ruin/animal consequence tuning beyond current hooks
- Formal maze/assault balance metrics
- Incremental mesh architecture (only after measured edit hitch)
- Terrain texture art brief and atlas overhaul
- Underground camera / occlusion / lighting
- Per-loop budget enforcement and sustained edit-latency optimization
- Documentation reconciliation of historical README/AGENTS counts

## Performance note

MEDIUM is the target preset. Do not tune HIGH until a representative windowed profile exists. Profiler is instrumentation-only.
