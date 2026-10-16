# Honest bot crystal and boss

The honest bot finishes the run the way a person would: it walks to the single crystal, attacks it with the mapped attack action, and fights the origin warden when that boss appears. It never teleports, calls `damage_crystal_at`, or writes crystal health.

## Sub-features

- `honest-bot-crystal` — a simulated walk closes on the crystal, close range pulses attack, a boss-prefixed foe is fought first at the 25% line, and vanishing that foe then draining observed HP to zero prints `CRYSTAL DESTROYED`. A live boot of `main.tscn` walks toward the origin cell and prints `STOP live reach` with remaining columns if the corner crystal is not destroyed.

## How to get to it (user POV)

Start a world. Face the crystal (Q/E) and walk (W). When close, keep the sword selected and hold attack. When the warden appears near 25% crystal health, fight it, then finish the crystal.

## Driving it with cs-verify.sh

```bash
bash .cursor/skills/verify-crystal-storm/cs-verify.sh bot-crystal
```

Pass: the log contains `HONEST BOT CRYSTAL OK`, a line `CRYSTAL DESTROYED`, a line starting with `BOSS SPAWN`, a line starting with `BOSS KILL`, and no line starts with `FAIL`. The script must not hit a `SCRIPT ERROR`. Exit 137 or 134 after the marker is the abrupt probe quit.

## Gotchas

The live origin is near the player spawn on this seed (about 56 columns). The probe walks toward `get_origin_cell()`, then keeps attacking for 8s after it is inside 2.4 columns. If crystal HP stays full, `STOP live reach remaining ... hp 500/500` is the exact stop. Simulated HP drops only while the bot is striking and the probe observes a new swing; the bot does not call `damage_spawn`. Headless runs do not write a step png.
