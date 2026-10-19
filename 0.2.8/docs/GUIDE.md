# Crystal Storm — player guide (part 1)

**Version 0.4.1.** This is for someone opening the game for the first time. Part 1 covers what the game is, how you win and lose, how to start, every control, every menu, every setting, and how saving works. Part 2 covers digging and building, the crystal, corruption, combat and skills, every boss, unlocks and level-ups, and a short first route.

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

## Dig and build

Aim with the mouse. The highlighted cell is the only cell a dig or a place will use. If it is out of reach, a toast names the reason and nothing happens in front of your feet.

### What breaks ground

Only a dig tool breaks terrain. The stone pick is the only dig tool in the item list. Swords, the spear, the shortbow, the sling, and the crystal hammer do not dig. Herbs, bombs, and armor do not dig either. The hammer is a slow melee weapon with a small splash; it is not a multi-block dig.

Hold the left mouse button (or F) with the pick selected. The pick's swing is short. Each broken cell costs 1 durability. The pick starts with 48. Extra cells in one swing also stretch the delay before the next dig: the delay is multiplied by `1 + 0.35` for each cell after the first. One cell keeps the old delay.

A swing drops at most 4 items, even if more cells broke.

`[` and `]` still toast "Dig brush" and a number from 1 to 3 while the pick is out. That number is a leftover brush size. With multi-block breaking on, the stroke uses the tool's break shape, not that brush. The stone pick is tier 0 and its shape is a single cell, so the brackets do not make the pick dig a wider hole.

The shape table, if a tool's tier steps up, widens in this order:

| Step | Shape | What it breaks |
| --- | --- | --- |
| 0 | single | The aimed surface cell. This is the stone pick. |
| 1 | 1×2 vertical | That cell and the cell above it on the aimed face. |
| 2 | line of 3 | Three cells across the aimed face. |
| 3 | 3×3 face | A 3×3 on the aimed face. |

No item in the catalog has a tier above 0. The 3×3 you can actually perform is the Ground Slam skill, which breaks the surface under your feet. It is not the pick.

The aimed cell stays the orange box. Any extra cells in a wider shape use the smaller preview marks. A preview only keeps cells the stroke can dig: a surface voxel, inside the border, not water, not a protected town or ruin, and not below the dig floor.

Shift or Ctrl while the dig fires edits a water channel instead of breaking the block. The dedicated channel key is covered in part 1.

Digging next to a river or a pool lets water creep into open cells at that waterline or lower. Solid ground at the line stays dry. A dug column whose top is still above the line stays dry.

### What you place

Right mouse (or R) places. Tab cycles the place list. The HUD names the current one.

One-block places, in Tab order:

| Place | What you get |
| --- | --- |
| Fill | Raises the dug column back up. |
| Ramp | A one-column slope. |
| Corner ramp | A corner slope. It needs real support, including the diagonal plateau. |
| Wall | A stone wall. It blocks movement and does not raise the height of the ground. One stone, or two wood if you are out of stone. Crystal crawls through it slowly. |
| Gate | A passage. You walk through. Crystal is slowed, not stopped. One wood. |
| Bridge | A span over a dig or low ground. One wood. Crystal still feels the drop underneath. |

Larger pieces are crafted in the bag (I), or selected with X after Z has armed the blueprint ghost. Z turns the ghost 90 degrees. X cycles Wall Segment, Wall Corner, Gate, Stairs, Small Tower. The ghost is green on open supported ground and red when the cell is blocked or unsupported. Right-click places every cell of that piece in one edit. Placing a crafted piece spends the piece, not the stone again. A failed place does not spend it.

| Piece | Size | Solid cells | Craft cost |
| --- | --- | --- | --- |
| Wall Segment | 3 wide, 2 high, 1 deep | 6 | 6 stone, or 12 wood |
| Wall Corner | 2×2×2 with the inner column empty | 6 | 6 stone, or 12 wood |
| Gate | 3 wide, 2 high, posts and an opening | 4 stone posts plus the gate mesh | 4 stone and 1 wood, or 8 wood if you cannot pay the stone recipe |
| Stairs | Rises 1, then 2, then 3 | 6 | 6 stone, or 12 wood |
| Small Tower | 2×2 footprint, 3 high | 12 | 12 stone, or 24 wood |

You start with 16 stone. One wall segment is 6 of that. The 12-stone tower does not fit in the same bag after that craft unless you mine more.

Each placed blueprint is one health pool: 8 HP per solid cell (a wall segment is 48). An enemy swing on that column, or on a side neighbor, chips the pool by that enemy's hit. While crystal still covers one cell of the piece, crystal flow chips 2 HP once per tick. Aim at a damaged piece and place: one stone restores 8 HP. At 0 HP the whole piece comes out in one edit, including a gate opening.

Quick Wall (a skill, below) places a wall segment one column in front of you, turned across the way you face, at half the stone cost (3 stone for the usual 6), and it does not wait on the build delay. It does not spend a crafted piece.

You can also plant with G. That is not a structure. Part 1 lists the plant keys.

## The crystal

There is one crystal. It is a pool that spreads from a single heart, not a set of lesser hearts. The heart has 500 health. The HUD reads `Crystal` and the current health out of 500, plus a strength tier.

Where it sits depends on the world seed. The heart is placed in one corner of the playable map, inset from the border. The default seed 12349 puts that corner at column 952, -952. The objective is still "Destroy the crystal." Hit the heart's own column, not merely a purple neighbor. A sword reaches it from about 2.8 columns. The hammer has to be closer (about 2.2) and hits the heart harder, but slower. Chipping the film around the heart is not the same as damaging the heart.

The pool creeps into empty neighbors and stays one connected body. It prefers to fill notches and low ground before it hops. Digging a trench gives it a lower path. A toast will say the purple front follows lower ground. Walls slow it. Gates slow it and still let you through. Bridges span a cut; the crystal still feels the drop. Wet ground and channels cut conductivity sharply, so a water cut is a slow crawl, not a wall. Plains and steppe let it spread faster than forest. Marsh is slower. Highland and mountain are the slowest.

As the pool covers plants, animals, ruins, and farmland it gains power. Power steps the strength tier at 0, then 20, 60, 140, 300, and 600. The HUD shows that tier as `T` plus a number. Higher tier is what lets stronger unlocked enemies join the spawn rolls. The tier does not, by itself, end the run.

Standing in crystal at least 0.25 deep, while the fight is close, burns you. Before the first tick of that burn, the ground under you lights up: cracked magma tiles and small flames, for 0.60 seconds. You can still move. Then the burn applies. Deeper crystal hurts more (28 damage per second times the depth, reduced by crystal resistance). That burn can kill you. The kill is still a death.

If the pool covers more than 72% of the map, a toast says "Crystal coverage is past the cap." The HUD can say "over cap." You keep playing.

The first time the heart's health is at or under 125 (a quarter of 500), the Origin Warden appears. See Bosses. The heart can still be hit while the warden is alive. Only breaking the heart wins.

## Corruption

Where the crystal absorbs a cell, the ground is overwritten with crystal, crystal vein, or shard-studded ground. Plants change with it: a tree becomes a shard tree, a bush or fern becomes a crystal bush, and other plants become crystal grass. A short pulse plays on that cell.

These cells are not overwritten: anything you built, a ruin, and a town.

An animal that stands in the crystal tints toward purple over 3.5 seconds. Leaving the pool bleeds that timer back down. If the timer fills, the animal becomes a crystal hostile:

| Animal | Becomes |
| --- | --- |
| Rabbit | Crystal Mite |
| Deer | Crystal Stag |
| Boar | Corrupted Beast |
| Bird | Crystal Wisp |

Breaking the crystal film on a cell clears that depth and leaves a scar. The scar heals back toward the old ground and the old plant over 18 seconds. Regrowth starts from stage zero. Towns, ruins, and your buildings do not take this scar.

## Combat and skills

Weapons swing on a wind-up so the hit is readable. You can move during an enemy's warning. Two different actions will not resolve within a short shared gap.

| Weapon | Hit | Reach | Time between swings | Notes |
| --- | --- | --- | --- | --- |
| Wooden Sword | 12 | 2.8 columns | 0.45 s | The practical heart weapon. Does not dig. |
| Spear | 15 | 3 columns | 0.78 s | Thrust. Pierces two targets. In the bag at the start. |
| Crystal Hammer | 7 to a creature, about 4.8 to crystal mass | 2.2 columns | 1.1 s | The slam lands at 0.62 of that swing. Splash on a 3×3 of cells. Heavy shove. Does not dig. |
| Shortbow | 10 | 14 | 0.8 s | Arrow drops. Aim the ground cell under the cursor. |
| Sling | 8 | 11 | 0.5 s | Lobs one stone from your stone stack in a high arc. Does not dig. |
| Stone Pick | 5 to a creature if the swing also connects | 3 | 0.1 s between digs | Dig first. A connected melee hit is weaker than the sword. |

A herb restores 28 health. Select it and right-click (hotbar 6, then the right mouse button). Bombs are a right-click use. Armor is worn from the bag.

Crystal creatures and wildlife shove you away from the hit. A boss hit, or a hit of 16 or more, shoves farther. You cannot walk until the shove ends. I-frames and the crystal burn do not apply that shove. The burn ignores i-frames.

Ordinary bites that use a warning (a mite, and the warden's bite) paint a pulsing disc on the ground at your feet before the damage. A mite's disc is yellow and about 1.25 columns across, and it waits 0.45 seconds. The warden's bite disc is red and about 1.55 columns across, and it waits 0.85 seconds. Step off the disc. Other creatures hit when they are in contact; they do not all draw that disc.

### Skills

Press K. The game pauses. Fighter, Miner, and Builder are the three columns. One level-up is one skill point. Each skill costs one point. Passives turn on when you buy them. An active goes into the first empty slot (C, then H, then J) when you buy it or when you click it again. Three actives is the cap. Click a slotted active to clear the slot.

Each active waits out its own wind-up, then the hit, then a short linger, then recovery. The numbers below are the effect. The wind-up lives in the game-feel timing, not in a second config.

| Skill | Id | Kind | What it does |
| --- | --- | --- | --- |
| Dash | `dash` | Fighter active | Slides 4 columns along your move, or along your facing if you are standing still. You ignore damage for 0.18 seconds. Cooldown 3 seconds. |
| Crystal Pulse | `crystal_pulse` | Fighter active | 16 damage to crystal enemies inside 4 columns, and crystal flow on that disc drops to 0.4 for 4 seconds. Cooldown 6 seconds. |
| Tough | `fighter_passive` | Fighter passive | +20 maximum health. |
| Ground Slam | `ground_slam` | Miner active | Breaks the 3×3 surface under you and deals 18 to crystal enemies and creatures standing on that patch. Cooldown 1 second. |
| Quick Mine | `miner_passive` | Miner passive | +0.25 dig speed. |
| Quick Wall | `quick_wall` | Builder active | Wall segment one column ahead, at half material cost. Cooldown 1 second. A failed place clears that cooldown. |
| Sturdy | `builder_passive` | Builder passive | Structures you place after the unlock gain +4 HP per cell. |

On the tree, the rows in each column are alphabetical: Fighter is Crystal Pulse, then Dash, then Tough. Miner is Ground Slam, then Quick Mine. Builder is Sturdy, then Quick Wall. Arrow keys move the highlight. Enter spends the point.

## Bosses

Three bosses exist in the data. Only two of them show up while the one-crystal rule is on, which it is.

### Origin Warden

This is the boss of a normal run. Display name Origin Warden. Id `origin_warden`.

**Where.** The first time the heart is at or under 25% health (125 of 500), one warden spawns two columns off the heart. The game tries east, then west, then south, then north, and keeps the first cell that accepts it. It does not spawn a second one. A save remembers that it already appeared. It has 240 health, hits for 18, and moves more slowly than a mite. It is visibly larger than the other crystal creatures. Its health bar sits at the top of the screen once you are within 22 columns or you have already hurt it. In this version the bar is labeled "Boss warning" plus the current and max health.

**What the warnings look like.**

- When it appears, a banner says `Boss warning — a warden guards the crystal`. The objective line gains `boss warning`. The banner holds for 3 seconds. The view eases slower for a moment. You can still move.
- Before a slam, a charge, or a burst, a pulsing ring is painted on the ground and a telegraph sound plays. You have 0.85 seconds. Slam and charge rings are red. A burst ring is wider and more orange. Slam reaches about 2.4 columns, charge about 1.8, burst about 4.6. The charge ring is centered where you were when the wind-up started; on impact the warden lunges toward that point and the hit is measured from its new spot. Burst and slam are measured from the ring.
- Its ordinary bite, if you are in arm's reach between those specials, uses the red disc described under Combat. Same 0.85 seconds.
- At half health (120), phase 2 starts. You hear the phase change. It calls three Crystal Mites and immediately starts a burst. After that it alternates a burst with either a slam (if you are within 4 columns) or a charge. Between impacts in phase 2 the pause is short (about a third of a second). In phase 1 the pause is longer (about 0.85 seconds), and it only slams or charges: slam when you are close, charge when you are not.

**How to beat it.** Put the cursor on the warden and hit it with the sword. Dash out of a ring. Ground Slam hurts it if the 3×3 catches the column it is standing on. Crystal Pulse hurts it if it is inside 4 columns. Kill it before you empty the heart if you want the relic offer and a clean read of the fight. Killing it does not win. The heart is still the win. When it dies, a panel says `Origin Warden fell — choose a relic`.

### Shard Tyrant

Display name Shard Tyrant. Id `spawn_elite`. It uses the same boss brain, flagged as an elite.

**Where.** After a 28-second grace at the start of the run, the spawner tries once a second to station one guardian on each crystal spawn that is not marked as a boss heart. The live crystal is not marked that way, so the tyrant is placed on the crystal's own column. If 24 crystal creatures are already alive, it waits. It has 96 health and hits for 16. It is larger than a Shard Guard and tinted orange. It patrols a short radius around that column.

**What the warnings look like.** The same red ground ring as the warden's slam and charge, for 0.85 seconds. It never enters phase 2, so it does not burst and it does not summon mites from a phase change. Close (within 4 columns) it slams. Farther, it charges. After each impact it waits about 0.85 seconds.

**How to beat it.** Same as any heavy melee target: sword on the cursor, step out of the ring, slam or pulse if they will reach it. Killing it does not win. A panel says `Shard Tyrant fell — choose a relic`. It can be absent if the guardian never got a free slot; do not wait on it to finish the heart.

### Origin Heart

Display name Origin Heart. Id `origin_boss`. This is the only crystal spawn flagged as a boss in the spawn table. Health 500. It is the old sealed heart: it could not be broken until every non-boss spawn was gone and the warden was dead, and killing that warden was itself a win.

That spawn is not placed while the one-crystal rule is on. You will not find an Origin Heart in a normal world. The thing you destroy is the released crystal, display name Crystal, which is not a boss. The in-game How to play card still describes the Origin Heart win. Ignore that card. Part 1 has the real goal.

Ruin Shard (`ruin_miniboss`, 120 health) and Artifact Node (`artifact_node`, 80 health) are the old lesser spawns. They are not bosses, and they are not placed in a normal world either.

## Unlocks and level-ups

You start at level 1 with no skill points. Experience toward the next level is `round(50 × level ^ 1.5)`: 50 to reach level 2, then 141 to reach level 3 (191 total), and so on. Each level gives one skill point, plus 4 maximum health, 0.04 melee damage, 0.04 ranged damage, and 0.04 dig speed for every level after the first. A banner plays on the level-up. There is no meta-progression file. A new run starts this over. The save of the current run keeps the level, the XP, and the skills.

What pays XP:

| Act | XP |
| --- | --- |
| A block mined | 1 |
| A hit that damages the heart or crystal mass | 4, plus 10 if that swing also broke the film on the cell |
| A structure placed | 12 |
| A ruin or treasure the world itself notices | 25 |
| A point of interest the world itself notices | 20 |

Kill XP is 8, plus 6 for each tier. Militia and villagers pay nothing.

| Kill | Tier | XP |
| --- | --- | --- |
| Rabbit, deer, boar, bird, Crystal Mite, Thornling | 0 | 8 |
| Crystal Stag, Corrupted Beast, Farm Bomber, Crystal Wisp | 1 | 14 |
| Shard Guard | 2 | 20 |
| Shard Tyrant | 3 | 26 |
| Origin Warden | 4 | 32 |

The crystal also unlocks enemy types by what it absorbs. A toast says `Enemy unlocked:` and the id. Crystal Mite is already unlocked when the run starts. Grass absorption does not unlock it. The mite row is still in the table so the threshold is visible; the flag on that row is "unlocked at the start."

| What the crystal absorbs | How many | Unlocks | Also |
| --- | --- | --- | --- |
| Grass | 10 | `crystal_mite` (already unlocked) | No bonus power |
| Farmland | 2 | `farm_bomber` Farm Bomber | +6 power, a short spawn burst |
| Trees | 4 | `crystal_stag` Crystal Stag | +4 power |
| Bushes | 6 | `thornling` Thornling | +2 power |
| Animals | 3 | `corrupted_beast` Corrupted Beast | +3 power |
| Ruins | 1 | `shard_guard` Shard Guard | +12 power, a short spawn burst |

Three of those unlocks also offer a relic. The mite's relic is not offered, because the mite is already unlocked at the start. If your relic slots are full, the panel says `Relic unlocked — replace one`.

| Unlock | Relic |
| --- | --- |
| `thornling` | Flow Anchor. Walls resist crystal spread more. Crystal flow is 0.88. |
| `farm_bomber` | Crystal Ward. Nearby growth and flow slow. Crystal flow is 0.72. +0.12 crystal resistance. |
| `crystal_mite` | Mason's Glove is the mapped relic (dig faster, build at 0.8 cost) but it is not granted for the starting unlock. |

Crystal Stag, Corrupted Beast, and Shard Guard unlock the creature only. They do not grant a relic.

The other relics you can be offered from a ruin or a boss kill are Pathfinder's Charm (move faster) and Ruin Seal (crystal contact burns less), plus Flow Anchor and Mason's Glove in the ordinary offer list. Boss kills open the choice panel with their own title, as above. That offer is a pick, not a new row in the absorption table.

Buying a skill is the other unlock. The seven skills are the whole catalog. See the table under Combat and skills. A banner plays when a skill unlocks.

## A first route

This follows the showcase route: one fresh world, your own inputs, no skipped travel. Do not reload to hunt a seed. The default seed is fine. The heart on that seed is the corner at 952, -952. Walk there. Do not teleport.

1. Wait until the loading screen is gone. If How to play is up, press Escape twice. It closes. Then you can move.
2. Sprint toward the heart for at least a short stretch and hop once on flat ground. If you are already in deep water, hold Space to rise to the surface, then walk out. Do not dig a pool just to swim.
3. The sun, shadows, and fog are already the medium look. You do not change them. There is no sleep and no day-night clock to use.
4. Select the stone pick (2). Break about eleven open blocks beside the route, one cell at a time. Stop if a column refuses (border, town, water, dig floor) and make the count up on the next open cell. Do not cut a tunnel.
5. Open the bag (I) and craft a Wall Segment (6 stone). Close the bag. It lands in the first empty hotbar slot. Select it, aim at open ground in reach, and place it. The ghost is green there.
6. On the way, if a camp, an abandoned dig, a crystal grove, or a shrine is close, stand on it so you can see it. If a treasure ruin is close, stand within about 10 columns and wait. The world notices it; you do not open it by hand. A landmark (a rock spire, a ruined tower, or a crystal glow) is worth a stop about 12 columns out, then a yaw so it is in frame. Skip anything that would be a trek across the far side of the map.
7. Fight before you commit to the heart. Kill a Crystal Mite with the sword, and fire the shortbow once. Rabbits, deer, boar, and birds that are already in range are fine. Do not hunt militia or villagers. If a Farm Bomber, Crystal Stag, Thornling, Corrupted Beast, Crystal Wisp, Shard Guard, or Shard Tyrant is there, fight it. If it never shows, move on.
8. Reach level 3 (191 XP earned) from digs, the wall, ruins, and kills before you start chopping the heart down. Open the tree as soon as you have one point, move down to Dash, and take it. Hold forward and press C. That slide is 4 columns.
9. The second point is Ground Slam. If the heart is still above 125, you can keep earning on the way. If you have already pushed the heart to 125, stop hitting the heart. Chip crystal film that is at least a few columns off the heart, kill mites that are already there, and dig a few more open cells. Then buy Ground Slam and use it on open ground, not in a town. That 3×3 is the multi-block break on this route. The pick stays a single cell.
10. Later points, once you have them: Crystal Pulse on dry ground near the pool, Quick Wall on that same ground, and Quick Mine. You can only hold three actives. Unequip one if the slots are full before Quick Wall.
11. Sword the heart's own column. Watch Crystal HP. Deal with the Origin Warden when the warning banner appears (see Bosses). Step out of its rings. Kill the warden, then go back to the heart.
12. Break the heart to 0. Stop swinging. The win title is the crystal destroyed. Read the summary. Do not press restart if you still want the screen up.

Dying fails the run. Pull back and use a herb (6, then right mouse) when your health is low. Coverage and a fallen town do not fail it.
