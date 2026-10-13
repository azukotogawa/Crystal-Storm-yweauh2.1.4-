# Crystal Storm Quarterly Development Roadmap

Scope: one autonomous engineer, 12 weeks, starting from the current 3D Godot production runtime. The goal is not "more systems"; it is to turn the existing prototype into a stable, replayable vertical slice where terrain shaping, crystal pressure, combat, and progression form a coherent loop.

This roadmap assumes the live architecture in `AI_CONTEXT.md`, `STABILIZATION.md`, and `studio/management/BACKLOG.md`. Human playtest sign-off remains required for visual and feel claims.

## Quarter Goal

By the end of the quarter, Crystal Storm should have a playable vertical slice:

- The game boots reliably on LOW/MEDIUM/HIGH/SAFE presets.
- Terrain dig/build/plant/channel actions are understandable and stable.
- Crystal flow creates readable pressure that responds to terrain.
- The player can prepare during a maze phase, fight during an assault phase, destroy spawn points, and win a short run.
- Core saves, map, UI feedback, and dev tools support iteration.
- Known P0 visual/collision/targeting issues are either resolved or explicitly documented with reproduction cases.

Non-goals for this quarter:

- Full economy.
- Full boss encounter.
- Large enemy roster.
- Finished art direction.
- Full-volume Minecraft-like voxel simulation.
- Major architecture rewrite.

## Critical Path

The critical path is:

1. Stabilize playable foundation.
2. Make terrain actions readable and reliable.
3. Make crystal response readable and fun.
4. Connect maze preparation to assault outcomes.
5. Add enough progression/rewards to motivate repeat runs.
6. Harden save/load, perf presets, and verification.

Do not begin broad content expansion until P0 feel/clarity defects are controlled. More enemies, relics, or buildings will not help if targeting, collision, ramps, or crystal readability remain confusing.

## Dependencies

Hard dependencies:

- Terrain editing depends on `TerrainEditor`, `TerrainEdits`, `ChunkManager`, chunk rebuild scope, and `VoxelFloorProbe`.
- Crystal readability depends on `CrystalTerrainQuery`, `CrystalFluidSim`, `CrystalChunkLayer`, chunk-loaded policy, and visual rebuild budgets.
- Combat feel depends on `ActionTargeting`, `WeaponController`, `CombatHitResolver`, `CombatVisualFeedback`, entity/spawn signals, and camera rotation correctness.
- Progression depends on inventory, stats, relic unlocks, absorption/evolution, and clear UI feedback.
- Persistence depends on canonical overlays loading before chunks and runtime systems restore.
- Manual "Working" claims depend on `manual_verification.md` human sign-off.

Soft dependencies:

- Texture/art improvements should follow a short art brief so atlas, props, crystal markers, and UI do not drift.
- Balance work should follow telemetry/dev-tool improvements so changes are measurable.
- New content should follow scenario presets so it can be tested quickly.

## Parallel Work

With one engineer, true parallel execution is limited. Use low-risk background tracks that can advance between critical-path tasks:

- Documentation: keep `AI_CONTEXT.md`, `STABILIZATION.md`, and backlog notes current after major changes.
- Verification: add focused `verify_*.gd` probes alongside fixes.
- Dev tooling: improve scenario presets, bug bundles, and debug overlays while waiting on playtest feedback.
- Asset polish: update isolated textures/voxel props only when they do not disturb runtime contracts.
- Balance tables: tune config resources after systems are stable.

Avoid parallelizing by opening multiple architecture fronts at once. For this project, context switching across terrain, crystal, saves, and visuals is a reliability risk.

## Tooling Plan

Required maintenance:

- Keep `scripts/run_all_verify.sh` as the authoritative durable suite list.
- Keep smoke/display scripts aligned with current input bindings.
- Preserve LOW/MEDIUM/HIGH/SAFE boot checks.
- Add scenario presets for repeatable maze, combat, crystal-flow, and save/load situations.
- Improve bug-report bundles so playtest issues capture seed, position, phase, selected item, perf preset, loaded chunks, crystal stats, and recent actions.

Useful additions this quarter:

- A "playtest snapshot" dev command that records seed, player column, camera rotation, inventory, current target, crystal coverage, spawn states, and nearest terrain edit.
- A crystal-flow debug overlay that shows pressure/frontier/source influence without requiring code inspection.
- A terrain-edit rebuild profiler view that shows chunks rebuilt per action and upload cost.
- A short manual test script for human playtesters with expected observations and repro fields.

## Technical Debt Budget

Reserve roughly 25-30% of the quarter for technical debt and verification. Debt work must be tied to playability, stability, or iteration speed.

Priority debt:

- Rebuild scope: reduce unnecessary terrain edit rebuild cost without breaking neighbor lips, ramps, or stacked walls.
- Collision/ramp contract: consolidate assumptions across player, entities, `VoxelFloorProbe`, mesh geometry, and tests.
- Targeting contract: keep dig/build/attack using one resolver across camera rotations.
- Visual readiness boot contract: prevent config/perf/visual/features/chunks wait cycles.
- Save/load ordering: ensure new canonical state is persisted and restored before derived systems rebuild.
- Atlas/prop pipeline: document and enforce production atlas layout and voxel prop scale conventions.
- Test suite hygiene: remove stale assumptions, add missing probes, and keep abrupt-exit OK markers intentional.

Debt to defer:

- Full 3D voxel storage rewrite.
- Broad ECS-style entity rewrite.
- Renderer replacement.
- Large save format migration unless needed for vertical slice data.

## Milestones

### Milestone 1: Stabilization Gate

Target: weeks 1-2.

Outcome: the current playable foundation is trustworthy enough for feature work.

Deliverables:

- Re-run and update P0 stabilization status based on current code.
- Complete a human playtest pass using `manual_verification.md` without auto-editing human results.
- Fix or reproduce P0 defects in targeting, highlights, collision, ramps, stacked build mesh, terrain atlas, crystal checkerboard flow, and entity/vegetation visuals.
- Confirm LOW/MEDIUM/HIGH/SAFE boot behavior.
- Add missing focused tests for any fixed P0 regression.

Exit criteria:

- `godot --headless -s scripts/run_all_verify.gd` passes or failures are triaged with owner notes.
- `bash scripts/run_smoke_gameplay.sh` and display session probes pass where environment allows.
- Human playtest notes are converted into concrete issues.
- No new feature work is blocked by unknown P0 behavior.

Risk:

- Ramp/collision fixes may expose mesh/pathing mismatch.
- Display-only issues may require more manual iteration than expected.

### Milestone 2: Terrain Action Clarity

Target: weeks 3-4.

Outcome: the maze phase controls are readable and satisfying at prototype quality.

Deliverables:

- Clear selected item/tool state in hotbar/UI.
- Reliable orange/green/red target highlight for dig/build/attack across camera rotations.
- Build placement preview that shows exact target cell and height.
- Dig/build/channel/plant failure feedback that explains common blockers without noisy text.
- Terrain edit rebuild profiling and scoped optimization plan.
- Fix high-impact collision and ramp traversal defects found in Milestone 1.

Exit criteria:

- A player can dig, build, plant/channel, rotate camera, and understand the targeted cell.
- Relevant targeting, highlight, terrain, ramp, and collision verification passes.
- Terrain edits do not cause unacceptable frame spikes on medium preset during basic playtest.

Risk:

- Highlight correctness may require coordinate cleanup in `ActionTargeting`, `WorldVisualCoords`, and `VoxelFloorProbe`.

### Milestone 3: Crystal Pressure Readability

Target: weeks 5-6.

Outcome: crystal spread visibly responds to terrain and creates strategic pressure.

Deliverables:

- Tune pressure-flow behavior for slow pooling/settling instead of checkerboard-looking expansion.
- Improve crystal visual continuity within current MultiMesh budget.
- Expose debug/readout for coverage, frontier pressure, spawn pressure, and blocked/channeled flow.
- Verify water/channels/buildings/plants affect crystal routing consistently.
- Ensure crystal contact/loss rules are clear in UI and `GameManager`.

Exit criteria:

- A test maze visibly delays or redirects crystal flow.
- Crystal flow remains bounded by performance caps.
- Crystal routing, settling, spread-limit, and terrain-routing probes pass.
- Human playtest can describe why the crystal moved the way it did.

Risk:

- Better visuals may require mesh rebuild changes; keep within existing chunk-layer budget.

### Milestone 4: Vertical Slice Loop

Target: weeks 7-8.

Outcome: one short run has a beginning, pressure curve, assault, victory/loss, and restartable loop.

Deliverables:

- Tune maze-to-assault phase thresholds.
- Ensure spawn destruction, origin/source goal, victory state, and loss reasons are clear.
- Add or refine one scenario preset for a 10-15 minute vertical-slice run.
- Make topographical map useful for crystal pressure, spawn locations, player position, and terrain constraints.
- Ensure core loop works after quick save/load.

Exit criteria:

- From a fresh run, a player can prepare, fight, destroy spawns, and win or lose with clear feedback.
- Full-loop, spawn-goal, maze-phase, topographical-map, combat-crystal-damage, and save-slot probes pass.
- Manual playtest identifies tuning issues rather than missing loop pieces.

Risk:

- Save/load and phase state can break if new loop state is not canonicalized.

### Milestone 5: Progression And Content Slice

Target: weeks 9-10.

Outcome: the run has enough rewards and variety to make repeated testing meaningful.

Deliverables:

- Tune absorption unlocks and relic grants for a short run.
- Add or refine 2-3 buildable/plantable/relic choices that create real terrain-strategy tradeoffs.
- Tune enemy/spawn pressure around crystal tier and absorbed features.
- Improve resource gain/cost pacing for dig/build/plant/channel actions.
- Ensure UI toasts/HUD communicate unlocks, relics, spawn pressure, and current goal.

Exit criteria:

- Player decisions during maze phase materially change assault difficulty.
- No new content bypasses inventory, config, save/load, or verification paths.
- Progression feedback and combat/entity tests pass.

Risk:

- Content tuning may mask system issues. If a mechanic is confusing, fix clarity before adding variants.

### Milestone 6: Hardening And Release Candidate

Target: weeks 11-12.

Outcome: a stable vertical-slice build is ready for broader feedback.

Deliverables:

- Full verification sweep and targeted fixes.
- Performance pass on LOW/MEDIUM/HIGH/SAFE.
- Save/load abuse pass.
- Display-session and human manual verification pass.
- Update `AI_CONTEXT.md`, `STABILIZATION.md`, backlog, and any architecture notes changed by the quarter.
- Package a short playtest guide: controls, goal, expected duration, known issues, feedback prompts.

Exit criteria:

- Full headless suite passes or has explicitly accepted non-blocking failures.
- Manual verification has a dated human result.
- A new tester can complete or fail a run without developer explanation.
- Known issues are tracked and do not obscure the vertical-slice goal.

Risk:

- End-of-quarter stabilization can expand if earlier milestones defer too many P0 issues.

## Playability Targets

Minimum acceptable vertical-slice experience:

- Time to first control: under 30 seconds on medium preset in a normal local run.
- First meaningful terrain action: under 2 minutes.
- First visible crystal pressure: under 5 minutes.
- First combat encounter: under 8 minutes.
- Short run length: 10-20 minutes.
- Player always has a clear current goal: prepare, redirect, survive, destroy spawn, push source.
- Loss explains cause.
- Victory is reachable without dev commands in the tuned scenario.

Qualitative targets:

- Terrain editing should feel like the main strategic verb, not a side tool.
- Crystal should look inevitable but understandable.
- Combat should be brief pressure relief or assault, not the entire game.
- The map should help planning rather than simply display terrain.
- UI should clarify state without explaining the design in paragraphs.

## Resource Allocation

Approximate single-engineer split:

- 30% stabilization, tests, boot/perf/save safety.
- 25% terrain action feel and collision/targeting.
- 20% crystal readability and loop tuning.
- 15% progression/content slice.
- 10% tooling, documentation, playtest support.

If behind schedule, cut content breadth first. Keep stabilization, terrain clarity, crystal readability, and loop completion.

## Decision Gates

Gate A: after Milestone 1.

- If P0 collision/targeting/ramp issues remain severe, extend stabilization and defer progression.

Gate B: after Milestone 3.

- If crystal flow is not readable, do not add more enemies/relics. Fix crystal presentation and terrain response first.

Gate C: after Milestone 4.

- If the vertical loop is not complete, cut Milestone 5 breadth and focus on one good run.

Gate D: week 11.

- Freeze new gameplay features. Only fixes, tuning, docs, tests, and playtest support.

## Quarter-End Definition Of Done

The quarter is successful if:

- There is one stable, documented, playable vertical slice.
- Terrain editing, crystal response, combat, progression, save/load, and UI operate as one loop.
- Automated verification protects the main contracts.
- Human playtest feedback is concrete and reproducible.
- Future work can shift from "make it hold together" to "make it deeper."
