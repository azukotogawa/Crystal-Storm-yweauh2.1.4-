# Studio Index

Compact map of `/studio`. Do not duplicate project facts here. Point agents to the right document; do not restate content.

## Core operating docs

| File | Purpose |
|------|---------|
| `NOW.md` | Single current objective, today’s checklist, stop condition |
| `WEEK_PLAN.md` | Weekly priorities and agent division |
| `AGENT_LOOP.md` | Short-cycle process and handoff format |
| `SYSTEM_HANDOFF.md` | Latest systems change + known problems + next action |
| `CONTENT_DIRECTOR.md` | Content rules (expand existing, depth over breadth, playable) |
| `STUDIO_CONSTITUTION.md` | Studio values, human vs AI ownership, definition of done |

## Contracts (must not drift)

| File | Purpose |
|------|---------|
| `INPUT_CONTRACT.md` | Fixed input bindings (WASD, Q/E, LMB/RMB, Tab, sword ≠ dig) |
| `PLAYTEST_VISUAL_CONTRACT.md` | Ramp geometry, coordinate language, edit/remesh, screenshot rule |
| `ALPHA_VISUAL_CONTRACT.md` | Terrain fidelity, scale, corner-ramp validity, crystal future constraints |

## Domain briefs (implemented surface only)

| File | Purpose |
|------|---------|
| `Terrain.md` | Dig/build/channel loop and incomplete parts |
| `Crystal.md` | Pressure, absorption, spawn victory/loss |
| `Chunking.md` | Streaming model and known gaps |
| `Combat.md` | Weapon → hit → spawn damage loop |
| `Player.md` | Movement, targeting, progression gaps |
| `Inventory.md` | Hotbar/materials and missing economy |
| `Rendering.md` | Heightfield MultiMesh path |
| `World.md` | Seed + overlays + feature roles |
| `Performance.md` | Presets and budget risks |
| `DeveloperTools.md` | Dev chat, F3, scenarios, verification |
| `UI.md` | Theme, tooltips, settings, tutorial, run summary |

## Architecture & knowledge (read only when needed)

| File | Purpose |
|------|---------|
| `ENGINE_ARCHITECTURE.md` | Production path, boot, chunk/crystal/save flows |
| `PROJECT_GRAPH.md` | Ownership, signals, communication graph |
| `ENGINEERING_AUDIT.md` | Ranked architectural risks and 90-day sequence |
| `TECHNICAL.md` | Short technical summary |
| `AI_DEVELOPMENT.md` | Safe change paths and verification discipline |
| `DECISIONS.md` | Locked decisions + open human questions |
| `PROJECT_KNOWLEDGE.md` | Session history, drift notes, learned contracts |
| `BACKLOG.md` | Prioritized remaining work (P0–P2) |
| `IDENTITY.md` / `VISION.md` / `GAMEPLAY.md` / `PILLARS.md` | Product intent (do not restate in every task) |
| `README.md` | Studio entry and status language |

## What to read by task type

| Task type | Read first |
|-----------|------------|
| Any task | `NOW.md` → `SYSTEM_HANDOFF.md` → `AGENT_LOOP.md` |
| Ramps / terrain visual | `PLAYTEST_VISUAL_CONTRACT.md`, `ALPHA_VISUAL_CONTRACT.md`, `Terrain.md` |
| Input / targeting / building | `INPUT_CONTRACT.md`, `SYSTEM_HANDOFF.md` |
| Crystal / fluid | `Crystal.md`, relevant ENGINE sections |
| Performance / streaming | `Performance.md`, `Chunking.md` |
| Architecture change | `ENGINEERING_AUDIT.md`, `DECISIONS.md`, `PROJECT_GRAPH.md` |
| Verification / regression | `AI_DEVELOPMENT.md`, `BACKLOG.md` |
| Content / assets | `CONTENT_DIRECTOR.md`, `WEEK_PLAN.md` (Agent 2 rules) |

## Rules for agents

- Prefer the short contract + handoff over long architecture docs.
- Never invent a parallel documentation system.
- After a change, update `SYSTEM_HANDOFF.md` (or `ASSET_HANDOFF.md`) only with the required fields.
- Do not edit `manual_verification.md` (human-only).
