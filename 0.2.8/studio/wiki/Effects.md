# Effects

Juice is presentation only. It does not change damage, terrain, or the combat rules in `Combat.md`.

## Particles

`systems/vfx_pool.gd` (`VfxPool`) keeps a fixed list of `CPUParticles3D` one-shots. Idle, the node does not run `_process`. A burst reuses a finished emitter or grows until the preset cap, then drops. Materials are unshaded, transparent, and `cast_shadow` is off. One shared box chip is the mesh. Each kind keeps one shared material whose albedo stays white (alpha about 0.9); the burst tint is the particle color.

| Preset | Emitters | Particles each | Corruption gap | Cull columns | Swing meshes |
| --- | --- | --- | --- | --- | --- |
| LOW | 4 | 6 | 0.50 s | 18 | 1 |
| MEDIUM | 10 | 12 | 0.22 s | 40 | 3 |
| HIGH | 16 | 20 | 0.12 s | 64 | 4 |
| SAFE | 2 | 4 | 0.70 s | 12 | 1 |

Cull distance is `cull columns * voxel_scale` from the player. Corruption uses one shared emitter and a cooldown, so a wave of absorbed tiles does not spawn an emitter per cell.

`CombatVisualFeedback` owns the pool and calls it from:

- crystal cell damage and breaks (`crystal_mass_hit`) — shatter, still played when combat labels are off
- dig place-flash (`build_id` `dig`) — dust
- player feet changing wet/dry, and arrow/stone/bomb impacts on water — splash
- spawn heart destroyed — large burst
- `CrystalManager` after `corrupt_absorbed_cell` returns true — corruption pulse
- crystal bomb detonation — shatter plus dust, plus the heavy hit-stop and shake

Legacy break shards and floating labels still follow `combat_visuals_enabled`. The pooled bursts do not.

## Swings, bob, flash, shake

Melee and the pick ask the pool for a swing mesh. Spear is a thin thrust box. Hammer is a flat torus. Sword and pick are short ribbon arcs. At most one style is visible per slot, and LOW keeps a single slot.

`Juice` (`systems/juice.gd`):

- Walk bob and landing squash scale the visual node. The player bob runs only while `RUNNING` and `Juice.walk_bob_allowed()`. Creatures bob only inside `bob_columns` (LOW 8, MEDIUM 22, HIGH 36, SAFE 0), only if the camera can see them, and only when `creature_bob_allowed` is true. The physics body is not scaled.
- Hit-stop dips `Engine.time_scale` to 0.02 for 40–80 ms and restores the previous scale with a real-time timer. Gameplay calls do nothing when `DisplayServer.get_name() == "headless"` (Godot 4.7 `--headless` leaves `OS.has_feature("headless")` false), when the setting is off, when Reduce motion is on, or when time scale is already away from 1 (the relic modal uses 0.05). `verify_juice` passes `force` to run the dip. Reduce motion still refuses that `force` call. A relic offer calls `Juice.cancel_hit_stop()` first and saves that pre-dip scale, so a killing blow cannot leave the run at 0.02.
- Screen shake is a decaying offset added by `player/camera.gd` after it writes `global_position`. Boss impacts and bombs use a larger amount. Gameplay shake uses the same headless check as hit-stop, and Reduce motion returns a zero offset.
- Reduce motion (`PlayerSettings.reduce_motion`) also skips the large shatter and spawn-death bursts in `VfxPool`. Dust, splash, and corruption still emit. Hit flash stays on `flash_effects_enabled`. The settings screen is in `studio/wiki/UI.md`.
- Hit flash sets `flash_amount` on one shared `shaders/entity_hit_flash.gdshader` overlay and clears that overlay when the amount returns to zero. No material is allocated per hit.

Death moves the visual onto `CombatVisualFeedback` (cap 6) for a 0.4 s shrink and fade, then frees it. The body `queue_free`s immediately so death signals and spawn-cell cleanup stay on the old frame.

## Held item, aim, hits, cracks

`ItemAnim` reads `anim_kind`, `anim_duration`, and `impact_ratio` from the item definition. Missing values derive a swing (melee and the pick), a thrust, a raise (eat, place, throw), or an aim pose (bow and sling). Armor has no pose. `HeldItemView` is two reused meshes parented to the player. The icon is about one body tall and sits outside the torso so it reads at the default iso zoom. A use moves that icon: a side sweep, a forward lunge, a lift, or a bow draw. The crystal hammer still raises for most of its wind-up and slams on the impact sample. That sample stays 0.62 of the 1.1 s swing. The body has no rig.

`WeaponController._try_attack` arms that clock for melee and ranged weapons and releases the existing strike on the impact sample. The cooldown still starts when the button is pressed, so the cadence is unchanged. Dig, place, eat, and bombs still resolve immediately, then the same pose plays from the ready frame. A repeat does not restart it until that pose finishes. A direct call to `_do_melee_attack` or `_do_ranged_attack` still applies damage inside that call.

`AimIndicator` draws a ground reticle for melee and a line plus an end marker for a shot. Tools emit `tool_aim_changed(cell, world_pos, active)` for `TargetHighlight` and do not draw a second block box. A block or melee mark stays inside `ActionTargeting.INTERACTION_RANGE`. A bow or sling marker uses the shot's authored range. The ray is the camera basis, so pitch moves the mark.

`HitMarkers` keeps six world rings. A hit, a miss, and a blocked swing use different colours. `show_hit_marker` reuses one slot and still uses the radius it was given. `hit_markers_enabled` (default on) hides them. Enemy hit flash is unchanged. Impact chips are `VfxPool.Kind.CHIP`.

`BlockBreakFx` draws one crack box from `shaders/block_crack.gdshader` while a dig is held. The shader builds the cracks from a hash. There is no crack image. The stage follows a visual fill that resets when the layer breaks. It does not change the dig delay. A break spawns `CHIP` particles in the block tint. A placement scales one of four proxy boxes and does not rebuild a chunk. `crack_overlay_enabled` (default on) hides the overlay. Chips still play. Reduce motion snaps the place pop to full size.

New meshes set `cast_shadow` off. Terrain shaders stay unshaded.

## Audio

Autoload `AudioManager` looks up ids in `config/audio_manifest.gd`. Each id points at `res://assets/audio/...`. If the file is missing, the call returns and the id is printed once. Buses are Master, Music, SFX, and UI (`default_bus_layout.tres`). Linear volumes persist on `PlayerSettings` and are applied to `AudioServer`.

`set_music_state("maze"|"assault")` follows `GameManager.phase_changed`. Win and loss call `run_win` / `run_lose` from `run_state_changed`.

The pause menu and the frontend settings screen edit the three effect toggles and the four bus volumes. Both saves start from `load_settings()`, so a partial write does not reset the other keys.

No audio files are in the repo. Record the list in `assets/audio/SOUNDS_NEEDED.md`.

## Settings

| Key | Default | Effect |
| --- | --- | --- |
| `screen_shake_enabled` | on | Camera offset |
| `hit_stop_enabled` | on | Time-scale dip |
| `flash_effects_enabled` | on | White overlay flash |
| `hit_markers_enabled` | on | Hit, miss, and blocked markers |
| `crack_overlay_enabled` | on | Mining crack overlay. Chips still play when this is off |
| `volume_master` / `volume_music` / `volume_sfx` / `volume_ui` | 1 | Bus linear gain |
| `reduce_motion` | off | Blocks shake, hit-stop, walk bob, creature bob, and large bursts |

Headless suites: `scripts/verify_juice.gd`, `scripts/verify_item_animations.gd`, `scripts/verify_block_break_place_fx.gd`, `scripts/verify_ui_settings.gd`. The rest of the settings keys live in `studio/wiki/UI.md`.
