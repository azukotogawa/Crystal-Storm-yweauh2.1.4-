# Honest bot recorded run

One live session drives the honest bot through boot, navigation, combat, progression, and the crystal. It only presses mapped actions. The run writes `bot-report.md` with each phase and the first phase that did not reach, plus a DifficultyTelemetry JSON. A phase that fails stays in the report and still lets the harness finish so `record` can write the movie and contact sheet.

## Sub-features

- `honest-bot-boot` — `main.tscn` reaches the start stream and the player can act.
- `honest-bot-nav` — the bot walks toward the crystal origin until it gains a column or five seconds pass.
- `honest-bot-combat` — if a crystal enemy is within 32 columns it is fought with the sword and skills; otherwise the phase fails closed.
- `honest-bot-progress` — a spare skill point is spent through the skill tree; zero points fails the phase.
- `honest-bot-crystal-run` — the bot walks to the origin and attacks. Unchanged crystal HP is a failed phase, not a harness failure.

## How to get to it (user POV)

Start a world. Walk toward the crystal (Q/E, W). Fight a crystal enemy if one is close (sword on 1, attack, skills). If a skill point is available, open the tree (K) and spend it. Then keep walking to the crystal and attack it.

## Driving it with cs-verify.sh

```bash
bash .cursor/skills/verify-crystal-storm/cs-verify.sh bot-run
bash .cursor/skills/verify-crystal-storm/cs-verify.sh record bot-run
```

Pass: the log contains `HONEST BOT RUN DONE` and `BOT RUN OK`, `bot-report.md` is non-empty, `<run>/telemetry/` has a session JSON, and no line starts with `FAIL`. `record bot-run` also prints `RECORD OK` and writes `contact-sheet.png` next to the mp4. The script must not hit a `SCRIPT ERROR`.

## Gotchas

The harness exits 0 when the report and telemetry exist, even if a phase failed. Read `Result:` in `bot-report.md` for the first failed phase. Combat does not invent a target. Progress does not grant XP. Crystal HP is only observed. Headless `bot-run` still writes the report and JSON; the contact sheet exists only under `record`.
