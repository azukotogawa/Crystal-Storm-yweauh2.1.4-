# Crystal Storm — Agent Loop

## Default instruction
Before every task:

> Read /studio and the repository's current instructions/status. Continue the highest-priority unfinished work. Do not repeat the game brief unless a rule has changed.

## Agent 1
Use short cycles:
inspect → one bounded change → focused verify → live verify when visual → update status → report.

Do not create a new system to compensate for a broken existing system.

## Agent 2
Use short asset batches:
inspect current atlas/content contract → create a coherent small batch → prove IDs in the live game → capture representative screenshots → report.

Do not change gameplay mappings merely to make an asset fit.

## Cross-agent handoff
Use files rather than long prompts.

Agent 2 writes:
`/studio/ASSET_HANDOFF.md`

Agent 1 writes:
`/studio/SYSTEM_HANDOFF.md`

Each contains only:
- current task
- changed IDs/files
- assumptions
- screenshots/locations
- known problems
- next action

## Human playtest loop
The human provides:
- screenshot
- cell/world coordinates when known
- expected result
- observed result

Agents turn recurring visual failures into explicit contracts/tests.

## Token rule
Prefer:

"Read /studio. Continue the current milestone. Verify the last result and fix the highest-priority remaining issue."

over repeating a multi-page prompt.

Restate instructions only when design direction, rules, priorities, or repository documentation intentionally changes.
