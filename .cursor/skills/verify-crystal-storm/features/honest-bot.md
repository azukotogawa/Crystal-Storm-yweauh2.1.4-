# Honest bot navigation

The honest bot walks the player toward a column the way a person would: it holds the mapped move and rotate actions. It never teleports the body, grants XP, damages the crystal, or writes terrain. If the body stops making progress it sidesteps, taps jump, and prints a stuck line.

## Sub-features

- `honest-bot-nav` — planner matches player heading, a simulated walk arrives, a frozen body reports stuck, and a live boot of `main.tscn` closes at least 3 columns on one bearing.

## How to get to it (user POV)

Start a world. Hold Q or E until the view faces the place you want, then hold W. If you stop against a rise, hold A or D and tap Space.

## Driving it with cs-verify.sh

```bash
bash .cursor/skills/verify-crystal-storm/cs-verify.sh bot
```

Pass: the log contains `HONEST BOT NAV OK`, no line starts with `FAIL`, and the script did not hit a `SCRIPT ERROR`. Exit 137 or 134 after the marker is the abrupt probe quit.

## Gotchas

The live walk tries +X, -X, +Z, then -Z and stops at the first bearing that gains 2.5 columns. Headless runs do not write a step png. Parts after navigation (dig, fight, skills, save) are not in this command.
