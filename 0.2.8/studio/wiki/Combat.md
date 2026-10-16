# Combat

## Current loop

Combat is centered on the player using hotbar-selected weapons through `WeaponController`. Dig tools still edit terrain. Combat weapons never dig or remove terrain.

1. Player selects a weapon, armor, or the crystal bomb.
2. `ActionTargeting` resolves the forward column (8-voxel interaction range for tools).
3. Melee uses `CombatHitResolver` arcs. The spear uses a thrust line. The bow, sling, and bomb spawn a pooled `Projectile`.
4. Hits land on the first `world_entity`, `crystal_enemy`, crystal cell, or terrain the shot reaches. Shots can miss.
5. `CrystalManager.damage_crystal_at` breaks crystal mass. Spawn hearts take damage only when `SpawnPointController` allows it.
6. Breaking a crystal cell drops crystal shards. Arrows and bombs never change terrain height.
7. Killing the Origin Warden wins immediately. Destroying every spawn heart still wins. Loss conditions are unchanged.

There is no crafting bench. The start kit and kill drops are the acquire path.

## Weapons

Ranges are in columns (1 column = 1 voxel). Cooldowns are seconds. Knockback is in voxels, then multiplied by `voxel_scale` when the body is shoved.

| Id | Role | Entity | Crystal | Range | Cooldown | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| `wooden_sword` | Fast arc | 12 | 0.35 | 2.8 | 0.45 | Knockback 1.0. Start hotbar. |
| `spear` | Long thrust | 15 | 0.5 | 3.0 | 0.78 | Pierces the first 2 bodies on the line. Knockback 1.6. Side targets miss. |
| `crystal_hammer` | Crystal breaker | 7 | 4.8 | 2.2 | 1.1 | Chebyshev splash 1 (3×3 cells) via `damage_crystal_at`. One enemy shove, knockback 3.2. Never digs. |
| `shortbow` | Arrow | 10 | 0.55 | 14 | 0.8 | Speed 32, gravity 12. Flies from camera-forward. No ammo. Sticks in terrain, then fades. |
| `sling` | Cheap arc | 8 | 0.45 | 11 | 0.5 | Speed 18, gravity 34, spends 1 `stone`. Extra upward speed `0.55 * speed`. |
| `crystal_bomb` | Throwable clear | 22 | 3.2 | arc | 0.9 | Consumable, stack 8. Fuse/flight 1.35s or terrain impact. Blast radius 2.5 columns. Knockback 2.0. |
| `stone_pick` | Dig tool | 5 | 2.4 | 3.0 | 0.1 | Not a combat weapon. This is what removes terrain. |

Icons reuse an existing `visual_id`: spear → sword, hammer → pick, sling → bow, bomb and crystal weave → crystal shard, leather → herb, stone plate → stone.

Start kit: hotbar is sword, pick, bow, wood, stone ×16, herb. The bag holds spear, crystal hammer, sling, crystal bomb ×3, and stone plate. Leather is already worn.

## Armor

One slot, `Inventory.armor_id`, saved inside the inventory dict (`armor` key). A missing key keeps whatever is already worn, so older saves keep the leather from the start kit.

| Id | Damage taken | Move speed | Where it comes from |
| --- | --- | --- | --- |
| `leather_armor` | ×0.88 | ×1.00 | Worn at start |
| `stone_plate` | ×0.72 | ×0.86 | Start kit bag |
| `crystal_weave` | ×0.80 | ×1.08 | Origin Warden drop |

Click an armor stack in the inventory panel to wear it. Click the worn slot to return it to the bag. LMB on a hotbar armor stack also equips it. Reduction happens in `Player.take_damage` before defense.

## Knockback and i-frames

`EntityNavigation.knockback_step` moves the body along the flat shove. If the landing ground is more than one walkable step above or below the current feet, the body stays put. That blocks tunnelling into walls.

The player gets `0.6s` of i-frames after a burst hit (`HIT_IFRAMES`, inside 0.5–0.7) and the body mesh blinks. The crystal-field burn is not a hit: it does not start i-frames and is not blocked by them.

Each enemy keeps one `0.22s` hurt lock after a player hit. A second hit from the same swing does not stack. The spear's pierce cap is two different bodies, not two hits on one body.

## Projectiles

`weapons/projectile.gd` pools up to 32 arrows, stones, and bombs. They share one box mesh and two sphere meshes, unshaded, shadow casting off. No physics body per shot. Each node owns one fade material, created with the node and reused on every impact. Taking from the pool skips freed instances, and the live count is recomputed when a shot leaves the tree with its scene. Each step is semi-implicit gravity plus a segment test against cached combat nodes, then terrain, then a crystal cell. The node cache is reused for shots that stay near each other in the same frame.

## Boss and minibosses

`entities/boss_brain.gd` drives the telegraphs. `CrystalEnemy` applies damage only when a tick reports `impact`. A cylinder ring marks the aim point. It stays hidden until the windup.

**Origin Warden** (`origin_warden`) stands on the origin heart. 240 HP, speed 6.5, contact 18, defense 0.08, lifetime 0, visual `crystal_mite` scaled 1.65 and tinted crimson.

- Phase 1 (above 50% HP): slam if the player is within 4 voxels, otherwise a charge. Both wait for the boss row in `config/default_game_feel.tres` (0.85 s) before damage. Cooldown 0.85 s.
- Phase 2 (at or under 50%): the next tick opens a shard burst and summons 3 crystal mites. After that it alternates bursts with a slam or a charge. Every attack uses that same boss telegraph. Cooldown 0.32 s. The player can move during the wind-up.

The HUD boss bar is hidden until the player is within 22 columns or the warden has taken damage.

**Shard Tyrant** (`spawn_elite`) is one elite on each other active heart. 96 HP, speed 7.5, contact 16, visual `shard_guard` scaled 1.35. It only slams, using the same boss telegraph. No second phase and no summons.

A crystal mite bite and the warden's bite use their own rows (`mite` 0.45 s, `boss` 0.85 s). The marker is a ground disc, the body holds the attack pose, and the mesh flashes. Damage waits until that time is up, and only if the player is still in reach. Standing in a crystal pool of depth 0.25 or more shows `BurnWarn` for the `burn_pool` row (0.60 s) before the same burn rate starts. Leaving the pool cancels it. None of these pause the tree.

Guardians are not placed during the mite grace (`spawn_grace_sec`). After that, the spawner retries about once a second and will not place a second copy of a heart that already has a living guardian. A guardian only aggros when the player is within 14 columns of its heart. It walks back when the player is past 22 columns, or when the guardian itself is dragged past 22. It does not roam the map, and it does not charge or slam while leashed home. Saves store `guard_spawn_id` so a resume does not double them and the body is leashed to that heart again. A save that predates guardians grows them on load, after grace. The warden flag is not cleared from `_exit_tree` (save import frees the old body before the new one is ready).

## Rewards and how a run ends

`CombatRewards.grant_player_kill` adds the drop to the inventory and toasts it.

- Crystal hostiles (mite, thornling, shard guard, stag, beast, bomber): 1 stone.
- Rabbit, deer, bird: 1 herb. Boar: 1 wood.
- Shard Tyrant: 1 crystal bomb. Origin Warden: 1 crystal weave.
- Town militia and villagers: no items. The toast still says they went down.

Destroying a spawn heart, killing a tyrant, or killing the warden offers 3 distinct relics from `RelicChoice` (`mason_glove`, `flow_anchor`, `crystal_ward`, `pathfinder_charm`, `ruin_seal`, rotated by a seed). With a `game_overlay` in the tree, `RelicChoicePanel` opens, sets `pause_open`, and slows time to 0.05. The pre-modal `Engine.time_scale` is saved once, while no panel is open, and restored after the last queued panel closes. A second offer (a heart and the warden dying together) does not save 0.05 and restore 0.05. If every relic slot is full, the panel stays open and the player picks one equipped relic to replace. Without that overlay (headless probes), the first rolled relic is equipped. An absorption milestone that unlocks a new enemy (`CrystalEvolution.enemy_unlocked`, not every absorbed cell) grants that enemy's mapped relic once per run: thornling → `flow_anchor`, farm bomber → `crystal_ward`, crystal mite → `mason_glove`. Crystal mite is unlocked at run start and the signal handler skips it, so absorbing grass does not equip a relic. A direct grant of that mapping still equips. If relic slots are full and `game_overlay` is present, `RelicChoicePanel.open_replace` offers that one relic as a replacement. Headless full slots do not force-unequip. Spawn destruction still offers the three-relic choice.

Win:

- Warden death calls `GameManager.notify_boss_defeated`. `victory_reason` is `boss`. The overlay reads "Origin Warden fell".
- Every heart destroyed still wins. `victory_reason` is `spawns`. The overlay keeps the "all spawns destroyed" line.
- The origin heart cannot be damaged while any minor heart is active. It also cannot be damaged while `origin_warden_alive` is true. That flag stays false until a warden actually exists, so suites that never spawn the boss can still destroy the heart.
- If the warden dies while minor hearts remain, the run still ends in victory. The heart seal and the win are separate.
- Loss is unchanged: player death, crystal coverage, and the crystal touching the player.

## Feedback

Hits, swings, and breaks go through `CombatVisualFeedback` and `VfxPool`. The pool reuses a small set of `CPUParticles3D` one-shots (crystal shatter, dig dust, water splash, spawn-heart burst, rate-limited corruption, impact chips) and a few swing meshes. Sword and pick draw a short arc, the spear a thrust line, the hammer an overhead ring. The held item plays the same timing as a procedural pose: the strike lands on the impact sample of that pose. A miss and a blocked hit use a different marker from a landed hit. Materials are unshaded and shadow casting is off. Counts follow the performance preset. LOW is the smallest. SAFE is smaller still. See `studio/wiki/Effects.md`.

A hit also asks `Juice` for a 40–80 ms hit-stop and a camera shake. Light hits sit near 40 ms. Hammer, bomb, and boss slams sit near 80 ms and shake harder. Both are off in headless probes unless a test forces the dip. The pause menu and the frontend settings screen can turn shake, hit-stop, and the white hit flash off. Those flags persist in `player_settings.json`.

Enemy and creature hits flash through one shared overlay shader (`shaders/entity_hit_flash.gdshader`). Death detaches the visual, shrinks and fades it for about 0.4 s, and frees the body immediately. Walking bobs the visual node only, and only while the creature is near the camera. LOW shortens that distance. SAFE skips creature bob.

`AudioManager` is the sound hook. It plays nothing until files exist for the ids in `config/audio_manifest.gd`. The list of files to record is `assets/audio/SOUNDS_NEEDED.md`.

## Connected systems

- `Player` owns `WeaponController`, armor multipliers, and hit i-frames.
- `Inventory` supplies the hotbar item and the worn armor id.
- `ItemTypes` / `ItemDef` hold damage, range, cooldown, pierce, splash, projectile, and armor fields.
- `CombatHitResolver` finds bodies. `WeaponStrike` is the thrust, splash, and blast shape. It only calls `damage_crystal_at`.
- `CrystalManager` routes heart damage and presents the relic choice when a heart dies.
- `GameManager` ends the run. Boss victory and spawn victory share `_set_won` and do not override a loss.

## Still open

- No weapon upgrade crafting and no ammo type besides stone for the sling.
- No second water mesh, no shadow-casting combat lights, and no ramp changes. Terrain shaders stay unshaded.
