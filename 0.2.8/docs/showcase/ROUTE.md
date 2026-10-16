# Showcase speedrun route

Input-only route for one fresh world on `res://scenes/main.tscn`. The bot sends input events and reads what the game already shows. It does not teleport, grant XP or items, write health, or change balance.

Record later with `bash .cursor/skills/verify-crystal-storm/cs-verify.sh record` once a driver can play this route. Movies go to `D:\ARCHIVE\CrystalStorm\verify-evidence\showcase\`. Copy the mp4 to `D:\LATEST\CrystalStorm\showcase-speedrun.mp4`. This document does not run that recording.

## What the last honest runs already proved

`0.2.8/scripts/honest_bot/` only presses and releases input actions (`Input.action_press`, `Input.action_release`, `InputEventAction`).

| Run | What happened |
| --- | --- |
| verify-13 `bot-crystal` | Sim destroy and boss fight passed. Live walk from about `1008.50,-951.50` to `953.92,-952.56` (origin `952,-952`). 20 swings, heart stayed `500/500`, boss never spawned. |
| verify-14 `20261016-004519-bot-run` | Boot and a 1.44-column nav. Combat not reached (no foe within 32 of spawn). Crystal failed (11 swings, remaining 1.97, heart `500/500`). 70 XP from mass cells did open the tree (`SKILL dash`). |
| verify-15 `20261016-005507-bot-run` | How to play was closed with two `pause` taps. Crystal still failed (12 swings, remaining 1.53, heart `500/500`, 0 XP). Combat and the skill tree were not reached. Report: `0.2.8/docs/VERIFY-15-honest-bot.md`. |

The sword hits `ActionTargeting`’s mouse cell. `damage_spawn_at_world` only hurts the heart when that cell is within the swing’s radius of the origin (sword radius 2.8, hammer radius 1.6). Facing the pool is not enough. Verify-14’s 14 XP events were mass chips (`XP_CRYSTAL_HIT` 4 plus `XP_CRYSTAL_CELL` 10), not heart damage.

A showcase driver has to aim the mouse. That is still a player input. It is not a stat write. The current action-only driver cannot finish the heart, the craft buttons, or Z / X.

## Rules the driver keeps

- Fresh world. No seed shopping. Spawn and the origin come from the live game (`get_origin_cell` on the last run was `952,-952`).
- Navigation is the existing one: hold `rotate_left` or `rotate_right` until the camera faces the column, then hold `move_forward`. Strafe when progress stalls. After 1.25 s and under 0.35 columns, print `STUCK nav`, sidestep, and tap `jump`. Three stuck lines and that target is abandoned (`unstuck` once, then skip).
- Do not path the whole continent. Density legs are capped at 1500 columns, which reaches the near ring and skips the far side.
- Fight retreat stays the combat bot’s rule: at or under 30% health, walk away and stop attacking. `hotbar_6` then `build_place` uses the herb (right-click use). One death fails the run.
- Tick the JSON checklist at the bottom as each segment ends. Print `SHOWCASE <id> <status>` with `status` one of `pass`, `fail`, `absent`, `too-far`, `skipped-no-point`.

## Loadout the route is allowed to touch

Hotbar slots 0–7 are keys `hotbar_1` … `hotbar_8`.

| Slot | Key | Item |
| --- | --- | --- |
| 0 | `hotbar_1` | wooden sword (heart damage 12, cooldown 0.45 s, heart radius 2.8) |
| 1 | `hotbar_2` | stone pick (tier 0, break shape `single`, digs one cell) |
| 2 | `hotbar_3` | shortbow |
| 3 | `hotbar_4` | wood ×16 |
| 4 | `hotbar_5` | stone ×16 |
| 5 | `hotbar_6` | herb ×4 |
| 6 | `hotbar_7` | empty until a craft lands here |
| 7 | `hotbar_8` | empty |

Bag, not hotbar: spear (slot 8), crystal hammer (slot 9, heart damage 8, radius 1.6, cooldown 1.1 s), sling, bombs, stone plate. The hammer is slower and has to stand closer. The speedrun uses the sword on the heart. There is no higher-tier pick, so the pick never digs a 1×2, a line of 3, or a 3×3. The 3×3 the player can actually perform is Ground Slam.

## Skill tree (focus resets to fighter / top every open)

Columns are fighter, miner, builder. Rows are the catalog ids sorted.

| Column | Row 0 | Row 1 | Row 2 |
| --- | --- | --- | --- |
| 0 fighter | crystal_pulse | dash | fighter_passive |
| 1 miner | ground_slam | miner_passive | |
| 2 builder | builder_passive | quick_wall | |

`open()` starts at column 0, row 0. Unlocking an active equips it into the first empty slot. Slot 0 is `skill_1` (C), slot 1 is `skill_2` (H), slot 2 is `skill_3` (J). Only three actives fit.

XP to the next level is `round(50 * level^1.5)`: 50, then 141, then 260. Level 2 is 50 XP. Level 3 is 191 XP total. Heart hits pay 4 XP each and do not pay the broken-cell bonus. The heart has 500 HP, so a clean sword kill is about 42 hits and about 168 XP. That is level 2 with room to spare, and short of level 3. The boss line is 25% (`BossBrain.BOSS_SPAWN_HEALTH_RATIO`), 125 HP, around sword hit 32 (about 116 HP). Spend dash as soon as the first point exists. If the heart reaches 125 HP before the second point exists, stop hitting the heart. Earn the rest from mass cells, mites, and a few extra digs beside the pool, then slam, then resume. Do not grind a second biome.

Kill XP, if a kill actually happens: mite / thornling 8, stag / beast / bomber / wisp 14, shard guard 20, warden 32. Militia and villagers pay nothing. Do not hunt them.

## Ordered segments

Each segment is one feature. Do them in this order. Skip a capped detour instead of adding a new trip.

### 1. `boot_tutorial`

Wait until the player is in the world and the stream is ready. If the How to play panel is visible, pulse `pause`, release it, pulse `pause` again, release it. The panel closes on that pair. Confirm the panel is gone before moving.

Pass: panel hidden, player can move.

### 2. `movement`

Face the live origin. Hold `sprint` and `move_forward` for at least 8 columns. Tap `jump` once on flat ground. One `rotate_left` or `rotate_right` correction is enough; do not orbit. If a deep channel is already underfoot, hold `jump` to rise to the waterline, then walk out. Do not dig a pool to demonstrate swimming.

Pass: the body moved at least 8 columns, a jump left the ground, sprint was held.

### 3. `lighting`

During segment 2, the medium preset is already on: directional sun, shadow map, SSAO, exponential fog, terrain corner AO. Keep the player in frame long enough that the body casts a shadow on the ground. Do not change quality and do not rotate the sun. `SceneLighting` treats a moved sun as an error. The sun vector stays `(0.55, 0.82, 0.38)`.

Pass: player shadow is on screen under that sun. No extra travel.

### 4. `day_night`

There is no day clock, dusk, night, or torch (`OmniLight3D` / `SpotLight3D`). Do not wait, and do not spin the light or drop its energy to fake one. Print `SHOWCASE night absent` and `SHOWCASE torch absent` (or `pass` if a later build actually has them). A crystal-glow landmark is emission on the mesh, logged later as `SHOWCASE glow`, not a torch.

Pass status: `absent`.

### 5. `dig_tool`

`hotbar_2`, aim the mouse at a diggable surface cell beside the route, pulse `attack` eleven times on open ground. The highlight is one cell. That is the whole multi-block tool table at tier 0. Eleven blocks are 11 XP. Stop early if a column refuses (border, town, water, dig floor) and make the count up on the next open cell. Do not hold `[` or `]` and do not cut a tunnel.

Pass: at least one column height dropped. Count the blocks; the crystal segment needs the number.

### 6. `structure_place`

`inventory_toggle` (I). Click the button named `Craft_wall_segment` (6 stone). Close the bag with `inventory_toggle`. The piece lands in the first empty slot, which is slot 6 (`hotbar_7`) when slots 6 and 7 were empty. Select that slot. Aim the mouse at an open cell in reach. Pulse `build_place` (right mouse). The ghost is green on open supported ground and red when blocked. Default blueprint is `wall_segment` (3 wide, 2 high, 1 deep). Do not press Z or X unless the ghost is red; Z turns it, X cycles `wall_corner`, `gate`, `stairs`, `small_tower`. Place only the segment. The other four are the same click with a different piece, and the starter 16 stone cannot also pay the 12-stone tower after this craft.

Pass: a wall segment exists, and the place granted structure XP (12).

### 7. `density_poi`

Read placed POIs (`poi_kind` of `camp`, `abandoned_dig`, `crystal_grove`, `shrine`). Together with segments 8 and 9, pick one of each kind on the shortest walk that still does poi, then treasure, then landmark. Consider only the 8 nearest of each kind. A leg longer than 1500 columns is `too-far` and is not walked (that is the far side of the map, not the ring near the origin). Sprint. Hold `jump` only while a deep channel is underfoot. Stand on the POI so the props are in frame. There is no `poi_discovered` emit in the live director, so do not expect the 20 XP.

### 8. `density_treasure`

The treasure stop chosen with segment 7. Walk inside `ruin_discover_radius` (10) and wait for the director's own scan. Discovery pays 25 XP. Do not call `discover_ruin_at` and do not write the chest into inventory. Status `too-far` when that leg was over 1500.

### 9. `density_landmark`

The landmark stop chosen with segment 7 (`rock_spire`, `ruined_tower`, or `crystal_glow`). Stop about 12 columns out so the mesh clears half of ortho size 16. Yaw until it is in frame. If it is a crystal glow and the mesh emission is in range, print `SHOWCASE glow pass`; otherwise `SHOWCASE glow absent`. Status `too-far` when that leg was over 1500.

### 10. `combat`

Do not walk onto the heart yet. Farm until level 3 (191 XP earned) before any heart swing. After that mite, the bow shot, and level 3, keep going until level 6 (five skill points) by breaking crystal mass with the stone pick. Aim only at cells at least 3.6 columns from the origin, and stand off the burn. That chips the film for XP and does not count as a heart swing. The already opened chain treasure is not opened again.

Seek a living non-mite crystal enemy inside 220 columns before another mite. Also fight rabbits, deer, boar, and birds that are already in range. Town militia and villagers are not targets. If nothing fresh is close, open up to four more treasure sites inside 1500 columns: stand inside the ruin radius, wait for the director to discover the chest, then fight the guardians. After those sites, or once level 3 is in hand and one mite is dead, hold the safe ring outside the burn for a short look at whatever the pool has spawned. The first mite still takes one bow shot after the mite chapter has been up for 4 seconds.

On the first living `crystal_mite`: `hotbar_1`, mouse on the mite, pulse `attack` until `KILL`. Also pulse `hotbar_3` and one `attack` so the bow fires once. Kinds that never show up stay `absent`. Do not write an unlock. `origin_warden` is segment 15, not this scan.

Pass: mite `pass` after a real kill, and earned XP at level 3 before segment 15. Each other id is `pass` or `absent`.

### 11. `xp_level`

Watched on the HUD while digging, placing, opening treasure, and killing. Level 3 must already be true before the crystal segment starts. Print `LEVEL` when the bar flips and `SHOWCASE xp ready` with the earned total.

Pass: level at least 3, earned at least 191, from kills, digs, the placed structure, or ruin discovery only. Heart hits do not count toward this gate.

### 12. `skill_dash`

The moment `skill_points >= 1`: `skill_tree`, `ui_down`, `ui_accept`, `skill_tree`. That is dash, and it equips to `skill_1`. Hold `move_forward` and pulse `skill_1`. Dash slides 4 columns.

Pass: log `SKILL dash`, and the body moved on that press.

### 13. `skill_ground_slam`

This is also the multi-block break. Second point (191 XP total): if the heart is still above 125 HP, keep swinging until the point exists. If the heart has reached 125 HP, stop heart swings. Break mass cells under the mouse and kill mites already on the pool, and dig a few more open cells if that is still short. Then `skill_tree`, `ui_right`, `ui_accept`, `skill_tree`. Ground slam equips to `skill_2`. Stand on open ground, not inside a town, and pulse `skill_2`. It digs the 3×3 under the player and hits enemies standing on that patch for 18.

Pass: log `SKILL ground_slam`, and more than one cell in that 3×3 lost height.

### 14. `skill_rest`

Level 6 has the points. Crystal pulse walks to a dry ring about 8 columns off the heart, pauses, and casts so the pool stays in frame. Quick wall casts on that same ground. If the three slots are full, the tree unequips dash first, then unlocks quick wall into the free slot. The wall has to appear. One turn and a retry if the first facing is blocked. Passives open the miner node, spend the last point, and hold the tree on Quick Mine until the caption shows it is on. Each of those beats logs `SHOWCASE STAMP` with the on-screen clock.

Pass: `crystal_pulse`, `quick_wall`, and `miner_passive` are `pass`, not skipped.

### 15. `crystal`

`hotbar_1`. Put the mouse on the origin column itself, not merely a purple neighbor. Hold range so that cell stays inside 2.8 columns (stand nearer than the verify-15 stop at remaining 1.5). Pulse `attack` on cooldown. Watch Crystal HP on the HUD. Stop at or under 125 HP if segment 13 is not done yet; resume only after the slam. Mass under the cursor may chip for 14 XP and still leave the heart at 500. That does not count as this segment.

Pass: heart HP has been at or under 125, and it dropped because of swings, not a write.

### 16. `boss`

The first time the heart is at or under 25%, one `origin_warden` spawns two columns off the heart (try +X, −X, +Z, −Z). HUD warning and a toast. Fight that id before any further heart damage that could empty the bar. Mouse on the warden, sword, `skill_1` to leave a slam telegraph, `skill_2` if the 3×3 will catch it. Phase 2 starts at half the warden’s 240 HP (burst, then slam or charge). Kill it (`BOSS KILL`) before the heart. Status `fail` if the heart hits 0 while the warden is alive, or if no warden appears after the line.

Pass: `BOSS SPAWN` then `BOSS KILL`.

### 17. `win_screen`

Sword the origin cell until the heart is 0. Stop attacking. The overlay title is `Victory — Crystal Destroyed`, the subtitle is `You destroyed the crystal.` and `Press R to restart.`, and the run summary says the crystal was destroyed. Do not press restart, `quick_load`, or quit. Hold about 5 seconds so the screen is on the recording.

Pass: phase victory, `victory_reason` crystal, that title visible. Log `CRYSTAL DESTROYED`.

## Checklist

The bot rewrites `status` in place. `pending` means not played yet. Order is the play order.

```json
{
  "route": "showcase-speedrun",
  "version": 1,
  "scene": "res://scenes/main.tscn",
  "input": "events-only",
  "features": [
    {"id": "boot_tutorial", "segment": 1, "required": true, "actions": ["pause", "pause"], "pass": "how-to-play hidden", "status": "pending"},
    {"id": "movement", "segment": 2, "required": true, "actions": ["sprint", "move_forward", "jump", "rotate_left", "rotate_right"], "pass": "moved >= 8 columns and left the ground", "status": "pending"},
    {"id": "lighting", "segment": 3, "required": true, "actions": [], "pass": "player shadow under the locked sun during the walk", "status": "pending"},
    {"id": "day_night", "segment": 4, "required": true, "actions": [], "pass": "no clock exists", "status": "pending"},
    {"id": "dig_tool", "segment": 5, "required": true, "actions": ["hotbar_2", "attack"], "pass": "stone pick removed a single surface cell", "status": "pending"},
    {"id": "structure_place", "segment": 6, "required": true, "actions": ["inventory_toggle", "mouse:Craft_wall_segment", "hotbar_7", "build_place"], "pass": "wall_segment placed", "status": "pending"},
    {"id": "density_poi", "segment": 7, "required": true, "actions": ["sprint", "move_forward", "rotate_left", "rotate_right"], "pass": "stood on the chain's camp, abandoned_dig, crystal_grove, or shrine, or too-far", "status": "pending"},
    {"id": "density_treasure", "segment": 8, "required": true, "actions": ["sprint", "move_forward", "rotate_left", "rotate_right"], "pass": "inside 10 columns of the chain's treasure_site and the director discovered it, or too-far", "status": "pending"},
    {"id": "density_landmark", "segment": 9, "required": true, "actions": ["sprint", "move_forward", "rotate_left", "rotate_right"], "pass": "chain landmark in frame, glow logged, or too-far", "status": "pending"},
    {"id": "combat_crystal_mite", "segment": 10, "required": true, "actions": ["hotbar_1", "attack", "hotbar_3", "attack"], "pass": "KILL crystal_mite after the pool scan, or absent", "status": "pending"},
    {"id": "combat_farm_bomber", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "combat_crystal_stag", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "combat_thornling", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "combat_corrupted_beast", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "combat_crystal_wisp", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "combat_shard_guard", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "combat_spawn_elite", "segment": 10, "required": true, "actions": ["hotbar_1", "attack"], "pass": "KILL or absent", "status": "pending"},
    {"id": "xp_level", "segment": 11, "required": true, "actions": [], "pass": "LEVEL >= 3 and earned >= 191 before the crystal, not a grant", "status": "pending"},
    {"id": "skill_dash", "segment": 12, "required": true, "actions": ["skill_tree", "ui_down", "ui_accept", "skill_tree", "move_forward", "skill_1"], "pass": "SKILL dash and a slide", "status": "pending"},
    {"id": "skill_ground_slam", "segment": 13, "required": true, "actions": ["skill_tree", "ui_right", "ui_accept", "skill_tree", "skill_2"], "pass": "SKILL ground_slam and a 3x3 dig", "status": "pending"},
    {"id": "multiblock_break", "segment": 13, "required": true, "actions": ["skill_2"], "pass": "same 3x3; the stone pick stays single", "status": "pending"},
    {"id": "skill_crystal_pulse", "segment": 14, "required": true, "actions": ["skill_tree", "ui_accept", "skill_tree", "skill_3"], "pass": "SKILL crystal_pulse on the dry ring", "status": "pending"},
    {"id": "skill_quick_wall", "segment": 14, "required": true, "actions": ["skill_tree", "ui_right", "ui_right", "ui_down", "ui_accept", "skill_tree"], "pass": "placed a segment after freeing a slot", "status": "pending"},
    {"id": "skill_passives", "segment": 14, "required": true, "actions": ["skill_tree", "ui_accept"], "pass": "miner_passive unlocked on the tree", "status": "pending"},
    {"id": "crystal", "segment": 15, "required": true, "actions": ["hotbar_1", "attack"], "mouse": "origin column", "pass": "heart <= 125 from swings", "status": "pending"},
    {"id": "boss", "segment": 16, "required": true, "actions": ["hotbar_1", "attack", "skill_1", "skill_2"], "pass": "BOSS SPAWN and BOSS KILL while the heart remains", "status": "pending"},
    {"id": "win_screen", "segment": 17, "required": true, "actions": ["hotbar_1", "attack"], "pass": "Victory — Crystal Destroyed, then hold", "status": "pending"}
  ]
}
```
