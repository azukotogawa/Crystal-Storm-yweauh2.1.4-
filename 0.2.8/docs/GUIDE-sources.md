# GUIDE.md part 1 — sources

Version checked: `0.2.8/project.godot` line 14, `config/version="0.4.1"`.

The player guide is `0.2.8/docs/GUIDE.md` (same text as `D:\LATEST\CrystalStorm\GUIDE.md`). Every input-map action and every settings key is named there in backticks. This file is the line each claim came from.

Win and loss (not an input or a setting, listed so the goal section can be checked):

- One crystal on: `0.2.8/config/game_config.gd` line 13 `SINGLE_CRYSTAL`.
- Destroying it sets `victory_reason` to `crystal` and wins: `0.2.8/game/game_manager.gd` lines 317–321.
- Boss death does not win while that flag is on: `0.2.8/game/game_manager.gd` lines 336–342.
- Boss appears at 25% health: `0.2.8/entities/boss_brain.gd` line 6 `BOSS_SPAWN_HEALTH_RATIO`.
- Death is the loss: `0.2.8/game/game_manager.gd` line 11 `DEATH_ONLY_LOSS`, lines 355–357 `_on_player_died`.
- Coverage does not end the run: `0.2.8/game/game_manager.gd` lines 150–152 and 156–159.
- A fallen town does not end the run: `0.2.8/game/game_manager.gd` lines 183–204.
- Crystal-touch loss switch is off: `0.2.8/crystal/crystal_manager.gd` line 50 `player_contact_defeat_enabled` false; emit at lines 2069–2079.
- Objective text: `0.2.8/ui/game_overlay.gd` line 559.
- Stale How to play win card: `0.2.8/ui/tutorial_overlay.gd` lines 191–192.
- Starting items: `0.2.8/player/player.gd` lines 872–884. Selected slot is the pick: line 342.
- Main scene: `0.2.8/project.godot` line 15 `res://scenes/frontend.tscn`. Menu title: `0.2.8/ui/frontend_root.gd` line 157.

## Input map

Every action in `0.2.8/project.godot` under `[input]` (the section starts at line 42). Bindings are the `physical_keycode` or mouse `button_index` on the following lines. The guide names each action in a controls table.

| Action | Default | Map line | Behavior line | In GUIDE.md |
| --- | --- | --- | --- | --- |
| `jump` | Space (32) | `project.godot:44` | Rise in water, else hop: `player/player.gd:427` and `:432` | yes |
| `sprint` | Shift (4194325) | `project.godot:49` | Land only: `player/player.gd:464` | yes |
| `move_left` | A (65) | `project.godot:54` | `player/player.gd:403` | yes |
| `move_right` | D (68) | `project.godot:59` | `player/player.gd:401` | yes |
| `move_forward` | W (87) | `project.godot:64` | `player/player.gd:407` | yes |
| `move_back` | S (83) | `project.godot:69` | `player/player.gd:405` | yes |
| `ui_accept` | Enter (4194309), keypad Enter (4194310), joypad button 0 | `project.godot:74` | Skill tree: `ui/skill_tree_panel.gd:170` | yes |
| `rotate_left` | Q (81) | `project.godot:81` | `player/camera.gd:201` | yes |
| `rotate_right` | E (69) | `project.godot:86` | `player/camera.gd:203` | yes |
| `attack` | Mouse left (button 1), F (70) | `project.godot:91` | Dig or attack: `weapons/weapon_controller.gd:130` | yes |
| `inventory_toggle` | I (73) | `project.godot:97` | `ui/inventory_panel.gd:61` | yes |
| `interact` | R (82) | `project.godot:102` | Same place path: `weapons/weapon_controller.gd:155` | yes |
| `build_place` | Mouse right (button 2) | `project.godot:107` | `weapons/weapon_controller.gd:155` | yes |
| `plant` | G (71) | `project.godot:112` | `weapons/weapon_controller.gd:1236` | yes |
| `channel_water` | Shift+T (84, shift) | `project.godot:117` | Pick only, Shift raises: `weapons/weapon_controller.gd:1257` | yes |
| `place_cycle` | Tab (4194306) | `project.godot:122` | `weapons/weapon_controller.gd:178` | yes |
| `dev_chat_toggle` | T (84) | `project.godot:127` | Action name: `systems/input_bindings.gd:49`. Chat panel: `ui/dev_chat_overlay.gd:1` | yes |
| `hotbar_1` | 1 (49) | `project.godot:132` | Slots: `weapons/weapon_controller.gd:180` | yes |
| `hotbar_2` | 2 (50) | `project.godot:137` | `weapons/weapon_controller.gd:180` | yes |
| `hotbar_3` | 3 (51) | `project.godot:142` | `weapons/weapon_controller.gd:180` | yes |
| `hotbar_4` | 4 (52) | `project.godot:147` | `weapons/weapon_controller.gd:180` | yes |
| `hotbar_5` | 5 (53) | `project.godot:152` | `weapons/weapon_controller.gd:180` | yes |
| `hotbar_6` | 6 (54) | `project.godot:157` | `weapons/weapon_controller.gd:180` | yes |
| `hotbar_7` | 7 (55) | `project.godot:162` | `weapons/weapon_controller.gd:180` | yes |
| `hotbar_8` | 8 (56) | `project.godot:167` | `weapons/weapon_controller.gd:180` | yes |
| `quick_save` | F5 (4194336) | `project.godot:172` | `systems/save_game_service.gd:72` and `:629` | yes |
| `quick_load` | F9 (4194340) | `project.godot:177` | `systems/save_game_service.gd:74` and `:633` | yes |
| `toggle_map` | M (77) | `project.godot:182` | `ui/topographical_map.gd:200` and `:246` | yes |
| `debug_overlay_toggle` | F3 (4194334) | `project.godot:187` | `systems/dev_tools_coordinator.gd:16` | yes |
| `bug_report` | F11 (4194342) | `project.godot:192` | `systems/dev_tools_coordinator.gd:20` | yes |
| `pause` | Escape (4194305) | `project.godot:197` | `ui/pause_menu.gd:34` | yes |
| `unstuck` | V (86) | `project.godot:202` | `player/player.gd:775` | yes |
| `camera_pitch_up` | Page Up (4194323) | `project.godot:207` | `player/camera.gd:137` | yes |
| `camera_pitch_down` | Page Down (4194324) | `project.godot:212` | `player/camera.gd:139` | yes |
| `texture_blueprint_toggle` | F6 (4194337) | `project.godot:217` | Settings checkbox: `ui/settings_menu.gd:74` | yes |
| `skill_1` | C (67) | `project.godot:222` | `systems/skill_service.gd:12` and `:223` | yes |
| `skill_2` | H (72) | `project.godot:227` | `systems/skill_service.gd:12` | yes |
| `skill_3` | J (74) | `project.godot:232` | `systems/skill_service.gd:12` | yes |
| `skill_tree` | K (75) | `project.godot:237` | `ui/skill_tree_panel.gd:8` | yes |

Count: 39 actions. That is the whole `[input]` section. No other joypad event is in the file. `ui_accept` is the only gamepad bind (button index 0, `project.godot:78`).

Rebind list (does not include the five skill and accept actions): `0.2.8/systems/input_bindings.gd` lines 4–16. Labels: lines 18–53. The settings tab builds one row per entry: `ui/settings_menu.gd` line 127.

### Not in the input map, still in the guide

- Mouse wheel zoom: `player/camera.gd` lines 378–381. Limits: lines 66–68.
- Middle-mouse pitch drag: `player/camera.gd` lines 366–374.
- Z and X for blueprints: `weapons/weapon_controller.gd` lines 1025–1031. Blueprint ids: `helpers/structure_blueprints.gd` lines 15–18. Large structures on: line 6.
- `[` and `]` dig brush: `weapons/weapon_controller.gd` lines 836–844.
- Shift and Ctrl plant modes: `weapons/weapon_controller.gd` lines 1236–1245.
- Channel mode after the key: `weapons/weapon_controller.gd` lines 1266–1269.
- `ui_up` / `ui_down` / `ui_left` / `ui_right` are read at `player/player.gd` lines 401–407 and `ui/skill_tree_panel.gd` lines 173–182. They are not keys in `project.godot`.
- Edge scroll is off: `player/camera.gd` line 22.

## Settings

Every key in `PlayerSettings.defaults()` (`0.2.8/systems/player_settings.gd` lines 49–76). The menu that shows it is `0.2.8/ui/settings_menu.gd`. The guide names each key in the settings tables.

| Key | Default line | Menu line | In GUIDE.md |
| --- | --- | --- | --- |
| `quality_preset` | `player_settings.gd:51` | Low/Medium/High/Safe: `settings_menu.gd:63` | yes |
| `render_distance` | `player_settings.gd:52` | Slider: `settings_menu.gd:69` | yes |
| `vegetation_scatter_multiplier` | `player_settings.gd:53` | Slider: `settings_menu.gd:70` | yes |
| `combat_visuals_enabled` | `player_settings.gd:54` | `settings_menu.gd:71` | yes |
| `screen_shake_enabled` | `player_settings.gd:55` | `settings_menu.gd:111` | yes |
| `hit_stop_enabled` | `player_settings.gd:56` | `settings_menu.gd:112` | yes |
| `flash_effects_enabled` | `player_settings.gd:57` | `settings_menu.gd:113` | yes |
| `hit_markers_enabled` | `player_settings.gd:58` | `settings_menu.gd:114` | yes |
| `crack_overlay_enabled` | `player_settings.gd:59` | `settings_menu.gd:115` | yes |
| `volume_master` | `player_settings.gd:60` | `settings_menu.gd:89` | yes |
| `volume_music` | `player_settings.gd:61` | `settings_menu.gd:90` | yes |
| `volume_sfx` | `player_settings.gd:62` | `settings_menu.gd:91` | yes |
| `volume_ui` | `player_settings.gd:63` | `settings_menu.gd:92` | yes |
| `ui_scale` | `player_settings.gd:64` | Range 0.75–1.5: `settings_menu.gd:108`. Limits: `player_settings.gd:8` | yes |
| `reduce_motion` | `player_settings.gd:65` | `settings_menu.gd:110`. Locks shake and hit stop: `settings_menu.gd:436` | yes |
| `colorblind_palette` | `player_settings.gd:66` | `settings_menu.gd:116` | yes |
| `tutorial_completed` | `player_settings.gd:67` | Not a checkbox. Written at `ui/tutorial_overlay.gd:237` | yes |
| `fullscreen` | `player_settings.gd:68` | `settings_menu.gd:94` | yes |
| `vsync` | `player_settings.gd:69` | `settings_menu.gd:95` | yes |
| `resolution` | `player_settings.gd:70` | Choices: `settings_menu.gd:12`. Label: line 97 | yes |
| `camera_cutaway_enabled` | `player_settings.gd:71` | `settings_menu.gd:73` | yes |
| `camera_pitch_degrees` | `player_settings.gd:72` | No slider. Saved from the camera: `player/camera.gd:171` | yes |
| `texture_blueprint` | `player_settings.gd:73` | `settings_menu.gd:74` | yes |
| `texture_set` | `player_settings.gd:74` | Original / Batch 1: `settings_menu.gd:79` | yes |
| `keybinds` | `player_settings.gd:75` | Rebind rows: `settings_menu.gd:127`. Reset: line 130 | yes |

Count: 25 keys. That is the whole `defaults()` dictionary.

Export texture manifest is a button, not a stored key: `ui/settings_menu.gd` line 83.

File path: `player_settings.gd` line 7 `user://player_settings.json`.

## Menus

- Main, world list, new world, delete confirm, settings screen: `ui/frontend_root.gd` lines 10, 155, 194, 323, 374, 418.
- Pause: `ui/pause_menu.gd` lines 113–129.
- Loading: `ui/loading_screen.gd` lines 180, 209, 341, 358.
- Inventory and craft: `ui/inventory_panel.gd` lines 58, 110, 116.
- Skill tree: `ui/skill_tree_panel.gd` lines 119 and 132. Skill ids: `systems/skill_service.gd` lines 21–27.
- Full map: `ui/topographical_map.gd` lines 246–254.
- Relic choice: `ui/relic_choice_panel.gd` line 22.
- Run summary buttons: `ui/run_summary_panel.gd` lines 26–32.
- Dev chat: `ui/dev_chat_overlay.gd` line 1.
- Actions blocked while those panels are open: `helpers/gameplay_input.gd` line 13.

## Save and load

- Continue file name: `systems/save_game_service.gd` line 34. Path helper: line 164.
- Alive check (health and run still playing): lines 244–256.
- Quit saves or drops continue: line 259. Window close calls it: `main.gd` lines 111–115 and 132–138. Pause quit: `ui/pause_menu.gd` line 175. Return to world select: `main.gd` line 141.
- Continue button enabled only when peek finds a living file: `ui/frontend_root.gd` lines 163–164 and 211. Dead or empty peek: `save_game_service.gd` lines 180–192.
- Continue launch does not also resume the world file: `ui/frontend_root.gd` lines 287–289. Boot loads the continue path: `save_game_service.gd` lines 92–97.
- World file: `save_game_service.gd` line 221. Play sets resume when that file exists: `systems/world_manager.gd` line 188. Boot loads it: `save_game_service.gd` lines 106–108.
- Quick slot 0: `config/save_game_config.gd` lines 5–7. Write and read: `save_game_service.gd` lines 629–635.
- Autosave every 300 seconds, on enemy unlock, and on town state 2: `config/save_game_config.gd` lines 10–13 and `save_game_service.gd` lines 78–87 and 147–161.
