# Crystal Storm — player guide (part 1)

**Version 0.4.1.** This is for someone opening the game for the first time. It covers what the game is, how you win and lose, how to start, every control, every menu, every setting, and how saving works. Later parts are not in this file.

The in-game **How to play** card still says you win by defeating the Origin Warden or by destroying every crystal heart. That sentence is out of date. Use this guide for the goal.

## What this game is

Crystal Storm is a 3D game about a world you can dig and build, and one crystal that spreads through that world. You walk an isometric view of voxel terrain: plains, forest, rivers, towns, ruins, plants, and animals. The crystal grows, feeds on what it covers, and sends creatures at you. You gather wood and stone, place walls and larger structures, swim, fight, and earn experience toward a few skills.

You start with a wooden sword, a stone pick (already selected), a shortbow, 16 wood, 16 stone, and 4 herbs on the hotbar. The bag behind that holds a spear, a crystal hammer, a sling, 3 crystal bombs, a stone plate, and leather armor already worn.

The window title is Crystalstorm. The first scene is the main menu.

## The goal

There is one crystal. **Destroy it and you win.** The objective line on the screen says "Destroy the crystal" and shows its health. The win screen is titled Win, and the summary says the crystal was destroyed.

When that crystal's health first drops to a quarter of its maximum (25%), one boss mob appears beside it. A warning tells you it spawned. **Killing that boss does not win.** The crystal can still be damaged while the boss is alive. Only breaking the crystal ends the run as a win.

## How you lose

**Dying is the only way to lose.** When your health reaches zero, the run ends and the screen says "You died."

These do not end the run:

- The crystal covering a large part of the map. You get a note that coverage is past the cap, and the HUD can say "over cap."
- A town falling. The crystal gains power, that town's defenders leave, and a message names the town. You keep playing.

Standing in deep crystal while the fight is close burns your health, after a short warning glow. That burn can kill you. The kill is still a death, not a separate loss.

An older "the crystal touched you and the run ends" switch exists in the crystal code and is **off**.

## How to start and play

1. Launch the game. You land on the main menu: **Continue**, **Play**, **Settings**, **How to play**, **Controls**, **Quit**.
2. **Continue** is on only when the last session was saved while you were still alive. It puts you back in that session. If you quit dead, Continue stays off.
3. **Play** opens the world list. Pick a world and press **Play**, or press **New World**.
4. A new world asks for a name (the box starts as "New Storm") and a seed (the box starts as 12349). **Randomize** fills a new seed. **Create** adds the world and returns to the list. It does not drop you into the world until you press **Play**.
5. A loading screen appears. It says controls are locked until the nearby terrain is ready. Wait until that screen goes away. If startup fails, it offers **Retry** and **Rebuild World**.
6. You stand in the world. A small map sits on the HUD. Your health bar is just above the hotbar. The objective points you at the crystal.
7. Dig with the pick, fight with a weapon, build with stone or wood, and walk toward the crystal when you are ready. Explore, reshape the ground, and thin the crystal down. At a quarter of its health the boss shows up. Keep hitting the crystal until it breaks.
8. When the run ends (win or death), a summary shows time, whether the crystal was destroyed, whether the boss died, crystal broken, enemies killed, relics taken, deaths, and your level and XP. **World Select** leaves. **New Run** reloads the current scene.

While the world is loading, the full map is open, the pause menu is open, the skill tree is open, or the dev chat is open, movement and digging do not run.

## Controls

The camera looks down at an angle. W moves the way the camera is facing, not "north" on the map. Q and E turn that view.

Only one gamepad button is mapped: the bottom face button (button 0) does the same thing as Enter. Sticks and the other face buttons are not in the input map.

Keys below are the defaults in the project. Settings → Controls can replace most of them. Skill keys, Enter, and the extra mouse and letter keys in the last table are not on that rebind list.

### Move and camera

| Action | Default | What it does |
| --- | --- | --- |
| `move_forward` | W | Walk the way the camera faces. |
| `move_back` | S | Walk backward relative to the camera. |
| `move_left` | A | Strafe left relative to the camera. |
| `move_right` | D | Strafe right relative to the camera. |
| `sprint` | Shift | Hold to run on land. Does nothing to your speed while you are swimming under the surface. Wading a shallow river is already slower than dry ground. |
| `jump` | Space | Hop on land. A short tap is a shorter hop. You can still jump for a brief moment after walking off a ledge. Underwater, hold it to rise toward the surface instead of doing a land jump. You can also hop while floating. |
| `rotate_left` | Q | Turn the camera left. Hold it. |
| `rotate_right` | E | Turn the camera right. Hold it. |
| `camera_pitch_up` | Page Up | Tilt the view up. The tilt is saved. |
| `camera_pitch_down` | Page Down | Tilt the view down. The tilt is saved. |
| `unstuck` | V | Shove yourself out if the body is stuck in the ground. It has a short cooldown. |

The game also asks the engine for `ui_up`, `ui_down`, `ui_left`, and `ui_right` while you walk, and again inside the skill tree. Those four actions are **not** in this project's input map, so the arrow keys are not bound here.

### Fight, dig, and build

Aim with the mouse. The highlighted ground cell is where a dig, a hit, or a place will land. If that cell is out of reach, the game tells you instead of digging in the direction you face.

| Action | Default | What it does |
| --- | --- | --- |
| `attack` | Left mouse button, and F | Use the item in your hand. A sword, spear, bow, hammer, or sling attacks. They do not dig. The stone pick breaks blocks. Hold it to keep digging. Herbs, bombs, and armor do not break blocks. |
| `build_place` | Right mouse button | Place, or use a right-click item. Held, it repeats. If the cell you are aiming at is a damaged structure, one stone repairs it. If a structure blueprint is selected (see Z and X), that blueprint is placed. Otherwise the place-cycle item is placed (wall, fill, ramp, and so on). |
| `interact` | R | Same place / right-click path as the right mouse button. |
| `place_cycle` | Tab | Cycle the place list (fill, ramps, gate, bridge, wall, and the rest of that catalog). |
| `plant` | G | Plant on the ground ahead of you. With 2 wood you plant a bush. With 2 herbs you plant tall grass. Otherwise you plant a grass tuft. |
| `channel_water` | Shift+T | With the stone pick selected, edit a water channel on the aimed cell. Because this default key already holds Shift, the edit raises the channel. |
| `hotbar_1` | 1 | Select hotbar slot 1. |
| `hotbar_2` | 2 | Select hotbar slot 2. |
| `hotbar_3` | 3 | Select hotbar slot 3. |
| `hotbar_4` | 4 | Select hotbar slot 4. |
| `hotbar_5` | 5 | Select hotbar slot 5. |
| `hotbar_6` | 6 | Select hotbar slot 6. |
| `hotbar_7` | 7 | Select hotbar slot 7. |
| `hotbar_8` | 8 | Select hotbar slot 8. |

Weapons and tools swing on a short wind-up so you can see the hit coming. Enemy attacks wait through their own warning before they hurt you. Those timings are not keys.

### Skills, map, pause, and save

| Action | Default | What it does |
| --- | --- | --- |
| `skill_1` | C | Use skill slot 1, if you have unlocked a skill and put it in that slot. |
| `skill_2` | H | Use skill slot 2. |
| `skill_3` | J | Use skill slot 3. |
| `skill_tree` | K | Open or close the skill tree. The game pauses while it is open. |
| `ui_accept` | Enter, keypad Enter, gamepad button 0 | On the skill tree, spend a point on the highlighted skill or toggle that skill on a slot. Also the usual "accept" key for Godot UI focus. |
| `toggle_map` | M | Open or close the full-screen map. While it is open you cannot move or dig. Pause, chat, or the loading screen closes it. |
| `pause` | Escape | Open or close the pause menu. The game pauses. |
| `inventory_toggle` | I | Open or close the bag. |
| `quick_save` | F5 | Write quick-save slot 0. |
| `quick_load` | F9 | Load quick-save slot 0. |
| `debug_overlay_toggle` | F3 | Show or hide the compact debug overlay. |
| `bug_report` | F11 | Write a bug report folder. |
| `dev_chat_toggle` | T | Open or close the developer chat panel. Gameplay input stops while it is open. |
| `texture_blueprint_toggle` | F6 | Turn the texture blueprint stand-in on or off. The same switch is in Settings. It starts off. |

### Keys and mouse that are not their own input-map action

| Input | What it does |
| --- | --- |
| Mouse wheel | Zoom the camera in and out. |
| Middle mouse drag | Tilt the camera. The tilt is saved when you release. |
| Z | Turn the selected structure blueprint by 90 degrees. |
| X | Cycle structure blueprints: wall segment, wall corner, gate, stairs, small tower. |
| `[` and `]` | With a dig tool in hand, shrink or grow the dig brush for this session. A toast shows the new size. |
| Shift+G | Plant a tree if you have 3 wood, otherwise a fern. |
| Ctrl+G | Plant a wildflower. |
| Ctrl held while the channel key fires, without Shift | Redirect a channel. The default channel key is Shift+T, so this needs a different bind. |
| Channel key with neither Shift nor Ctrl | Dig a channel. The default Shift+T bind does not do this. |

Click a skill button in the tree with the mouse. Click a craft button in the bag to make a structure piece. Left-drag stacks between the bag and the hotbar to swap or combine them. A short click on a bag stack files it into the hotbar.

## Menus

### Main menu

Title "CRYSTAL STORM", subtitle "Maze. Dig. Survive."

- **Continue** — load the alive-quit snapshot. Greyed out when that file is missing, invalid, or from a dead run.
- **Play** — world list.
- **Settings** — the settings tabs, then **Back** to this menu.
- **How to play** — a stepped overlay. **Next**, **Back**, **Skip**, **Close**, and a **Controls** button. Finishing or skipping remembers that you saw it, so it will not pop up by itself next time. The button always opens it anyway. Its last card still describes the old win. Ignore that card.
- **Controls** — a list of the current bindings for the rebindable actions.
- **Quit** — leave the game.

A font credit sits under the buttons.

### World list

Title "Worlds". Each row shows the name, seed, last played time (or "Never"), and whether the world bake is ready. Empty list says "No worlds yet."

- Click a row to select it.
- **Play** — enter that world. If it has a world save, that save is loaded after the terrain is ready.
- **New World** — name and seed screen.
- **Rename** — uses the text box ("Rename selected world").
- **Delete** — asks `Delete "<name>"? This cannot be undone.` **Cancel** or **Delete**.
- **Back** — main menu.

### New world

**World name**, **Seed**, **Randomize**, **Create**, **Back**. A bad name or a failed write shows a status line. A seed that is not a whole number is treated as 12349.

### Pause menu

Title "Paused". Opened with Escape.

- **Resume** — close the menu and unpause.
- **Settings** — the same settings tabs, inside the pause panel.
- **How to play** and **Controls** — the same overlays as the main menu.
- **Return to World Select** — saves first (see Saving), then the world list.
- **Quit** — saves first, then exits.

Opening pause closes the skill tree. Closing pause closes How to play.

### Loading screen

Shown while the start area streams in. Title, "Maze. Dig. Survive.", a phase line, a percent, and the line "Controls locked until nearby terrain is ready." On a failed start: "Could not start", the reason, **Retry**, and **Rebuild World**.

### Inventory

Opened with I. Title "Inventory". Craft buttons for the five structures, an armor button, the bag grid, and the hotbar (the hotbar is also on screen while the bag is closed). Drag with the left mouse button. Opening the bag pulls the hotbar in front of the dimmed background so you can drop onto it.

### Skill tree

Opened with K. Title "Skills". Three columns: Fighter, Miner, Builder. The point count is on the panel. Click a locked skill to spend a point. Click an active skill to put it in the first empty slot (C, H, or J) or, if it is already slotted, to clear that slot.

What the buttons call the skills:

- Dash — a short slide. You do not take damage during a brief window after it starts.
- Crystal Pulse — hurts crystal enemies nearby and slows crystal flow on that patch for a few seconds.
- Tough — more maximum health.
- Ground Slam — breaks the 3 by 3 surface under you and hurts enemies standing there.
- Quick Mine — faster digging.
- Quick Wall — places a wall segment one column in front of you, at half the usual material cost.
- Sturdy — structures you place afterward have more health per block.

Passives apply as soon as you unlock them. Actives do nothing until they sit in a slot. You can equip three actives. The tree pauses the game. It will not open on top of pause, the dev chat, the full map, or the loading screen.

### Full map and minimap

The minimap is always on the HUD unless a quality option has turned maps off. M opens a larger map over the HUD and blocks actions until you press M again or open pause, chat, or the loading screen.

### Relic choice

When the game offers relics, a panel titled "Choose a relic" (or a replacement title) covers the HUD. Pick one of the buttons. The game slows while it is up. This is not on the main menu. It appears only when a relic offer actually happens.

### Run summary

After a win or a death. **World Select** and **New Run**.

### Dev chat and debug

T opens a panel at the bottom of the screen with a history and a text line. It is a developer tool. F3 is the debug overlay. F11 writes a report. You do not need these to play.

### Settings

Opened from the main menu or from pause. Five tabs, then **Close** (or **Back** on the main-menu copy). Changes save as you move them. The status line says "Saved." if the file wrote.

#### Graphics

| What you see | What it stores | Default |
| --- | --- | --- |
| Quality preset: Low, Medium, High, Safe | `quality_preset` | Medium |
| Render distance (slider 1 to 8) | `render_distance` | 2 |
| Vegetation density (slider 0 to 1) | `vegetation_scatter_multiplier` | 1 |
| Combat visuals | `combat_visuals_enabled` | on |
| Camera cutaway | `camera_cutaway_enabled` | on |
| Texture blueprint (F6) | `texture_blueprint` | off |
| Texture set: Original or Batch 1 | `texture_set` | Original |
| Export texture manifest | no stored switch | writes a manifest of texture slots |

Picking a preset also moves the render-distance and vegetation sliders to that preset's numbers. You can still drag them afterward. Camera cutaway hides terrain that sits between the camera and you. Texture blueprint swaps in placeholder textures until you turn it off. Batch 1 uses the alternate art set where those files exist.

#### Audio

| What you see | What it stores | Default |
| --- | --- | --- |
| Master volume | `volume_master` | 1 (full) |
| Music volume | `volume_music` | 1 |
| SFX volume | `volume_sfx` | 1 |
| UI volume | `volume_ui` | 1 |

Each slider runs from 0 to 1 in steps of 0.05.

#### Display

| What you see | What it stores | Default |
| --- | --- | --- |
| Fullscreen | `fullscreen` | off (windowed) |
| VSync | `vsync` | on |
| Resolution (windowed) | `resolution` | 1280x720 |
| UI scale | `ui_scale` | 1 (shown as 100%) |

Resolutions in the list: 1280x720, 1366x768, 1600x900, 1920x1080, 2560x1440. The resolution box is locked while fullscreen is on. UI scale runs from 75% to 150% in steps of 5%.

#### Accessibility

| What you see | What it stores | Default |
| --- | --- | --- |
| Reduce motion | `reduce_motion` | off |
| Screen shake | `screen_shake_enabled` | on |
| Hit stop | `hit_stop_enabled` | on |
| Hit flash | `flash_effects_enabled` | on |
| Hit markers | `hit_markers_enabled` | on |
| Block cracks | `crack_overlay_enabled` | on |
| Colour-blind crystal palette | `colorblind_palette` | off |

Reduce motion forces screen shake and hit stop off and greys those two boxes out. The colour-blind palette recolors the crystal, the HUD, and creatures that use that palette.

#### Controls

Click a binding, then press a key or a mouse button. Escape cancels. If that key is already used, the line names the other action and the bind does not change. **Reset bindings** restores the defaults in the tables above. **How to play** and **Controls** open the same overlays as the main menu.

These actions can be rebound: move forward, move back, move left, move right, jump, sprint, rotate left, rotate right, look up, look down, unstuck, attack / use, place / alt use, interact, inventory, plant, channel water, cycle place, hotbar 1 through 8, map, quick save, quick load, pause, dev chat, debug overlay, bug report, texture blueprint.

These input-map actions are not on that list: `skill_1`, `skill_2`, `skill_3`, `skill_tree`, `ui_accept`.

The saved camera tilt is `camera_pitch_degrees`. It is not a slider. It updates when you use Page Up, Page Down, or the middle mouse. The default tilt is the isometric angle (about -35.3 degrees).

`tutorial_completed` is not a checkbox. It becomes true when you finish or skip How to play, and that is what stops the overlay from opening itself.

`keybinds` is the dictionary of any bindings you changed. Empty means "use the defaults."

Settings are stored in `user://player_settings.json` (Godot's user data folder for this game, not a file next to the guide).

## Saving and loading

Three different saves exist. They are not the same button.

### Continue (alive quit)

When you are alive and you quit, or you return to the world list, or you close the window, the game writes `user://saves/continue.json` and also the world file below. Continue on the main menu loads that continue file after you have spawned, and it does not also apply the world file on top.

If you are dead, that quit **deletes** the continue file (and still writes the world file if a world is open). The Continue button then stays off. A continue file is also ignored if your saved health is zero or the run is already over.

### World file

Each catalog world has `user://saves/world_<id>.json`. **Play** on the world list loads it when the file exists.

The game also writes that world file on its own about every 5 minutes, when a new enemy type unlocks, and when a town becomes besieged. Those autosaves do not refresh the Continue file. Closing the window and using pause → Quit or Return to World Select do refresh Continue, if you are alive.

What a save keeps includes the terrain you changed, what you placed, your hotbar, bag, and armor, where you are, your health, wildlife, crystal enemies, and the one crystal (its health, and whether the boss has already appeared so it does not appear twice).

### Quick save

F5 writes `user://saves/slot_0.json`. F9 loads that same slot. The game allows three slot numbers, but only slot 0 has keys. There is no slot picker on the menu. Quick load does not use the Continue file.

Pause and the window close do not press F5 for you. They use the Continue and world files instead.

### What a dead run means for the next launch

You can still open the world from **Play** and get the world file from the last autosave or from the dead quit. You cannot press **Continue** for that dead session.
