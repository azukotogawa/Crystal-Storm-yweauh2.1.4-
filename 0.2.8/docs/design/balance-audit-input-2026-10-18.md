# Balance audit input — 2026-10-18

Notes for cs-balance-audit-01. No tuning values were changed.

- Crystal burn still starts at depth 0.25 and deals the existing per-second damage. A player who stands in that pool, or sprints across it, dies before a crystal mite on the same tiles can be killed. Attempt 5 (`20261018-cs-bot-win-run-05`, `DEATH hp 0.0` at dist 4.0) is the evidence. The bot was the change: it now fights that mite from a clear cell and will not sprint through burn tiles while its health is low.
- Sword reach is still the existing hit ring (about 1.65 columns). If the mite stays deeper in the pool than that ring, a player on the clear rim cannot hit it until the mite walks out. That wait is a bot limit, not a mite or burn nerf.
- A guardian leash is still 22 columns. On attempt 6 the treasure stand the bot had reached sat inside that leash, so stepping off the leash also left the 10-column ruin discover radius. The bot now stays for the discovery. The leash radius was not changed.
- Attempt 7 (`20261018-cs-bot-win-run-07`) stood on that same ruin (`94.8,-247.2`) after the level-up from discovery. A guardian dodge one column away (`93.8,-246.5`) counted as arrived, so the bot held no keys for the 150s phase wall and never played the treasure face. Aggro, leash, discover radius, and the 1.25-column arrive distance were not changed.
- The rerun (`20261018-cs-bot-win-run-07b`) passed the treasure and still died on the heart (`DEATH hp 0.0` at dist 3.5) after two sprints out past 1000 and 690 columns. Burn depth and mite damage were not changed. The bot still leaves the clear rim.
