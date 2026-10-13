# UI, settings, and onboarding

Menus, tooltips, the first-run tutorial, and the end-of-run summary. Gameplay rules stay in `Combat.md`, `Player.md`, and `INPUT_CONTRACT.md`. Presentation toggles that juice already owned are listed again in `Effects.md`.

## Theme

`ui/theme/theme_builder.gd` builds one `Theme` from Pixelify Sans (`assets/fonts/PixelifySans.ttf`, SIL OFL 1.1, see `assets/fonts/README.md`). Panel, button, slider, and tooltip styles use the crystal purple palette. The theme is applied on the HUD, hotbar, inventory, pause menu, frontend, relic choice, and boss bar. There is no `crystal_theme.tres`; the theme is built in code and cached.

UI scale is `Window.content_scale_factor` on the root window (75%–150%). Theme font sizes stay at the 100% design size so scale is not applied twice.

## Tooltips

`ui/tooltip_panel.gd` is one `CanvasLayer` (layer 90). It follows the mouse, clamps to the visible rect, and only runs `_process` while it is visible. Copy comes from `ui/tooltip_text.gd`, which reads `ItemDef` / `ItemTypes` and `RelicRegistry`. Hovering a hotbar slot, an inventory cell, worn armor, or a relic choice shows name, damage, range, cooldown, crystal damage, armor reduction, description, and effects. Those labels are chrome. The numbers and names are not hardcoded item strings.

## Settings

`ui/settings_menu.gd` is the shared body. The frontend settings screen and the pause menu both embed it. The body is a tab container (`SettingsTabs`): Graphics, Audio, Display, Accessibility, Controls. A Close button under the tabs is always visible. Opening the menu copies the saved file onto the widgets with signals blocked, so opening pause does not write the file. Later edits save immediately.

Closing Settings by Escape, Close, Resume, or leaving any tab hides the pause layer and every tab page, cancels a pending key rebind, calls `gui_release_focus`, and dismisses the controls overlay. That overlay is its own `CanvasLayer` (layer 70), not a child of the pause menu. The first Escape while a rebind is listening only cancels the capture. The next Escape closes.

Persistence is `user://player_settings.json` (`PlayerSettings.DEFAULT_PATH`). `load_settings()` merges the file onto `defaults()`, then `_sync_runtime` copies the statics, applies keybinds, UI scale, and display. `save_settings()` starts from `defaults()` and merges the dictionary you pass, so a partial save resets omitted keys. Callers that only mean to change one field load first, then overlay.

`AudioManager` calls `load_settings()` from its `_ready`, before gameplay reads input. That is what installs saved keybinds and the UI scale at boot.

| Key | Default | Effect |
| --- | --- | --- |
| `quality_preset` | Medium | Low / Medium / High / Safe. Safe is the existing perf preset. |
| `render_distance` | 2 | Chunk ring, clamped 1–8. |
| `vegetation_scatter_multiplier` | 1 | Scatter density, 0–1. |
| `combat_visuals_enabled` | on | Combat presentation. |
| `screen_shake_enabled` | on | Camera offset. Forced off while Reduce motion is on. |
| `hit_stop_enabled` | on | Time-scale dip. Forced off while Reduce motion is on. |
| `flash_effects_enabled` | on | White hit flash. Independent of Reduce motion. |
| `hit_markers_enabled` | on | World hit, miss, and blocked markers. Independent of Reduce motion. |
| `crack_overlay_enabled` | on | Mining crack overlay. Independent of Reduce motion. Break chips still play. |
| `volume_master` / `volume_music` / `volume_sfx` / `volume_ui` | 1 | Linear bus gain on Master, Music, SFX, UI. |
| `fullscreen` | off | Display mode. Ignored on the headless server. |
| `vsync` | on | `DisplayServer` vsync mode. Ignored headless. |
| `resolution` | `1280x720` | Windowed size. Choices: 1280x720, 1366x768, 1600x900, 1920x1080, 2560x1440. Disabled while fullscreen. |
| `ui_scale` | 1 | Content scale, clamped 0.75–1.5. |
| `colorblind_palette` | off | Alternate crystal colours. See below. |
| `reduce_motion` | off | Disables shake, hit-stop, walk bob, creature bob, and the large shatter / spawn-death bursts. |
| `tutorial_completed` | off | First-run overlay stays dismissed. |
| `camera_cutaway_enabled` | on | Graphics tab. Cave cutaway between the camera and the player. |
| `texture_blueprint` | off | Graphics tab and F6. Swaps textures for labelled placeholders. Export texture manifest writes `docs/texture_manifest.json`. |
| `keybinds` | `{}` | Per-action event lists. Empty means the project defaults. |

### Keybinds

`systems/input_bindings.gd` owns every gameplay action in `project.godot`, plus `pause` (Escape). It does not rebind `ui_accept`. Defaults are captured once from the `InputMap` before any saved map is applied, so Reset restores the input contract: WASD move, Space jump, Q/E yaw, Page Up / Page Down pitch, V unstuck. Middle-mouse drag also tilts the camera and is not a rebindable action. A click on a row listens for the next key or mouse button. Escape cancels the listen and leaves the menu open. A conflict (same key and modifiers, or the same mouse button, on another gameplay action) is refused and named. Bindings round-trip through `keybinds` in the settings file.

### Colour-blind palette

`ui/crystal_palette.gd` picks an alternate crystal set with different luminance (bright gold mass, blue markers). `CrystalManager.apply_color_palette` writes existing albedo, emission, and sprite modulate. The objective-arrow colour is cached on the HUD when the palette changes. No new textures.

### Reduce motion

The flag is its own key. `Juice` refuses shake, hit-stop, and bob while it is on, including `force` calls used by probes. Flash stays on its own toggle. The settings screen also unchecks and disables shake and hit-stop while Reduce motion is checked, and writes those two keys off. Turning Reduce motion off unlocks the checkboxes and leaves them as they are. Large `VfxPool` bursts (`SHATTER`, `SPAWN_DEATH`) return without spawning. Dust, splash, corruption, and break chips still play. The place pop snaps to full size. Hit markers and the crack overlay keep their own toggles.

## Onboarding

`ui/tutorial_overlay.gd` shows six short steps: move, rotate and tilt the camera (and V to get unstuck), attack a crystal (weapons do not dig), dig and build, follow the spawn arrow, and the boss goal. Skip, or Next on the last step, sets `tutorial_completed`. Headless runs do not auto-open it and do not pause the tree. `should_show()` is false when `DisplayServer` is headless. `wants_tutorial()` is the persisted flag and stays testable headless. Pause, settings, and the frontend can reopen the steps or a Controls page. The Controls page lists each action with `InputBindings.binding_text`, so rebound keys show up. Closing settings or pressing Escape while pause is open frees that page.

## Run summary

`GameManager` counts spawns destroyed, crystal cells broken, enemies killed, relics taken, and deaths on the existing signals. `grant_player_kill` is the kill counter. Time is `Time.get_ticks_msec()` at run start, read when the summary is built. Nothing in `_process` accumulates these stats.

`run_summary()` returns `outcome` (`win`, `loss`, or `playing`), `time_sec`, `spawns_destroyed`, `boss_defeated`, `crystal_broken`, `enemies_killed`, `relics_taken`, `deaths`, `victory_reason`, and `loss_reason`.

On win or loss, `ui/game_overlay.gd` keeps the existing victory titles and adds `ui/run_summary_panel.gd` under the panel. World Select calls `return_to_world_select` on the `game` group. New Run calls `restart_run` on `game_manager`.

## Probes

- `scripts/verify_ui_settings.gd` — rebind persists, conflict, reset, bus volume, UI scale, reduce motion, colour-blind colours, tutorial flag.
- `scripts/verify_settings_close.gd` — every settings tab, including Controls, closes on Escape and on Close. Rebind cancel, focus, and gameplay input are checked.
- `scripts/verify_tooltips.gd` — weapon, armor, and relic tooltip text.
- `scripts/verify_run_summary.gd` — summary dictionary and panel after a simulated win and loss.

These are `SceneTree` scripts. They quit on their own, so they are not in the abrupt-exit marker map.
