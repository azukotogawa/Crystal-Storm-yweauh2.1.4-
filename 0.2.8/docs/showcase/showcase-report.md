# Showcase report

Checked 2026-10-16. This is the windowed honest-bot recording `20261016-035639-showcase`. The bot only sends input events. It does not teleport, grant XP or items, write health, or change balance.

The run does not play to a win. The last frame is the defeat card. Crystal HP is still 350/500. Boss defeated: no. Crystal destroyed: no.

## Files

| File | Result |
| --- | --- |
| `D:\ARCHIVE\CrystalStorm\verify-evidence\20261016-035639-showcase\honest-bot-showcase.avi` | Present. 608,878,592 bytes. MJPEG, 1280x720, 30 fps. ffprobe duration is `N/A` (no index duration). Sampled JPEGs, including the first and the last, are 1280x720. |
| `D:\ARCHIVE\CrystalStorm\verify-evidence\20261016-035639-showcase\honest-bot-showcase.mp4` | Present but not a playable file. 92,799,024 bytes. ffprobe: `moov atom not found`. The ffmpeg log stops mid-encode around frame 2687 (`time=00:01:31`) with no completion footer. The output header had already declared 1280x720, but the file never got a moov atom, so resolution and duration cannot be read back from the mp4. |
| `contact-sheet.png` | Missing. No `contact-sheet-ffmpeg.log` in the run folder. `finish_record` only writes the sheet after a passing command, and this command printed `FAIL` lines. The encode was also cut off before that step. |
| `chapters.json` and `chapters.txt` | Present in the run folder. They are not muxed into the mp4 (no `chapters-ffmpeg.log`, no `showcase-chaptered.mp4`). |
| `D:\ARCHIVE\CrystalStorm\verify-evidence\showcase\` | Did not exist before this report. The recorder only copies here after `RECORD OK`. |
| `D:\LATEST\CrystalStorm\showcase-speedrun.mp4` | Not present. Same reason. |

Godot's own line is `Movie Maker mode enabled, recording movie in 1280×720 @ 30 FPS` and the script printed `SHOWCASE capture 1280 720`. The AVI and the extracted frames meet >=720p. The mp4 does not, because it is truncated.

## Total run time

- On-screen showcase timer on the last AVI frame: **6:48.07** (408.07 s). `chapters.txt` ends at **408.066**.
- Defeat-card clock on that same frame: **416.1 s**.
- Godot wall clock: start `2026-10-16T03:56:39-07:00`, `# exit=0 end=2026-10-16T04:03:42-07:00` (**7 min 3 s**). Exit 0 is the process code. The log still contains `HONEST BOT SHOWCASE FAIL`, so the wrapper does not treat the run as a pass.

## Features shown

Times are the showcase clock in seconds, from `chapters.txt`. Status is the matching `SHOWCASE` line in `honest-bot-showcase.log`.

| Feature | Start | End | Status | What the run actually did |
| --- | --- | --- | --- | --- |
| `boot_tutorial` | 0.001 | 0.143 | pass | How to play was closed. The player could move. |
| `movement` | 0.190 | 1.439 | pass | `OK movement columns 8.23 jump true sprint true`. |
| `lighting` | 1.503 | 2.862 | pass | Locked sun, player kept in frame. |
| `dig_tool` | 2.972 | 6.891 | pass | Stone pick. `SHOWCASE dig column 999 -953`. |
| `structure_stone_wall` | 6.967 | 8.341 | placed | One stone wall. |
| `structure_wall_corner` | 8.341 | 9.057 | shown | Ghost only. |
| `structure_gate` | 9.057 | 9.791 | shown | Ghost only. |
| `structure_stairs` | 9.791 | 10.488 | shown | Ghost only. |
| `structure_small_tower` | 10.488 | 11.169 | shown | Ghost only. Starter stone cannot also pay the 12-stone tower. |
| `structure_wall_segment` | 11.169 | 11.281 | shown, then placed | Crafted and placed. |
| `structure_place` | 11.281 | 11.774 | pass | A zero-length `structure_place` row also sits at 6.967. |
| `density_poi_crystal_grove` | 11.891 | 141.690 | pass | Sprint to the grove. About 130 seconds. |
| `density_treasure` | 141.761 | 150.354 | pass | Treasure Site 4 at (86, -242). Loot stone 7, herb 3, wood 5. Relic `mason_glove`. |
| `density_landmark_rock_spire` | 150.429 | 158.468 | pass | Rock spire in frame. |
| `combat_crystal_mite` | 158.572 | 391.064 | pass | Four `KILL crystal_mite` lines. `SHOWCASE kills mite 4 level 2`. The defeat card later says enemies killed: 2. |
| `xp_level` | 391.940 | 391.941 | pass | `LEVEL 2 xp 64`. |
| `skill_dash` | 392.017 | 395.017 | pass | `SKILL dash`. `OK dash slide 4.99`. |

Sampled frames agree with that clock: dig at 0:03.03, the grove walk at 0:44.06 and 2:12.13, the mite chapter at 4:03.55 and 5:59.70, the crystal chapter at 6:41.23 with HP 1/104, and the defeat card at 6:48.07.

## Features the bot did not show

| Feature | Status | Why |
| --- | --- | --- |
| `day_night`, night, torch | absent (2.914–2.918) | The game has no day clock and no torch light. The route forbids faking one. |
| `glow` | absent | The landmark on this seed is a rock spire, not a crystal-glow mesh. |
| `combat_farm_bomber`, `combat_crystal_stag`, `combat_thornling`, `combat_corrupted_beast`, `combat_crystal_wisp`, `combat_shard_guard`, `combat_spawn_elite` | absent (zero-length chapters from 391.192 to 391.841) | None of those ids were alive inside 32 columns. The route does not wait for absorption unlocks. |
| `skill_ground_slam`, `multiblock_break` | skipped-no-point (395.125, 395.230) | Still level 2 at 64 XP. Level 3 needs 191. The stone pick stays a single-cell break, so the 3×3 never happens. |
| `skill_crystal_pulse`, `skill_quick_wall`, `skill_passives` | skipped-no-point (395.335–395.530) | No spare skill point. The route does not farm a second biome for them. |
| `crystal` | fail (395.605–408.066) | Heart was 350/500. Camp `957,-956` at depth 0.21. `Run lost: You died.` `DEATH hp 0.0`. |
| `boss` | not played | The warden spawns at 25% heart HP (125). The heart never got there. No `BOSS SPAWN`. |
| `win_screen` | not played | No victory title. The last frame is `Phase: Defeat`, `You died`, `Crystal destroyed: no`, `Boss defeated: no`. |
| Bow shot | not confirmed | The route asks for one shortbow shot on the first mite. The log has no bow line, and the frames sampled in that chapter show the sword. |

`FAIL showcase segment failed` and `FAIL sidecar missing crystal, boss, or win` follow the death. The sidecar has a failed `crystal` chapter and no `boss` or `win_screen` rows.

## Known glitches

- The mp4 encode was killed before the moov atom. ffprobe cannot open it. There is no contact sheet and no copy at `verify-evidence\showcase\` or `D:\LATEST\CrystalStorm\showcase-speedrun.mp4`.
- The first AVI JPEG is a blank gray viewport with only the timer `0:01.25` and the word `movement`. Later frames show the world. The opening of the movie does not show terrain.
- The chapter label is drawn on top of the crystal HP panel, so names such as `dig_tool` and `crystal` cover the HUD text.
- Sword swings whiff. The mite chapter logs seven `[Combat] melee wooden_sword — no entity hit` lines.
- The player stands in the crystal pool (a sampled frame at 5:59.70 is inside the pink disk, heart already under 500, "Used herb (+28 HP)"). The crystal chapter then dies in that burn in about 12 seconds with the heart still at 350/500.
- Kill count disagrees. The log prints four `KILL crystal_mite` lines. The defeat card says enemies killed: 2.
- `structure_place` is written twice, once with a zero-length span at 6.967.
- Absent and skipped beats are zero-length chapters (`start` equal to `end`).
- During `lighting`, Godot prints `global_shader_parameter_get` — "This function should never be used outside the editor".
- These sounds are missing and skipped: `ui_open`, `ui_close`, `boss_telegraph`, `boss_slam`, `swing_sword`, `enemy_hurt`, `hit_light`, `crystal_crackle`, `player_hurt`, `pickup`, `enemy_death`, `music_assault`, `run_lose`.
- Godot exits 0 even though the script printed `HONEST BOT SHOWCASE FAIL`. The wrapper still fails the command because a line starts with `FAIL`.

## Command to reproduce

From WSL, at the repo root:

```bash
cd /mnt/c/Users/cwith/Crystal-Storm-yweauh2.1.4-
bash .cursor/skills/verify-crystal-storm/cs-verify.sh record showcase
```

That is what produced this run. The captured process line was:

```text
godot --write-movie D:/ARCHIVE/CrystalStorm/verify-evidence/20261016-035639-showcase/honest-bot-showcase.avi --fixed-fps 30 --disable-vsync --windowed --resolution 1280x720 --path /mnt/c/Users/cwith/Crystal-Storm-yweauh2.1.4-/0.2.8 -s res://scripts/verify_honest_bot_showcase.gd
```

`run_id=20261016-035639-showcase`. A new run gets a new id. A pass would also copy the mp4, the contact sheet, and the chapter sidecar to `D:\ARCHIVE\CrystalStorm\verify-evidence\showcase\` and the mp4 to `D:\LATEST\CrystalStorm\showcase-speedrun.mp4`. This run did not pass, so those copies were not made.

## Still open

Finishing the ffmpeg encode of the existing AVI would make a playable mp4 of this same loss. It would not be a win, and it would not add the missing boss or victory chapters. A winning movie needs another `record showcase` after the bot can leave the burn alive, reach 125 heart HP, kill the warden, and hold the victory title.
