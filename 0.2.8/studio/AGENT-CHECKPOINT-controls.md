# Controls checkpoint (cs-sonnet/controls)

Env: Godot 4.7.2 headless on a Linux VM, scratch copy with stand-in art; screenshots and visuals cannot be judged (Dell). `cs-verify.sh` runs through a patched copy.

Start: branch off cs-sonnet/water, `water-test-fixes.patch` applied with git am (`fea21d1`).

## cs-ctl-01
- project.godot: attack is mouse-left only (F removed); skill_1..3 are Shift+1/2/3; added hotbar_9 (9), hotbar_10 (0), rotate_piece (Z), rotate_piece_back (Shift+Z), place_variant (X), hotbar_next/prev (wheel down/up, period/comma), camera_zoom_in/out (Ctrl+wheel, = and -), camera_reset (Home), camera_free_look (MMB).
- `InputBindings.ACTIONS`/`LABELS` hold every gameplay action (the tutorial Controls page already lists the table). Mouse binds now carry and compare Ctrl/Alt/Shift and persist them.
- weapon_controller: Z/X/bracket polls and Shift/Ctrl build and plant modifiers replaced by `rotate_piece`, `rotate_piece_back`, `place_variant` (cycles wall/gate/bridge and plant variants) and `brush_shrink`/`brush_grow`; hotbar number keys use exact matching so Shift+number is never a slot. camera: wheel zoom now only through `camera_zoom_in/out` (plain wheel no longer zooms).
- New `scripts/verify_input_map.gd` (table, labels, no shared key+modifiers, hotbar without Shift, attack mouse-only, no hard-coded keys in weapons/ and player/). `verify_skills` updated to Shift+1/2/3. PASS.
- Scenario: none for this job; the ctl-02..08 scenarios exercise the new actions. Kept the existing action names brush_shrink/brush_grow for the plan's brush_smaller/bigger.
- Left: nothing for ctl-01.

## cs-ctl-02 camera (done)
- `player/camera.gd`: Q/E tap (<= `camera_tap_sec`) snaps yaw 90 degrees, hold rotates smoothly; MMB (`camera_free_look`) or Alt plus pointer motion adjusts yaw and pitch (`camera_look_deg`) and sets `GameplayInput.free_look`; zoom in/out and `camera_reset` (Home) go through `InputBindings.matches`.
- `scripts/verify_camera_controls.gd` (tap E, Alt look, =, Home) passes; `verify_camera_default_zoom.gd` now uses Ctrl+wheel and passes.
- Scenario `camera` is registered (`honest_build._camera`, `HonestInput.motion/wheel`, cs-verify.sh) but cannot run in this cloud stub (full scene needs real shaders/art); needs the Dell.
- Cursor aim is not yet suspended by `free_look`; wired in cs-ctl-08.

## cs-ctl-03 hotbar (done)
- `Inventory.HOTBAR_SIZE` is 10 (bag and panel grid follow the constant; slot 10 labelled 0). `WeaponController.select_hotbar` is the one selection path for number keys, `hotbar_next/prev` (plain wheel, period/comma, wrap) and polls with exact match so Shift+number and Ctrl+wheel never change the slot.
- `ui/hotbar.gd`: selected-slot highlight (existing border) plus a fading item-name label (`HotbarItemName`).
- `scripts/verify_hotbar_controls.gd` passes (3, 0, wheel wrap both ways, period/comma, Shift+2 ignored, plain wheel no zoom, Ctrl+wheel zooms). `verify_inventory_drag` still passes.
- Scenario `hotbar` registered (cannot run in the cloud stub; needs the Dell).

## cs-ctl-04 skills (done)
- `skill_service._hotkey_down_now` matches exactly, so Shift+1/2/3 fire skills and never hotbar slots; sprint (Shift alone) and unstuck (V) untouched.
- New `ui/skill_bar.gd` (node `SkillBar` in `scenes/main.tscn`, above the hotbar): skill name, key from `InputBindings.binding_text`, cooldown number, sweep, dimmed when empty or cooling down.
- `scripts/verify_skill_bar.gd` passes (Shift+1 fires dash, hotbar index unchanged, cooldown label set then cleared, key text "Shift+1", plain 1 selects slot 1 and fires nothing). `verify_skills` passes.
- No separate honest-bot scenario; the Shift+1 step is part of the controls tour (cs-ctl-07).
