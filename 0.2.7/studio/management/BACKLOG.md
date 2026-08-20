# Backlog

This is a prioritized onboarding backlog derived from live code, `manual_verification.md`, and `STABILIZATION.md`. It is not a claim that the listed work is authorized; a human owner should select and refine items before implementation.

## P0 — validate and stabilize the playable foundation

- Obtain a dated human pass/fail in `manual_verification.md`; its checklist is intentionally not auto-signable.
- Resolve reported collision/ramp feel and targeting/highlight placement issues through a display-session review, preserving the existing ramp and targeting regression suite.
- Profile terrain edit rebuild behavior. The documented concern is full chunk regeneration after dig/build; determine acceptable incremental-mesh scope before changing architecture.
- Review crystal visual settling/checkerboard appearance in a real display session. The flow contracts are tested; visual motion still needs human judgment.

## P1 — improve clarity and presentation

- Establish an approved terrain texture/art brief, then update the atlas and visual assets consistently across terrain, ramps, vegetation, crystal spawn markers, and props.
- Audit vegetation/entity representation and scale, especially 3D voxel coverage versus billboard fallbacks and the reported ambiguous prop.
- Improve tool selection and placement feedback only after confirming intended UX with playtest evidence.

## P2 — core gameplay loop (playable prototype)

**Done (2026-07-15):** Headless contracts pass for terrain→crystal routing, viscous flow, spawn combat→victory, full main-scene loop, and progression HUD feedback. Absorption unlocks auto-grant relics (`mason_glove`, `flow_anchor`); `game_overlay` shows coverage/spawn pressure, unlock/relic toasts, and win/lose panels with loss reason.

**Human playtest still needed:** maze fun, defense satisfaction, absorption pacing, assault weapon feel — use dev tools (**T**) and scenario presets; do not auto-edit `manual_verification.md`.

**Deferred (out of P2 slice scope):**
- Full economy/resource loop and construction constraints beyond prototype stone/dig/build.
- Boss multi-phase encounter, expanded enemy roster, long-term relic trees.
- Town/ruin/animal persistence and consequence tuning beyond current hooks.
- Maze/assault pacing balance with formal playtest metrics.

## Engineering hygiene

- Reconcile historical README/AGENTS/STABILIZATION quantitative claims with live code under an explicitly approved documentation pass.
- Keep the runner’s suite list current when adding durable regression coverage.
- Preserve SAFE/LOW/MEDIUM/HIGH behavior during systems work; profile changes against relevant presets.

## Performance measurement (2026-07-15)

**Done:** F3 debug overlay shows structured runtime profiler (FRAME/CHUNKS/CRYSTAL/ENTITIES/RENDER/WORLD). Instrumentation-only — use readings to guide future optimization work, not as FPS targets yet.

**Next (deferred):** Per-loop budget enforcement, edit-latency profiling under sustained dig/build, save/load restore cost — after measurement baseline review.
