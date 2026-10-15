# CRYSTAL STORM — MASTER PROJECT DOCUMENT

**Version:** October 14, 2026  
**Purpose:** Unified game vision, implementation reference, and development roadmap

## 1. Game Identity

Crystal Storm is a 3D voxel action-survival roguelike built in Godot 4. It combines Minecraft-style environmental manipulation with a living crystal corruption that progressively transforms the world.

The defining idea is **a world the player can reshape while a hostile simulation reshapes it in return**.

Design inspirations include Minecraft (editable terrain), Terraria (exploration and progression), Noita (systemic interactions), Hades (combat feel), Vampire Survivors (escalating pressure), Sanctum (player-shaped defenses), Spelunky (emergent consequences), Rain World (environmental hostility), and Zelda (intuitive interaction). These are design references, not features to copy.

Crystal Storm should retain its own identity: spatial problem-solving, terrain manipulation, crystal propagation, water interactions, and pressure that escalates over time.

## 2. Core Gameplay Loop

1. Explore procedurally generated terrain.
2. Dig, gather resources, build, and alter the environment.
3. Observe crystal propagation and identify threats.
4. Manipulate terrain, water, structures, and routes to influence the simulation.
5. Fight crystal creatures and destroy secondary crystal spawn points.
6. Survive increasing pressure while protecting towns and managing crystal coverage.
7. Destroy the origin boss to win before the world is overrun.

The central loop is:

**Explore → Manipulate → Simulate → Adapt → Fight → Progress.**

Maze preparation and assault are the principal gameplay phases. The long-term goal is to make these phases meaningfully distinct and to connect exploration, gathering, combat, and progression into one coherent experience.

## 3. Crystal Simulation — Primary Development Direction

Crystal is the defining world-changing force, not merely an enemy texture or a purple liquid.

The existing implementation includes crystal spawn points, propagation, absorption, power tiers, enemy unlocks, pressure-based behavior, water conductivity interactions, presentation, and persistence.

The intended evolution is a richer simulation in which crystal can:

- Spread through connected terrain and across exposed surfaces.
- Grow into cavities and around obstacles.
- Transform susceptible terrain and create crystalline structures.
- React to water and different materials.
- Interact with walls, bridges, tunnels, ramps, and player-built defenses.
- Accumulate pressure, branch, split, and reconnect where supported by the simulation rules.
- Change the routes, hazards, and strategic possibilities available to the player.

These are design goals, not claims that every behavior already exists. Investigate the current simulation before implementing them. Prefer deterministic, testable propagation rules and localized updates over expensive whole-world recalculation.

Crystal must remain readable: players should understand where it is spreading, what affects it, and how their actions change its behavior.

## 4. Voxel Construction and Destruction

Terrain manipulation must become a strategic toolkit rather than a collection of unrelated input actions.

**Existing foundations:** terrain digging, resource collection, walls, gates, bridges, channels, ramps, terrain edits, chunk remeshing, and persistence.

**Development direction:**

- Make digging and block removal consistent and responsive.
- Expand meaningful placement and terrain-shaping options.
- Support useful walls, trenches, tunnels, bridges, ramps, and defensive layouts.
- Ensure terrain changes update collision, water, crystal, and neighboring geometry correctly.
- Explore material-dependent construction and destruction.
- Investigate structural collapse or terrain deformation only when it adds meaningful gameplay and fits the architecture.

Macro voxels provide efficient large-scale terrain; sparse micro voxels support selected detailed edits and features. The world should not become uniformly oversized cubes: maintain meaningful visual scale and readable terrain silhouettes.

Every new construction or destruction mechanic should interact with the simulation and offer a clear player benefit.

## 5. Water and Environmental Systems

Water, terrain, vegetation, and crystal should form a connected simulation.

The intended interaction loop is: dig a channel or cavity → water occupies the correct space → crystal encounters the altered environment → propagation changes → the player adapts.

Water must occupy actual available space without replacing untouched terrain or floating above the ground. Terrain edits must trigger appropriate fluid updates and visual rebuilding.

Vegetation, animals, ruins, towns, and terrain features already contribute to world behavior and crystal absorption. Improve their interactions and player-facing purpose before adding disconnected environmental systems.

## 6. Combat, Enemies, and Progression

The game includes melee and ranged combat, crystal enemies, spawn-point destruction, enemy unlocks, relic/stat foundations, towns, militia, ruins, wildlife, and vegetation.

The existing victory condition requires destroying all crystal spawn points, with the origin boss sealed until the secondary spawns are eliminated. Loss conditions include player death, excessive crystal coverage, and town loss.

Priorities:

- Make combat readable, responsive, and satisfying.
- Give enemy encounters a meaningful relationship to terrain and crystal behavior.
- Connect relics, consumables, resources, ruins, towns, and combat to rewards and progression.
- Make the boss encounter more distinctive than an ordinary enemy with more health.
- Preserve the strategic value of spatial control and preparation.

## 7. World, Visuals, and Presentation

The world uses seeded terrain generation, biomes, rivers, varied elevations, vegetation, structures, ruins, towns, and crystal spawn points. The presentation currently uses a mixture of authored assets and generated placeholder visuals.

The visual direction is stylized, readable, and voxel-based, with a clear sense of terrain scale and an increasingly corrupted world. Terrain materials should eventually resemble stylized pixel-art materials rather than flat colors with noise. Crystal growth should feel organic and continuous rather than like a checkerboard of isolated markers.

The player uses an isometric orthographic camera with smooth rotation and zoom. HUD elements communicate the crystal threat, current phase, tools, and world state.

Replace placeholders incrementally. Do not undertake a wholesale art replacement before the gameplay and simulation are coherent.

## 8. Technical Architecture and Constraints

- **Engine:** Godot 4; the latest saved inspection records Godot 4.7.
- **World:** chunked 3D terrain with macro surface data and sparse micro terrain.
- **Terrain pipeline:** snapshots → column generation → mesh generation → buffer preparation → application.
- **Rendering:** greedy meshing, chunk streaming, cached mesh plans, and localized rebuilding.
- **Terrain edits:** routed through the terrain/world-state services.
- **Crystal:** simulation model, snapshot, fluid simulation, events, presentation, and manager façade.
- **Water:** fluid service/engine and channel state.
- **Gameplay:** player, targeting, weapons, combat, entities, inventory, relics, towns, vegetation, and spawn management.
- **Verification:** `scripts/run_all_verify.sh`, focused verification scripts, smoke tests, and manual runtime checks.
- **Performance target:** MEDIUM preset is the primary development target; avoid expensive whole-world work and unmeasured threading changes.

The architecture is already substantial. Extend existing systems where practical. Avoid replacing working subsystems or confusing visual fixes with simulation fixes.

## 9. Current State and Known Risks

The project has reached a locally playable 0.3.0 milestone. The latest iinventedlight progress note records combat, effects/game feel, and menus/settings/accessibility as merged, with additional merge cleanup and art work remaining.

The broader technical audit identifies important risks:

- Crystal simulation can cause substantial frame-time spikes.
- Crystal visuals and propagation patterns need improvement.
- Several systems exist without complete reward or progression loops.
- Some fluid behavior and visual feedback remain incomplete or require runtime verification.
- The automated suite and manual verification do not cover every runtime behavior.
- Historical documentation may disagree with the live implementation.

These findings are dated observations, not a substitute for inspecting the current repository. Confirm the present state before acting on any listed issue.

## 10. Development Priorities

1. **Crystal simulation:** improve propagation, terrain interaction, readability, and performance.
2. **Voxel manipulation:** expand meaningful ways to build, shape, and break terrain.
3. **System integration:** make terrain, water, crystal, collision, and chunk rebuilding agree.
4. **Gameplay glue:** connect gathering, combat, towns, ruins, relics, and consumables to rewards.
5. **Playability:** verify the complete run from world entry through victory or defeat.
6. **Presentation:** improve crystal visuals, terrain materials, animations, sound, and feedback.
7. **Performance and release quality:** profile representative gameplay and verify changes.

## 11. Autonomous Agent Protocol

Agents should treat repository code and current Studio documentation as the authority for implementation details.

1. Read `AGENTS.md`, `studio/NOW.md`, relevant design documents, and the relevant code.
2. Identify the highest-value concrete task within the current development priority.
3. Investigate before editing; establish the actual runtime path and root cause.
4. Implement the smallest coherent change that advances the game.
5. Add focused regression tests for important simulation rules.
6. Run relevant tests and perform real runtime verification when available. Never claim an unexecuted test passed.
7. Update `studio/NOW.md` with verified results, remaining issues, and the next task.
8. Avoid unrelated refactors, giant repeated prompts, and unnecessary full-suite runs during iteration. Run the full suite at meaningful milestones.

**The mission:** Build a coherent, compelling 3D voxel world in which the player can reshape the environment, crystal actively transforms it, and every system contributes to an escalating struggle for control of the world.
