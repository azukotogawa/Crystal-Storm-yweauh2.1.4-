# Play harness

The showcase bot is the player. A scenario is one feature, started from a fixed seed, driven only through `scripts/honest_bot/honest_input.gd`, then checked against what that player would see.

`bash .cursor/skills/verify-crystal-storm/cs-verify.sh scenario <name>` runs one scenario. Names that play the world today: `dig`, `build`, `crystals`, `corruption`, `combat`, `mite_fight`, `relic_esc`. `scenario break` does not boot the world. It forces the dig height assertion to fail and must print `FAIL harness assertion`, `STUCK REPORT`, and `STUCK SHOT`.

## Shared setup

| Piece | Value |
| --- | --- |
| Seed | `12349` (the new-world field in `ui/frontend_root.gd`) |
| Launch | `WorldManager.pending_launch` id `harness-<name>`, name `Harness`, `pending_resume` off. No catalog write and no save apply. |
| Scene | `scenes/main.tscn`, same boot wait as the showcase (`INITIAL_STREAM_READY`, then actions unblocked, `world_ready`). |
| Loadout | The live starting slots. Stone pick is hotbar 2. Stone is slot 4, count 16. Nothing is granted. |
| Input | `HonestBuild` calls `HonestInput` (`action_press`, `InputEventAction`, mouse aim, the craft click). No teleport, no direct dig, no direct damage, no XP grant. |
| Walker | `HonestPlayBot`. Scenarios do not steer with a second navigator. |
| Stuck and failed assertions | `HonestPlayBot.fail_closed`. That writes `stuck-*.txt` plus a screenshot (`STUCK REPORT`, `STUCK SHOT`) using `ProbeCapture.write_step`. A window grab is used when the display is not headless. Headless still saves a proof image, because a headless viewport has no texture. |
| Pass screenshot | `HonestPlayBot.save_view` writes `steps/<n>_<name>.png` and prints `HARNESS SHOT` and `PROBE CAPTURE`. |

The runner is `scripts/honest_bot/honest_scenario.gd`, launched by `scripts/verify_honest_bot_scenario.gd`. Timing stays in `config/default_game_feel.tres` via `honest_pace.gd`. Do not add a second input driver, stuck watch, or screenshot path.

## What every scenario asserts

After the feature finishes, the run prints one `HARNESS see` line and fails on the first miss.

- State: the feature's world change (a height drop, a placed wall).
- Banner: `ToastLabel` text sampled every frame from boot onward. The opening line `Watch the purple front — dig trenches & walls where it advances` must appear. Any other line has to be one this feature is allowed to show.
- HP: `player.health` is unchanged, `PlayerHealthBar` is visible, and its label matches `current / max`.
- Inventory: `inventory.count_item` for the material this feature takes or gives.
- Screenshot: a non-empty `HARNESS SHOT` path.

A miss prints `FAIL harness assertion ...` and then the stuck report. Death is still the only way to lose a real run. A failed scenario is a broken check, not a loss screen.

## dig

Plays `HonestBuild` mode `dig_tool` until it returns `pass` (select the stone pick, aim a dry column, hold attack through the multi-block wind-up in `default_game_feel.tres`).

| Check | Pass |
| --- | --- |
| Terrain | The aimed column's height delta falls (same read as `SHOWCASE dig column`). |
| Inventory | Stone count rises. |
| Banner | Opening line. A trench line is allowed if the dig is inside crystal. It is not required. |
| HP | Unchanged, label matches. |
| Shot | `steps/*_dig.png` |

## build

Plays `HonestBuild` mode `structure_place` until the first stone wall is down (`beat` reaches 10, the `SHOWCASE structure stone_wall placed` point). Ghosts and the crafted segment stay on the showcase route. They are not this scenario.

| Check | Pass |
| --- | --- |
| Terrain | At least one new build tile inside the place snap. |
| Inventory | Stone count falls (a stone wall spends one stone). |
| Banner | Opening line. `Wall raised — crystal slows here; it will find another way` is allowed when the wall is near crystal. Gate, bridge, trench, and `First steps` lines are allowed and not required. Any other toast fails. |
| HP | Unchanged, label matches. |
| Shot | `steps/*_build.png` |

## crystals

Walks to the released heart with `HonestPlayBot`, chips a film cell with the stone pick until `crystal_shard` increases, then swings the wooden sword at the heart column until crystal HP falls. The heart is observed. It is not written.

| Check | Pass |
| --- | --- |
| Find | The player is within 8 columns of the heart. |
| Collect | Crystal shard count rises. |
| Use | Crystal HP falls after the sword swings. |
| Banner | Opening line. First steps, trench, gate, bridge, wall, level-up, skill, enemy, boss, coverage, assault, and discovery lines are allowed. |
| HP | Unchanged, label matches. A guardian or mite bite fails this scenario. |
| Shot | `steps/*_crystals.png` |

## corruption

Watches the pool until a nearby cell becomes corrupt, breaks one filmed cell with the stone pick until a scar starts, then stands in crystal at least 0.25 deep. The burn warning has to be up before health falls. The player then walks out.

| Check | Pass |
| --- | --- |
| Spread | A cell near the heart gains `corrupt` that it did not have at boot. The rise is kept when it happens. A scar can heal before the burn, so the end count may fall. |
| Cleanse | `CrystalCorruption.scar_count` rises after the pick swings. The rise is kept when it happens. |
| Effect | `BurnWarn` is visible, then `player.health` drops. |
| Banner | Same allowed lines as crystals, plus the assault line. |
| HP | Lower than boot, label matches, and the bar stays visible. |
| Shot | `steps/*_corruption.png` |

## combat

Stands through a mite `StrikeTelegraph` until that bite lands at 1.45 columns or less, steps away from a boss `TelegraphRing`, chips film until a skill point exists, spends it on Dash through `HonestSkillCast`, and lands a sword hit that lowers a living foe's health. `HonestCombat` does the sword walk. No XP is granted.

| Check | Pass |
| --- | --- |
| Warning hit | A mite `StrikeTelegraph` is visible (`HARNESS attack warning`), then that mite lands `HARNESS mite hit` at 1.45 columns or less. A boss ring is stepped away from and does not count. |
| Melee | One foe's health is lower after sword swings. |
| Skill | Dash is bought and the cast slides (`OK dash slide` or `SKILL dash`). |
| Feedback | `HitMarkers` is live at least once (a sword connection or a crystal chip). |
| Banner | Same allowed lines as crystals, plus `Used herb` when the bot drinks one. |
| HP | Lower than boot, label matches. Death fails the scenario. |
| Shot | `steps/*_combat.png` |

## mite_fight

Boots a fresh world on each seed and walks to the Origin Heart. The burn pool, the crystal mites, and the heart-bound guardian are the ones that seed spawns. The Shard Tyrant stands on the edge of the crystal spawn ring, not on the heart column, and its slam stays on that station. No teleport, no granted XP, and no direct damage. `HonestFight` is already home, the bow chapter is finished, and the wooden sword is the weapon. Default seeds are 12349 through 12353. `CRYSTALSTORM_HARNESS_SEED` runs one seed. `CRYSTALSTORM_HARNESS_SEEDS` runs a comma list.

Each attempt lasts at most 150 seconds. Once the Shard Tyrant is within 28 columns, the bot walks to its station and stands inside the slam until `damage_taken` records source `spawn_elite`. That source stays separate from `boss` (the Origin Warden). The bot then kills at least one crystal mite from a clear cell and holds one second with no living mite inside 16 columns of the heart and with the player out of the burn. A sprint or dash whose path, landing, or current cell is burn fails that seed. A boss hit whose telemetry `heart_columns` is within 4 of the heart fails that seed. A `boss` damage source on this fight also fails it.

| Check | Pass |
| --- | --- |
| Survive | Health stays above zero and the label matches. |
| Kill | `KILL crystal_mite` at least once, then the heart neighborhood is clear for one second. |
| Off film | At least one `HARNESS mite off_film contact` or `HARNESS mite off_film kill` on a mite cell whose depth is under 0.12. The bot holds a clear cell and swings only after that mite steps off the film. |
| Burn sprint | Zero frames where sprint or dash is held into a burn tile. |
| Tyrant | `HARNESS mite spawn_elite` prints an amount above zero. The session JSON has `damage_taken` source `spawn_elite` and no `boss` source. |
| Boss | `damage_taken` source `boss` rows carry `heart_columns`. None are within 4 columns of the heart. Each seed prints `HARNESS mite boss_near 0`. |
| Banner | The opening dig line is up. |
| Shot | `steps/*_mite_fight.png` from the last clear moment. |
| Seeds | One `HARNESS mite seed` line per seed, including `off_film`, then `HARNESS mite N/N survive N/N kill` and `HARNESS mite boss_hits_near_heart 0`. |

## relic_esc

Boots a fresh world on each seed. Default seeds are 12349 through 12353. `CRYSTALSTORM_HARNESS_SEED` runs one seed. `CRYSTALSTORM_HARNESS_SEEDS` runs a comma list. After the start region is ready, `RelicChoice.present` opens the offer the game uses when a spawn is destroyed. The bot then sends Escape, holds move, and pulses attack and hotbar through `HonestInput`. No teleport, no granted XP, and no direct damage.

| Check | Pass |
| --- | --- |
| Pause | The pause menu stays hidden, the tree stays unpaused, and `pause_open` stays false. |
| Panel | The same offer is still open after Escape. |
| Play | The player does not walk, the hotbar slot does not change, and the weapon cooldown does not start. |
| Pick | A click on an offer closes the panel, leaves a relic equipped, and clears the modal. |
| Seeds | One `HARNESS relic seed` line per seed, then `HARNESS relic N/N pause_closed N/N panel_held`. |
| Shot | `steps/*_relic_esc.png` |

## Not scripted yet

One scenario each, same seed and the same input layer, when that feature is next: movement, treasure, landmark, boss, win. The showcase route still plays those. This harness does not replace it.
