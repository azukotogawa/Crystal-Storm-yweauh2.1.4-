# Sounds needed

No audio files are shipped. `AudioManager` looks up each id in `config/audio_manifest.gd` and skips a missing file (one log line per id). Drop a real recording at the path below. Ogg Vorbis. Do not generate placeholder audio.

Buses: **Master** (final), **Music**, **SFX**, **UI**. Music follows the maze and assault phases. Volumes persist in `player_settings.json`.

| Id | Bus | File | When it plays | Length | Character |
| --- | --- | --- | --- | --- | --- |
| `swing_sword` | SFX | `res://assets/audio/sfx/swing_sword.ogg` | Player swings the wooden sword | 0.12s | Short dry whoosh, light wood |
| `swing_spear` | SFX | `res://assets/audio/sfx/swing_spear.ogg` | Player thrusts the spear | 0.14s | Tight forward stab, little air |
| `swing_hammer` | SFX | `res://assets/audio/sfx/swing_hammer.ogg` | Player slams the crystal hammer | 0.28s | Heavy overhead whoosh into a low thud |
| `swing_pick` | SFX | `res://assets/audio/sfx/swing_pick.ogg` | Player swings the stone pick | 0.10s | Small metallic tick and grit |
| `hit_light` | SFX | `res://assets/audio/sfx/hit_light.ogg` | A light or normal hit lands | 0.08s | Soft crack, not a boom |
| `hit_heavy` | SFX | `res://assets/audio/sfx/hit_heavy.ogg` | Hammer, bomb, or other heavy hit | 0.20s | Thick impact with a short ring |
| `fire_bow` | SFX | `res://assets/audio/sfx/fire_bow.ogg` | Shortbow fires an arrow | 0.16s | String snap and a thin whistle |
| `fire_sling` | SFX | `res://assets/audio/sfx/fire_sling.ogg` | Sling looses a stone | 0.12s | Leather snap, low and short |
| `impact_arrow` | SFX | `res://assets/audio/sfx/impact_arrow.ogg` | Arrow hits a body, crystal, or ground | 0.10s | Thunk, muffled |
| `impact_stone` | SFX | `res://assets/audio/sfx/impact_stone.ogg` | Sling stone hits | 0.08s | Pebble clack |
| `bomb_throw` | SFX | `res://assets/audio/sfx/bomb_throw.ogg` | Crystal bomb leaves the hand | 0.14s | Soft toss and a crystal clink |
| `bomb_explode` | SFX | `res://assets/audio/sfx/bomb_explode.ogg` | Crystal bomb detonates | 0.45s | Bright crystal crack, then a low blast |
| `dig` | SFX | `res://assets/audio/sfx/dig.ogg` | Pick removes a terrain layer | 0.10s | Dry dirt scoop |
| `build_place` | SFX | `res://assets/audio/sfx/build_place.ogg` | Wall, gate, bridge, or fill is placed | 0.12s | Stone set down, solid |
| `build_remove` | SFX | `res://assets/audio/sfx/build_remove.ogg` | A placed structure layer is removed | 0.10s | Block lift and grit |
| `crystal_crackle` | SFX | `res://assets/audio/sfx/crystal_crackle.ogg` | Crystal mass takes damage and stays | 0.12s | Glass tickle, quiet |
| `crystal_shatter` | SFX | `res://assets/audio/sfx/crystal_shatter.ogg` | A crystal cell breaks | 0.28s | Shard burst, bright and short |
| `spawn_destroyed` | SFX | `res://assets/audio/sfx/spawn_destroyed.ogg` | A crystal spawn heart is destroyed | 0.70s | Large crystalline collapse |
| `enemy_hurt` | SFX | `res://assets/audio/sfx/enemy_hurt.ogg` | An enemy or creature takes a non-lethal hit | 0.10s | Soft organic hit |
| `enemy_death` | SFX | `res://assets/audio/sfx/enemy_death.ogg` | An enemy or creature dies | 0.35s | Drop and a short dissolve hiss |
| `boss_telegraph` | SFX | `res://assets/audio/sfx/boss_telegraph.ogg` | Warden or tyrant starts a windup | 0.40s | Rising crystal tone, warns the slam |
| `boss_slam` | SFX | `res://assets/audio/sfx/boss_slam.ogg` | Boss slam, charge, or burst lands | 0.35s | Ground hit, heavier than the hammer |
| `boss_phase` | SFX | `res://assets/audio/sfx/boss_phase.ogg` | Origin Warden enters phase 2 | 0.80s | Chord shift, ominous, not a sting |
| `boss_death` | SFX | `res://assets/audio/sfx/boss_death.ogg` | Origin Warden dies | 1.20s | Large crystal break, then quiet |
| `player_hurt` | SFX | `res://assets/audio/sfx/player_hurt.ogg` | Player takes a burst hit | 0.16s | Close thud, no voice line |
| `player_death` | SFX | `res://assets/audio/sfx/player_death.ogg` | Player dies | 0.80s | Low falloff, ends the run |
| `pickup` | SFX | `res://assets/audio/sfx/pickup.ogg` | Loot, herb use, or similar gain | 0.10s | Small bright blip |
| `water_splash` | SFX | `res://assets/audio/sfx/water_splash.ogg` | Feet enter or leave water, or a shot lands in it | 0.22s | Light splash, not a wave |
| `corruption_spread` | SFX | `res://assets/audio/sfx/corruption_spread.ogg` | A tile corrupts (rate-limited with the particle) | 0.30s | Quiet crystal whisper |
| `run_win` | SFX | `res://assets/audio/sfx/run_win.ogg` | Run is won | 1.40s | Short triumph, crystal and horn |
| `run_lose` | SFX | `res://assets/audio/sfx/run_lose.ogg` | Run is lost | 1.20s | Low descending tone |
| `relic_open` | UI | `res://assets/audio/ui/relic_open.ogg` | Relic choice modal opens | 0.35s | Soft chime, modal |
| `relic_pick` | UI | `res://assets/audio/ui/relic_pick.ogg` | Player picks a relic | 0.28s | Confirm chime, warmer than click |
| `ui_click` | UI | `res://assets/audio/ui/ui_click.ogg` | Button press | 0.05s | Dry click |
| `ui_hover` | UI | `res://assets/audio/ui/ui_hover.ogg` | Pointer enters a button | 0.04s | Very quiet tick |
| `ui_open` | UI | `res://assets/audio/ui/ui_open.ogg` | Pause, inventory, or a menu screen opens | 0.12s | Soft open |
| `ui_close` | UI | `res://assets/audio/ui/ui_close.ogg` | Pause, inventory, or relic modal closes | 0.10s | Soft close |
| `music_maze` | Music | `res://assets/audio/music/music_maze.ogg` | Maze phase loop | 60–90s loop | Sparse, building, low pulse |
| `music_assault` | Music | `res://assets/audio/music/music_assault.ogg` | Assault phase loop | 45–75s loop | Tighter rhythm, same palette as the maze bed |

Hook map (code, not files):

- Swings, shots, dig, place, and remove: `weapons/weapon_controller.gd`
- Hit weight, crystal crackle/shatter, spawn burst, bomb burst: `systems/combat_visual_feedback.gd`
- Arrow, stone, and bomb impact, plus water: `weapons/projectile.gd`
- Player hurt, death, landing bob, foot splash: `player/player.gd`
- Creature and crystal-enemy hurt, death, bob, and boss telegraph/slam/phase: `entities/world_entity.gd`, `entities/crystal_enemy.gd`
- Corruption pulse: `crystal/crystal_manager.gd` when a cell actually corrupts
- Pickup: `helpers/combat_rewards.gd` (and herb use in the weapon controller)
- Relic open/pick, pause, inventory, frontend buttons: the matching `ui/` scripts
- Music and run win/lose: `AudioManager` listens to `GameManager` phase and run-state signals
