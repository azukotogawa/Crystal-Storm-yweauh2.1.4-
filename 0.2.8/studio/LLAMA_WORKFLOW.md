# Llama Workflow (local 3B)

Rules for a small local model working on Crystalstorm. Keep every cycle tiny.

## Default instruction (before every task)

Read `/studio` status files first. Continue the highest-priority unfinished work. Do not restate the game brief.

Minimum reads:
1. `NOW.md`
2. `SYSTEM_HANDOFF.md` (or `ASSET_HANDOFF.md` for art)
3. The relevant contract (`INPUT_CONTRACT`, `PLAYTEST_VISUAL_CONTRACT`, etc.)

Then stop reading and act.

## Cycle (mandatory)

```
inspect → one bounded change → focused verification → stop
```

- **Inspect**: look at the exact files and current handoff. Do not invent missing systems.
- **One bounded change**: smallest coherent fix that addresses the current priority. No drive-by refactors.
- **Focused verification**: run the narrowest relevant `verify_*.gd` or live camera check. Do not claim full suite unless you ran it.
- **Stop**: update handoff if needed, then report in the required format.

Never broaden scope. Never start the next feature because polish is missing.

## Response format (always)

```
Changed:
- …

Live / focused verified:
- …

Remains:
- …

Next single step:
- …
```

No multi-page summaries. No restated design pillars.

## Screenshots

When the human provides a screenshot:

1. Note cell `(x,z)`, heights of landing/approach if given, and expected vs observed.
2. Map the failure to an existing contract (ramp geometry, edit halo, input binding, scale).
3. Fix the root cause in the existing system if possible.
4. Turn recurring failures into an explicit contract or focused probe — do not paper over with a new system.

Coordinate language (required for terrain talk):
- world cell `(x,z)`
- east `+X`, west `−X`, south `+Z`, north `−Z`
- landing = higher cell; approach = lower neighbor toward step-down

Never use only “top/bottom/left/right” for world geometry.

## When to read which files

| Situation | Read |
|-----------|------|
| Starting any work | `NOW.md`, `SYSTEM_HANDOFF.md` |
| Ramp / dig / build visual | `PLAYTEST_VISUAL_CONTRACT.md`, `ALPHA_VISUAL_CONTRACT.md` |
| Input or targeting | `INPUT_CONTRACT.md` |
| Crystal behavior | `Crystal.md` |
| Architecture or large change | Ask human first; then `ENGINEERING_AUDIT.md` / `DECISIONS.md` |
| Content / assets | `CONTENT_DIRECTOR.md` + Agent 2 rules in `WEEK_PLAN.md` |

Do not load the entire studio into context. Prefer the short contracts.

## Hard prohibitions

- Do not create a new system to fix a broken existing one.
- Do not change input bindings silently.
- Do not auto-edit `manual_verification.md`.
- Do not start persistence, terrain art, or content architecture while the live slice is still being verified.
- Do not claim human visual/feel sign-off.
- Do not expand beyond the current `NOW.md` objective.

## Content rule (from CONTENT_DIRECTOR)

Expand existing mechanics first. Every new piece must connect to ≥3 existing systems, create player decisions, stay playable, and prefer depth over breadth. Placeholder art is fine.

## Handoff update (when you change code)

Write only these fields into `SYSTEM_HANDOFF.md`:

- current task
- changed IDs/files
- assumptions
- screenshots/locations
- known problems
- next action
