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

- Walk bob and landing squash scale the visual node. The player bob runs only while `RUNNING` and multiplies the existing landing squash. Creatures bob only inside `bob_columns` (LOW 8, MEDIUM 22, HIGH 36, SAFE 0) and only if the camera can see them. The physics body is not scaled.
- Hit-stop dips `Engine.time_scale` to 0.02 for 40–80 ms and restores the previous scale with a real-time timer. Gameplay calls do nothing when `DisplayServer.get_name() == "headless"` (Godot 4.7 `--headless` leaves `OS.has_feature("headless")` false), when the setting is off, or when time scale is already away from 1 (the relic modal uses 0.05). `verify_juice` passes `force` to run the dip. A relic offer calls `Juice.cancel_hit_stop()` first and saves that pre-dip scale, so a killing blow cannot leave the run at 0.02.
- Screen shake is a decaying offset added by `player/camera.gd` after it writes `global_position`. Boss impacts and bombs use a larger amount. Gameplay shake uses the same headless check as hit-stop.
- Hit flash sets `flash_amount` on one shared `shaders/entity_hit_flash.gdshader` overlay and clears that overlay when the amount returns to zero. No material is allocated per hit.

Death moves the visual onto `CombatVisualFeedback` (cap 6) for a 0.4 s shrink and fade, then frees it. The body `queue_free`s immediately so death signals and spawn-cell cleanup stay on the old frame.

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
| `volume_master` / `volume_music` / `volume_sfx` / `volume_ui` | 1 | Bus linear gain |

Headless suite: `scripts/verify_juice.gd`.
