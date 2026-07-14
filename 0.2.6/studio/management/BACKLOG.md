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

## P2 — product definition and content completion

- Define the economy/resource loop, construction constraints, and progression beyond current prototype items.
- Define crystal absorption rewards, enemy unlocks, spawn-point encounter behavior, boss encounter, victory/defeat presentation, and relic role.
- Tune maze/assault pacing and map-scale goals with measurable playtest criteria.
- Define town/ruin/animal gameplay consequences and persistence expectations.

## Engineering hygiene

- Reconcile historical README/AGENTS/STABILIZATION quantitative claims with live code under an explicitly approved documentation pass.
- Keep the runner’s suite list current when adding durable regression coverage.
- Preserve SAFE/LOW/MEDIUM/HIGH behavior during systems work; profile changes against relevant presets.
