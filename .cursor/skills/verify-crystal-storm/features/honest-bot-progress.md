# Honest bot progression

The honest bot levels the way a person would: only kills grant XP, and a new skill point is spent by opening the skill tree and accepting a highlighted skill. It never calls the progression or skill services. The XP-per-minute line is the telemetry autoload's snapshot.

## Sub-features

- `honest-bot-progress` — non-kill sources stay at level 1, kill tiers reach level 2 and choose dash, and that choice unlocks dash on the real skill-tree panel. The printed rate matches `DifficultyTelemetry.xp_snapshot()`.

## How to get to it (user POV)

Kill hostile creatures until you level. Press K. Move the highlight with the arrow keys and press Enter on the skill you want. Mining, placing, ruins, and the crystal do not level this bot.

## Driving it with cs-verify.sh

```bash
bash .cursor/skills/verify-crystal-storm/cs-verify.sh bot-progress
```

Pass: the log contains `HONEST BOT PROGRESS OK`, a line starting with `LEVEL`, a line starting with `SKILL`, a line starting with `XP_RATE`, and no line starts with `FAIL`. The script must not hit a `SCRIPT ERROR`.

## Gotchas

This part does not boot `main.tscn`. The skill press is delivered as `skill_tree`, `ui_down` or `ui_right`, and `ui_accept` into the real panel. Headless runs do not write a step png. Dash is the first choice; it sits one row under Crystal Pulse, so a missed `ui_down` unlocks the wrong skill and fails the check.
