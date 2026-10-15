# Comment strip — Crystal Storm v0.3.0

Code-only snapshot of tag v0.3.0 (`.gd`, `.gdshader`, `.sh`, `project.godot`). Art, scenes, and other assets are not in this tree, so the game cannot be run from here. The live game is `0.2.8/`. Older trees shipped in the same tag (`0.2.3`–`0.2.6`, `crystalstorm0.2.0`, `crystalstorm0.2.2`, `yweauh-2`) and `.cursor/skills/verify-crystal-storm/cs-verify.sh` were stripped with the same rules.

Baseline commit `5405f4c` is the zip, unchanged. `no-comments.patch` is `git diff 5405f4c` through the commit that adds this report. It does not contain itself. From a checkout of the original repository at tag v0.3.0:

```
git apply -p1 no-comments.patch
```

## Result

- 7,142 comment occurrences removed across 785 files.
- 628 comments kept.
- No renames. No extracted functions. No new `assert` or `const`. Numbers, strings, signals, node paths, and exported property names are unchanged.
- The only non-comment edits are six trailing comments removed from an existing `pass` (the statement stays `pass`, so the block is not empty).
- Re-stripping the baseline with the same tool reproduces this tree byte for byte.

## Deleted, by folder

A deletion is one comment occurrence (a full-line comment, or the comment tail of a code line). Counts are the folder of the file, with `0.2.8` split by its first directory.

| Deleted | Folder |
| ---: | --- |
| 1679 | `0.2.8/scripts` |
| 575 | `0.2.8/world` |
| 497 | `0.2.8/systems` |
| 317 | `0.2.8/chunks` |
| 226 | `0.2.8/player` |
| 200 | `0.2.8/crystal` |
| 149 | `0.2.8/helpers` |
| 137 | `0.2.8/assets` |
| 84 | `0.2.8/ui` |
| 74 | `0.2.8/entities` |
| 71 | `0.2.8/config` |
| 45 | `0.2.8/weapons` |
| 33 | `0.2.8/fluids` |
| 31 | `0.2.8/shaders` |
| 24 | `0.2.8/tools` |
| 24 | `0.2.8/verify_river_specs.gd` |
| 18 | `0.2.8/game` |
| 16 | `0.2.8/stats` |
| 11 | `0.2.8/main.gd` |
| 6 | `0.2.8/relics` |
| 3 | `0.2.8/debug_drainage_patch.gd` |
| 1 | `0.2.8/addons` |
| 1 | `0.2.8/building` |
| 1 | `0.2.8/inventory` |
| 1564 | `0.2.6` |
| 486 | `0.2.5` |
| 357 | `0.2.4` |
| 160 | `crystalstorm0.2.2` |
| 146 | `yweauh-2` |
| 108 | `crystalstorm0.2.0` |
| 89 | `0.2.3` |
| 9 | `.cursor` |
| **7142** | **total** |

Rolled up to the top-level tree:

| Deleted | Tree |
| ---: | --- |
| 4223 | `0.2.8` |
| 1564 | `0.2.6` |
| 486 | `0.2.5` |
| 357 | `0.2.4` |
| 160 | `crystalstorm0.2.2` |
| 146 | `yweauh-2` |
| 108 | `crystalstorm0.2.0` |
| 89 | `0.2.3` |
| 9 | `.cursor` |

## Why those comments went

| Removed | Class |
| ---: | --- |
| 6290 | restate — Restates the following code, or narrates an edit that the code already shows. |
| 318 | banner — Section banners and divider lines. |
| 172 | commented-code — Commented-out code. |
| 135 | script-narration — Verify-script prose that is not a locked number or an engine bug. |
| 112 | usage — Usage banners under a shebang. The shebang itself stays. |
| 69 | step — Numbered procedure comments. |
| 39 | narration — TODO, FIXME, and "add this line" notes. |
| 7 | blank — Empty comment lines that were not part of a format header. |

Shader lines whose first non-whitespace character is `#` (`#shader_type` and similar) are preprocessor directives and were not treated as comments. Godot annotations (`@tool`, `@export`, `class_name`, `extends`, `@warning_ignore`) are not comments. This snapshot has no `# warning-ignore` and no `#region` / `#endregion` markers.

## Kept, by reason

| Kept | Reason |
| ---: | --- |
| 21 | Shebang |
| 68 | File-format header (project.godot or bake disk layout) |
| 18 | Verify-script line that states a locked number or an engine bug |
| 418 | External constraint or non-obvious invariant |
| 103 | Next sentence of a kept constraint (same comment block) |
| **628** | **total** |

Every kept comment is listed at the bottom, with the line number in the stripped file.

## Locked rules

These are the "do not remove" design locks called out for PLAN-0.3. They stay as comments. They were not encoded as `assert` or `const`: an assert would change the failure path, and a new constant would be a new symbol. The numbers those comments describe were already in the code and were not edited.

Dig tools (pick and other dig tools break blocks; combat weapons, including the crystal hammer, never dig; a right-click ability never also places):

- `0.2.8/helpers/placeable_catalog.gd:3`
- `0.2.8/helpers/item_types.gd:266`, `:280`
- `0.2.8/config/item_def.gd:35` (footprint in columns; 0 means not a dig tool)
- `0.2.8/weapons/weapon_controller.gd:109`–`:111`, `:139`, `:169`, `:191`, `:515`
- `0.2.8/scripts/verify_content_contracts.gd:119`
- `0.2.8/scripts/verify_sword_no_terrain_subtract.gd:2`
- `0.2.8/world/living_force.gd:15`, `:24` (depth on an existing cell; never seeds one)

Hammer timing. The view uses a 0.65 pre-hit split inside the wind-up and says not to move it. The verify scripts lock the hit to 0.62 of the 1.1 s swing:

- `0.2.8/systems/held_item_view.gd:143`–`:145`
- `0.2.8/weapons/weapon_controller.gd:169` (damage stays on the wind-up frame)
- `0.2.8/scripts/verify_held_item_use.gd:2`
- `0.2.8/scripts/verify_cursor_aim.gd:2`, `:182`

Camera ortho size 16 (old size 24):

- `0.2.8/player/camera.gd:64`
- `0.2.8/systems/held_item_view.gd:236`–`:238` (readable at ortho 16; `u` is one `voxel_scale`)
- `0.2.8/scripts/verify_camera_default_zoom.gd:2`
- `0.2.8/scripts/verify_held_item_mesh.gd:2`
- `0.2.8/scripts/display_block_texture_grid.gd:2`
- `0.2.8/scripts/verify_block_texture_grid.gd:161`
- `0.2.8/shaders/water_surface.gdshader:33`
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:77`–`:79` (a 0.04 cutoff reads as a grid at ortho 16)

`voxel_scale` and column-versus-world-unit contracts (a wrong conversion doubles walls or misses probes):

- `0.2.8/helpers/world_visual_coords.gd:3`–`:5`
- `0.2.8/config/world_settings.gd:12`, `:61`, `:101`–`:103`, `:120`
- `0.2.8/config/item_def.gd:27`
- `0.2.8/config/enemy_spawn_def.gd:17`, `:30`
- `0.2.8/systems/game_visual_registry.gd:12`, `:488`–`:492` (short Y cap; full `Y * voxel_scale` would double the wall)
- `0.2.8/world/town_manager.gd:140` (world units, not legacy 0–158)
- `0.2.8/player/voxel_floor_probe.gd:189`, `:400`
- `0.2.8/player/action_targeting.gd:12`–`:13`, `:191`
- `0.2.8/entities/world_entity.gd:253`, `:539`
- `0.2.8/entities/crystal_enemy.gd:474`
- `0.2.8/assets/structures/*/author_*.gd` headers that state the XZ `voxel_scale` bind and the short Y cap

Sun shade and cave fog stay on at every preset: `0.2.8/helpers/terrain_lighting.gd:3`. The shared `terrain_*` shader-global registry is `terrain_lighting.gd:39` and `player/camera.gd:353`. `get_list` is editor-only (`terrain_lighting.gd:28`, `camera.gd:334`).

Ramps. Axis frame, greedy skip, toward-low-west reference, one landing column, and the winding that keeps the iso camera off the underside:

- `0.2.8/helpers/voxel_primitive_meshes.gd:4`–`:6`, `:126`, `:157`
- `0.2.8/helpers/terrain_ramps.gd:99`–`:100`, `:108`–`:109`, `:139`
- `0.2.8/helpers/chunk_surface_mesh_builder.gd:546`, `:593`
- `0.2.8/chunks/chunk_manager.gd:1351`–`:1352`, `:2028`–`:2032` (the seam must stay unfilled)
- `0.2.8/shaders/ChunkRamp.gdshader:3`–`:5`, `:61` (black diamonds; 0.04 cutoff)

The same locks that exist in `0.2.6` (and the winding / shader notes in `0.2.4` and `0.2.5`) were kept there too. They are in the inventory, not repeated here.

## Other constraints that were kept

These are not PLAN numbers, but they record something the code cannot say by itself: an engine bug, a file format, or an invariant that a rename would not capture.

- Godot 4.7 does not deliver `NOTIFICATION_WM_CLOSE_REQUEST` to nodes; `close_requested` is the alive-snapshot path (`0.2.8/main.gd:81`–`:83`). Sibling picking ignores `z_index` (`ui/inventory_panel.gd:67`, `ui/hotbar.gd:55`). `--headless` does not set the `headless` feature (`systems/juice.gd:3`–`:4`). `run_smoke_gameplay.sh` tolerates teardown abort 134.
- `WorkerThreadPool` task ids must be waited exactly once or shutdown SIGSEGV / double-frees (`chunks/chunk_manager.gd` in `0.2.8` and `0.2.6`). Do not `queue_free` ChunkViews from `_exit_tree`. Do not `remove_child` LayerContainer children in `chunk_view.gd` (glibc double free). Performance monitor callables must be removed before autoload free. Worker threads cannot call `class_name` statics. Do not clear a dictionary a worker is indexing.
- Bake disk layout v4 (`world.index`, `chunks/cx_cz.chk`, `static_meta.json`, tombstones) in `world/world_bake_service.gd`. Save `schema_version` 1 vs 2 in `systems/save_schema.gd`. Checksum mask for `store_32`. Each `project.godot` keeps the engine's `; Format:` header.
- ChunkView must classify faces in model space. View-space `NORMAL` discarded every face and left white voxels. Lambert blacks iso side faces. `T_MIN` 0.05 stays in sync with `helpers/camera_cutaway.gd`. A built-in `TIME` read would hide a missing `water_time` / pulse bind. `face_code` is `floor` plus a fraction of `uv_h`.
- In-package cells must not procedural-generate when a valid index exists. Crystal must not expand past the playable edge. Flow must not delete a donor cell (checkerboard blink). Natural river tiles must not be gathered as player channels.

## Renames and extractions

None. A comment that explained a confusing name was left in place when changing the name would touch an export, a signal, a node path, or another file. No function was extracted.

## The six `pass` edits

Each of these was already `pass`. Only the trailing comment was removed.

| File | Line | Removed tail |
| --- | ---: | --- |
| `0.2.4/chunks/chunk_data.gd` | 61 | `no-op, derived from maps` |
| `0.2.5/chunks/chunk_data.gd` | 147 | `no-op, derived from maps` |
| `0.2.6/chunks/chunk_data.gd` | 789 | `no-op, derived from maps` |
| `0.2.8/chunks/chunk_data.gd` | 924 | `no-op, derived from maps` |
| `0.2.6/systems/spatial_query_layer.gd` | 229 | `reserved for future compaction` |
| `0.2.8/systems/spatial_query_layer.gd` | 229 | `reserved for future compaction` |

No new `pass` was inserted. No block was left empty.

## Syntax check

Godot 4.7-stable (`Godot_v4.7-stable_linux.x86_64`) ran `godot --headless --check-only --path <project> --script <file>` on the 511 changed `.gd` scripts. The log has no `Expected indented block`, `Unexpected`, `Mixed use of tabs and spaces`, or `Expected end of statement`. It does report missing types and missing preloads (`ChunkManager`, scenes, png, tres). Those files are not in this zip, and the global class cache was never imported. That is an asset gap, not a parse error introduced by the strip.

`bash -n` passed on every `.sh`. Quote parity for `'''` and `"""`, and whether the file ended in a newline, match the baseline. Older `main.gd` files that start with a short script and then a triple-quoted legacy source keep that string intact; `#` inside it was not treated as a comment.

## Risks

- The keep decision is a keyword rule plus a short sentence-continuation inside a comment block (103 of the 628 kept lines). A continuation can be a softer sentence sitting under a real constraint. The inventory is the place to delete one of those later. Nothing in that set was rewritten.
- Verify scripts lost their procedure comments (135 narration lines, 112 usage lines). The checks themselves are unchanged. A reader of `scripts/verify_*.gd` no longer has the comment that said what the probe was trying to catch, except where the line stated a locked number or an engine bug (18 script-locked lines, plus shebangs).
- `0.2.8/world/world_viewer.gd:615` (and the same line in `0.2.4`, `0.2.5`, `0.2.6`) starts with `1.` and survived because it says `world units`. It is a diagnostic note, not a format spec.
- `0.2.8/player/voxel_floor_probe.gd:546` (and `0.2.6` `:406`) describes step easing ("ledges don't feel floaty"). It matched `don't` and was kept. It does not encode a numeric lock.
- Godot could not typecheck this tree. A scene that depended on a comment is not a thing Godot does; the remaining risk is a human reader, not the parser.

## Kept comments

Line numbers are in the stripped files.

### Shebang

- `0.2.8/scripts/run_streaming_after_profile.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_chunk_mesh_investigation.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_all_verify.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/dev_assistant_respond.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_regenerate_atlas.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/generate_backlog_triage.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_terrain_surface_benchmark.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_profile_gameplay.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_crystal_render_benchmark.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_gpu_renderer_investigation.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_streaming_lifecycle_investigation.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_streaming_traversal_benchmark.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/verify_river_seeds.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_streaming_low_traversal.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_smoke_gameplay.sh:1` #!/usr/bin/env bash
- `0.2.8/scripts/run_display_session.sh:1` #!/usr/bin/env bash
- `.cursor/skills/verify-crystal-storm/cs-verify.sh:1` #!/usr/bin/env bash
- `0.2.5/scripts/run_all_verify.sh:1` #!/usr/bin/env bash
- `0.2.5/scripts/verify_river_seeds.sh:1` #!/usr/bin/env bash
- `0.2.5/scripts/run_smoke_gameplay.sh:1` #!/usr/bin/env bash
- `0.2.5/scripts/run_display_session.sh:1` #!/usr/bin/env bash

### File-format header (project.godot or bake disk layout)

- `0.2.3/project.godot:1` ; Engine configuration file.
- `0.2.3/project.godot:2` ; It's best edited using the editor UI and not directly,
- `0.2.3/project.godot:3` ; since the parameters that go here are not all obvious.
- `0.2.3/project.godot:4` ;
- `0.2.3/project.godot:6` ;   [section] ; section goes between []
- `0.2.3/project.godot:7` ;   param=value ; assign values to parameters
- `crystalstorm0.2.2/project.godot:1` ; Engine configuration file.
- `crystalstorm0.2.2/project.godot:2` ; It's best edited using the editor UI and not directly,
- `crystalstorm0.2.2/project.godot:3` ; since the parameters that go here are not all obvious.
- `crystalstorm0.2.2/project.godot:4` ;
- `crystalstorm0.2.2/project.godot:6` ;   [section] ; section goes between []
- `crystalstorm0.2.2/project.godot:7` ;   param=value ; assign values to parameters
- `0.2.8/project.godot:1` ; Engine configuration file.
- `0.2.8/project.godot:2` ; It's best edited using the editor UI and not directly,
- `0.2.8/project.godot:3` ; since the parameters that go here are not all obvious.
- `0.2.8/project.godot:4` ;
- `0.2.8/project.godot:6` ;   [section] ; section goes between []
- `0.2.8/project.godot:7` ;   param=value ; assign values to parameters
- `0.2.8/world/world_bake_service.gd:3` ## Streamed finite-world bake for Engine 1.0.
- `0.2.8/world/world_bake_service.gd:4` ##
- `0.2.8/world/world_bake_service.gd:5` ## Loading UI may connect to status_changed for real progress (mode + 0..1).
- `0.2.8/world/world_bake_service.gd:6` ##
- `0.2.8/world/world_bake_service.gd:8` ##   user://world_bakes/v4_s{seed}_{full\|rN}/
- `0.2.8/world/world_bake_service.gd:10` ##     chunks/cx_cz.chk     — terrain columns + mesh plan + baked vegetation
- `0.2.8/world/world_bake_service.gd:12` ##
- `0.2.8/world/world_bake_service.gd:13` ## Runtime memory holds only the index + packages for currently streamed chunks.
- `0.2.8/world/world_bake_service.gd:14` ## Baked vegetation is installed into WorldState when a chunk becomes resident.
- `0.2.8/world/world_bake_service.gd:15` ## WorldState remains sole authority for digs/builds/crystal/session mutations
- `0.2.4/project.godot:1` ; Engine configuration file.
- `0.2.4/project.godot:2` ; It's best edited using the editor UI and not directly,
- `0.2.4/project.godot:3` ; since the parameters that go here are not all obvious.
- `0.2.4/project.godot:4` ;
- `0.2.4/project.godot:6` ;   [section] ; section goes between []
- `0.2.4/project.godot:7` ;   param=value ; assign values to parameters
- `crystalstorm0.2.0/project.godot:1` ; Engine configuration file.
- `crystalstorm0.2.0/project.godot:2` ; It's best edited using the editor UI and not directly,
- `crystalstorm0.2.0/project.godot:3` ; since the parameters that go here are not all obvious.
- `crystalstorm0.2.0/project.godot:4` ;
- `crystalstorm0.2.0/project.godot:6` ;   [section] ; section goes between []
- `crystalstorm0.2.0/project.godot:7` ;   param=value ; assign values to parameters
- `0.2.6/project.godot:1` ; Engine configuration file.
- `0.2.6/project.godot:2` ; It's best edited using the editor UI and not directly,
- `0.2.6/project.godot:3` ; since the parameters that go here are not all obvious.
- `0.2.6/project.godot:4` ;
- `0.2.6/project.godot:6` ;   [section] ; section goes between []
- `0.2.6/project.godot:7` ;   param=value ; assign values to parameters
- `0.2.6/world/world_bake_service.gd:3` ## Streamed finite-world bake for Engine 1.0.
- `0.2.6/world/world_bake_service.gd:4` ##
- `0.2.6/world/world_bake_service.gd:5` ## Loading UI may connect to status_changed for real progress (mode + 0..1).
- `0.2.6/world/world_bake_service.gd:6` ##
- `0.2.6/world/world_bake_service.gd:8` ##   user://world_bakes/v4_s{seed}_{full\|rN}/
- `0.2.6/world/world_bake_service.gd:10` ##     chunks/cx_cz.chk     — terrain columns + mesh plan + baked vegetation
- `0.2.6/world/world_bake_service.gd:12` ##
- `0.2.6/world/world_bake_service.gd:13` ## Runtime memory holds only the index + packages for currently streamed chunks.
- `0.2.6/world/world_bake_service.gd:14` ## Baked vegetation is installed into WorldState when a chunk becomes resident.
- `0.2.6/world/world_bake_service.gd:15` ## WorldState remains sole authority for digs/builds/crystal/session mutations
- `yweauh-2/project.godot:1` ; Engine configuration file.
- `yweauh-2/project.godot:2` ; It's best edited using the editor UI and not directly,
- `yweauh-2/project.godot:3` ; since the parameters that go here are not all obvious.
- `yweauh-2/project.godot:4` ;
- `yweauh-2/project.godot:6` ;   [section] ; section goes between []
- `yweauh-2/project.godot:7` ;   param=value ; assign values to parameters
- `0.2.5/project.godot:1` ; Engine configuration file.
- `0.2.5/project.godot:2` ; It's best edited using the editor UI and not directly,
- `0.2.5/project.godot:3` ; since the parameters that go here are not all obvious.
- `0.2.5/project.godot:4` ;
- `0.2.5/project.godot:6` ;   [section] ; section goes between []
- `0.2.5/project.godot:7` ;   param=value ; assign values to parameters

### Verify-script line that states a locked number or an engine bug

- `0.2.8/scripts/verify_held_item_mesh.gd:2` ## readable at the game camera (ortho 16) and actually drawn.
- `0.2.8/scripts/display_block_texture_grid.gd:2` ## Windowed terrain shot at the game camera (ortho 16, iso pitch).
- `0.2.8/scripts/autonomous_gameplay_audit.gd:2` ## Does not pass by hardcoded expected cell values.
- `0.2.8/scripts/verify_block_texture_grid.gd:161` # ortho 16. Apply the shader's own cutoff to the tile.
- `0.2.8/scripts/verify_content_contracts.gd:119` ## Only dig tools break blocks. Right-click abilities never place. Hammer wind-up stays.
- `0.2.8/scripts/verify_composition_boot.gd:124` # (Manual free() + quit previously raced ObjectDB and printed double-free on exit.)
- `0.2.8/scripts/verify_main_teardown.gd:2` ## Regression: production main scene teardown must not abort with double-free.
- `0.2.8/scripts/verify_held_item_use.gd:2` ## Hammer impact stays 0.62 of the 1.1 s swing: the hit is not allowed early.
- `0.2.8/scripts/_repro_isolate_quit.gd:2` ## Binary-search which subsystem leaves a double-free on quit.
- `0.2.8/scripts/profile_feature_seeding.gd:2` ##   godot --headless -s scripts/profile_feature_seeding.gd
- `0.2.8/scripts/verify_ramp_geometry.gd:33` # One column: size on X/Z must be ~voxel_scale, not the old 1.5-cell span.
- `0.2.8/scripts/verify_cursor_aim.gd:2` ## The hammer press waits through the 0.62 wind-up of the 1.1 s swing.
- `0.2.8/scripts/verify_cursor_aim.gd:182` ## (inside the hit range) is the one that gets hit after the wind-up.
- `0.2.8/scripts/verify_sword_no_terrain_subtract.gd:2` ## Regression: sword/bow LMB must never dig or remove terrain/buildings (INPUT_CONTRACT).
- `0.2.8/scripts/verify_camera_default_zoom.gd:2` ## Default ortho zoom is closer than the old 24. Wheel limits, the rig, and iso pitch stay.
- `0.2.8/scripts/run_smoke_gameplay.sh:2` # Run smoke_gameplay; exit 0 when terminal marker is OK (tolerates Godot teardown abort 134).
- `0.2.8/scripts/_repro_isolate_nodes.gd:2` ## Remove named nodes from main.tscn before add_child to isolate double-free.
- `0.2.5/scripts/run_smoke_gameplay.sh:2` # Run smoke_gameplay; exit 0 when terminal marker is OK (tolerates Godot teardown abort 134).

### External constraint or non-obvious invariant

- `0.2.3/project.godot:5` ; Format:
- `0.2.3/chunks/chunk_manager.gd:120` # Localized safe fallback checking to avoid Dictionary lookup thread deadlocks
- `crystalstorm0.2.2/project.godot:5` ; Format:
- `crystalstorm0.2.2/chunks/chunk_manager.gd:78` # THREAD-SAFE FIX: Do not use class variables. Scope these locally!
- `crystalstorm0.2.2/shaders/ChunkView.gdshader:4` // from leaving hidden punch-holes, passing all layer order over to your sorting_offsets!
- `crystalstorm0.2.2/shaders/multimeshinstance2d_shader.gdshader:14` // Safe half-pixel padding to stop texel bleeding on the atlas PNG
- `0.2.8/project.godot:5` ; Format:
- `0.2.8/main.gd:81` ## Godot 4.7 does not pass NOTIFICATION_WM_CLOSE_REQUEST on to nodes.
- `0.2.8/main.gd:82` ## The root window emits close_requested. With auto-accept off, that signal
- `0.2.8/crystal/crystal_manager.gd:545` # do not stay embedded in old terrain (presentation only; sim depth unchanged).
- `0.2.8/crystal/crystal_manager.gd:1335` # Loaded chunk set from ChunkManager (façade gathers; sim never touches the tree).
- `0.2.8/crystal/crystal_manager.gd:1737` # Crystal never expands past the intentional playable map edge.
- `0.2.8/crystal/crystal_manager.gd:2091` ## that already sampled the terrain base do not walk the ramp a second time.
- `0.2.8/crystal/crystal_manager.gd:2546` # Missing key must not wipe live win targets (empty {} import used to clear all).
- `0.2.8/crystal/crystal_corruption.gd:203` # Drop the scar marker without a tombstone so baked plants can return.
- `0.2.8/crystal/crystal_fluid_sim.gd:621` # Flow never deletes a cell. Over-outflow used to erase the donor and
- `0.2.8/crystal/crystal_chunk_layer.gd:123` ## x = horizontal scale, y = height in world units, z = frontier_boost.
- `0.2.8/ui/loading_screen.gd:482` # Do not map full-world fill (16k packages) onto the start-region bar.
- `0.2.8/ui/live_world_inspector.gd:296` # Do not draw a filled cell slab — it reads as a black voxel top on camera.
- `0.2.8/ui/topographical_map.gd:73` ## voxel_position X/Z are already column indexes. Do not pass them through world_to_column.
- `0.2.8/ui/topographical_map.gd:234` # A job still in flight must not consume the movement. Retry next frame.
- `0.2.8/ui/relic_choice_panel.gd:14` ## Pre-modal scale, captured only while no panel is open. A queued offer must not save 0.05.
- `0.2.8/ui/game_overlay.gd:603` # the existing sim field the player can actually see changing. Do not print
- `0.2.8/ui/tooltip_panel.gd:3` ## Hidden tooltips do not run _process.
- `0.2.8/ui/tutorial_overlay.gd:157` # close() dismisses this overlay. Do not toggle or the pause menu reopens.
- `0.2.8/ui/inventory_panel.gd:67` # Godot picks the later sibling, and z_index does not change that.
- `0.2.8/ui/hotbar.gd:55` # Drawn above the inventory dimmer. Picking ignores z_index, so the bag
- `0.2.8/ui/frontend_root.gd:287` # Continue file is the alive-quit snapshot. Do not also apply the world file.
- `0.2.8/helpers/voxel_primitive_meshes.gd:4` ## +X = east, +Z = south, +Y = up.
- `0.2.8/helpers/voxel_primitive_meshes.gd:5` ## Ramp/corner/concave meshes include slopes plus back/floor/side fills (greedy skips these cells).
- `0.2.8/helpers/voxel_primitive_meshes.gd:6` ## Cardinal +Z ramps are derived from the west (toward-low-west) reference via axis transforms.
- `0.2.8/helpers/voxel_primitive_meshes.gd:126` ## Reference mesh: toward-low-west landing (high east back, side fills peak on east edge).
- `0.2.8/helpers/voxel_primitive_meshes.gd:157` ## Reference mesh: toward-low-west + toward-low-north corner (high WN, fills on east/south).
- `0.2.8/helpers/terrain_lighting.gd:3` ## Detail, sun shade, and cave fog stay on at every preset.
- `0.2.8/helpers/terrain_lighting.gd:28` # get_list is editor-only; see _add(
- `0.2.8/helpers/terrain_lighting.gd:39` # shared registry: camera + terrain_lighting both register terrain_*
- `0.2.8/helpers/world_visual_coords.gd:3` ## Y is already in world units (layer_height == voxel_scale).
- `0.2.8/helpers/world_visual_coords.gd:4` ## Node3D XZ is column * voxel_scale. Never treat global_position.x as a column
- `0.2.8/helpers/placeable_catalog.gd:3` ## Only dig tools break blocks.
- `0.2.8/helpers/chunk_surface_mesh_builder.gd:546` # Landing column only. Low edge is toward `dir` (world-cell step-down).
- `0.2.8/helpers/chunk_surface_mesh_builder.gd:593` # Solid under the wedge: the landing column's floor at the low edge (approach top).
- `0.2.8/helpers/macro_terrain_perf_gate.gd:3` ## Frozen perf contract for macro vs legacy median comparison (probe must not redefine).
- `0.2.8/helpers/terrain_ramps.gd:99` ## Step wedge: one landing column only. Local +X is the high edge (away from the low neighbor).
- `0.2.8/helpers/terrain_ramps.gd:100` ## Collision uses the same column: voxel_top at t=0, voxel_top-layer at t=1 toward the low neighbor.
- `0.2.8/helpers/terrain_ramps.gd:108` # Winding A,D,C,B so the slope normal is (-1, 1, 0) — toward +Y. The previous
- `0.2.8/helpers/terrain_ramps.gd:109` # A,B,C,D winding faced -Y, so the iso camera lit the underside (black diamonds).
- `0.2.8/helpers/terrain_ramps.gd:139` # Winding must face +Y so the walkable top renders (was inverted).
- `0.2.8/helpers/voxel_types.gd:68` ## new_tile_set.tres / voxelsnew.png use a different 64 px strip layout — do not bind to ChunkView.
- `0.2.8/helpers/voxel_types.gd:79` ## Minecraft-style face picking: grass tops on FACE_TOP, dirt/earth on vertical sides, dirt underside.
- `0.2.8/helpers/voxel_types.gd:167` ## Ramps (face >= 7) use the landing top. Bottoms stay the underside cell.
- `0.2.8/helpers/water_locomotion.gd:94` # Do not create a session just to discover there is no water.
- `0.2.8/helpers/water_locomotion.gd:106` # Border ocean stays a wall. WorldBorder blocks the step; swimming must not carry a body along it.
- `0.2.8/helpers/item_types.gd:266` ## Pickaxe and other dig tools. Combat weapons, including the crystal hammer, do not.
- `0.2.8/helpers/item_types.gd:280` ## Right-click use that must not also place a block. Placeable blocks are not abilities.
- `0.2.8/helpers/chunk_data_pool.gd:43` # Never pool the same shell twice (double free / RefCounted corruption).
- `0.2.8/helpers/terrain_vertex_ao.gd:27` ## Halo when it is filled, otherwise an in-chunk map read. Never calls the world.
- `0.2.8/config/item_def.gd:27` ## Horizontal shove in voxels. World distance is this times voxel_scale.
- `0.2.8/config/item_def.gd:35` ## Dig-tool footprint in columns. 1 is the single-column dig. 0 means not a dig tool.
- `0.2.8/config/world_settings.gd:12` ## Hard cap on generated terrain height, measured in voxel layers (not world units).
- `0.2.8/config/world_settings.gd:61` ## Feet sit on top of the solid voxel column (surface_y + layer_height).
- `0.2.8/config/world_settings.gd:101` ## One voxel column is layer_height() world units. A person is 1.6 voxels tall
- `0.2.8/config/world_settings.gd:120` ## Melee contact reach: both bodies plus a short gap, in world units.
- `0.2.8/config/enemy_spawn_def.gd:17` ## Hit radius in voxels. World size is hit_radius * voxel_scale.
- `0.2.8/config/enemy_spawn_def.gd:30` ## Body size in voxels (one voxel = voxel_scale world units).
- `0.2.8/chunks/chunk_data.gd:15` ## Macro terrain authority (v2). Legacy maps are synced views for mesh/verify scripts.
- `0.2.8/chunks/chunk_data.gd:33` # Snapshotted on main thread before worker generation (avoids live WorldState races).
- `0.2.8/chunks/chunk_data.gd:38` ## Halo-region height deltas (world units), same dim as _halo_surface — worker-safe.
- `0.2.8/chunks/chunk_data.gd:59` ## Legacy bound — prefer WorldSettings.get_active().chunk_height_bound() for checks.
- `0.2.8/chunks/chunk_data.gd:68` # Legacy 3D paths (if any) will see AIR / false.
- `0.2.8/chunks/chunk_data.gd:240` # Read authority storage once; convert height layers → world units for workers.
- `0.2.8/chunks/chunk_data.gd:411` # Outside package bounds, or no valid bake: legacy noise (allowed for out-of-bounds).
- `0.2.8/chunks/chunk_data.gd:683` ## Dirty column = baked base (or legacy noise outside package) + frozen WorldState overlays.
- `0.2.8/chunks/chunk_data.gd:696` # Authored WorldObjects mark build_tile without raising — do not retile
- `0.2.8/chunks/chunk_data.gd:788` # Worker / post-capture path: never re-read live WorldState.
- `0.2.8/chunks/chunk_data.gd:822` # Drop the reference. clear() in place races a worker that is indexing it.
- `0.2.8/chunks/chunk_data.gd:867` # A yard stamp landed while this regen was already queued. Do not overwrite it.
- `0.2.8/chunks/chunk_data.gd:1004` ## Baked plant decorations are drawn by the vegetation layer and must not
- `0.2.8/chunks/chunk_manager.gd:21` ## Main-thread applies per frame (legacy path when FrameBudgetScheduler absent).
- `0.2.8/chunks/chunk_manager.gd:86` # Mirrored from WorldBorder — worker threads cannot call class_name statics reliably.
- `0.2.8/chunks/chunk_manager.gd:324` # or engine shutdown corrupts heap (SIGSEGV mutex=0x1c0 / free invalid).
- `0.2.8/chunks/chunk_manager.gd:329` ## wait left handles for engine teardown to free twice / UAF.
- `0.2.8/chunks/chunk_manager.gd:348` ## Safe to remove_child + free views here. Must NOT be used from _exit_tree (double free).
- `0.2.8/chunks/chunk_manager.gd:373` # Explicit teardown: do not pool — free views we own while tree is live.
- `0.2.8/chunks/chunk_manager.gd:395` ## Children will be freed by the engine — DO NOT queue_free ChunkViews here
- `0.2.8/chunks/chunk_manager.gd:396` ## (that is the double-free root cause: parent frees children twice).
- `0.2.8/chunks/chunk_manager.gd:426` # Null MultiMesh refs so RID teardown is single-owner.
- `0.2.8/chunks/chunk_manager.gd:654` # edge stream jobs do not cold-load packages inside sample_base.
- `0.2.8/chunks/chunk_manager.gd:1351` ## A cardinal's approach column is a floor. It must not also be a cardinal
- `0.2.8/chunks/chunk_manager.gd:1524` # Worker path: never touch live world/registries for halo neighbors.
- `0.2.8/chunks/chunk_manager.gd:1872` # Deep digs only lower surface_map. Do not emit leftover FACE_TOPs at
- `0.2.8/chunks/chunk_manager.gd:2032` # slope profile, so that seam must stay unfilled.
- `0.2.8/chunks/chunk_manager.gd:2303` # Do not recreate the pre-dig horizontal cap at natural_h (greedy top uses cur_h).
- `0.2.8/chunks/chunk_manager.gd:2661` # landing columns as black holes after dig/remesh.
- `0.2.8/chunks/chunk_manager.gd:2689` # Finite world: do not stream/generate infinite terrain outside playable bounds.
- `0.2.8/chunks/chunk_manager.gd:2783` # The halo is only the neighbor ring frozen for the worker. It must not
- `0.2.8/chunks/chunk_manager.gd:3309` # Do not null data.world here: regen reuses view.chunk_data and concurrent main-thread
- `0.2.8/chunks/chunk_manager.gd:3310` # rebuild enqueue can race a still-running or just-finished worker if world is cleared early.
- `0.2.8/chunks/chunk_manager.gd:3316` ## True when a completed mesh job must not be applied (token or WorldState mesh stamp).
- `0.2.8/chunks/chunk_manager.gd:3340` # Reap pool task id first (wait_for_task_completion). Must not only erase.
- `0.2.8/chunks/chunk_manager.gd:3371` # Worker-stage attribution only (must not count as main-thread tracked).
- `0.2.8/chunks/chunk_manager.gd:3636` ## Same-frame terrain edits (rapid dig/build) coalesce into one flush so we do not
- `0.2.8/chunks/chunk_view.gd:108` # IMPORTANT: Do NOT remove_child/queue_free LayerContainer children here.
- `0.2.8/chunks/chunk_view.gd:109` # queue_free of those Multimesh nodes here was a proven double-free
- `0.2.8/chunks/chunk_view.gd:110` # (glibc: "double free or corruption (!prev)").
- `0.2.8/chunks/chunk_view.gd:111` # Only detach MultiMesh Resource refs so RID ownership is single-path.
- `0.2.8/chunks/chunk_view.gd:499` ## Prevents heap corruption when stream-unload races the main-thread upload drain.
- `0.2.8/chunks/voxel_world.gd:26` # Legacy path without composition root.
- `0.2.8/chunks/chunk_pipeline.gd:61` # Full-world bake: never procedural-generate static terrain in package bounds.
- `0.2.8/chunks/chunk_pipeline.gd:256` ## Full worker path: column → mesh → buffer. Host must not use shared manager scratch.
- `0.2.8/systems/spatial_query_layer.gd:25` ## Default grid cell size in world units (XZ). ChunkData.SIZE is 16; half is a good default.
- `0.2.8/systems/aim_indicator.gd:3` ## Tools do not draw a second block box: they emit tool_aim_changed for TargetHighlight.
- `0.2.8/systems/combat_visual_feedback.gd:95` # Bind handles once; do not regenerate combat textures on every handoff.
- `0.2.8/systems/player_settings.gd:37` ## True after the first `apply_runtime`. Startup applies once; later reads must not.
- `0.2.8/systems/player_settings.gd:236` # Env preset owns quality + native render_distance. Do not apply saved
- `0.2.8/systems/save_game_service.gd:364` # Seal after all fields present; re-seal after validate so on-disk checksum matches load.
- `0.2.8/systems/save_game_service.gd:492` # Migrated/legacy flat path
- `0.2.8/systems/game_visual_registry.gd:12` ## World units per texture pixel (= voxel_scale * factor in 0.025–0.04 band).
- `0.2.8/systems/game_visual_registry.gd:146` ## Back-compat alias — do not block on ChunkManager (avoids VoxelWorld deadlock).
- `0.2.8/systems/game_visual_registry.gd:183` # Reuse session textures — never regenerate the full bundle on refresh.
- `0.2.8/systems/game_visual_registry.gd:489` # Y is a SHORT cap on raised terrain — full Y*voxel_scale would double the wall.
- `0.2.8/systems/game_visual_registry.gd:492` # Cap ≈ 0.9 world units tall (mesh height ~1.67 * 0.55), not a second full voxel stack.
- `0.2.8/systems/spatial_query_service.gd:143` # Height digs/builds (DOMAIN_TERRAIN only) do not move structure/town static markers.
- `0.2.8/systems/audio_manager.gd:27` # Keybinds, UI scale, and display once, before gameplay input. Later volume loads do not reapply them.
- `0.2.8/systems/perf_profiler.gd:5` ## Worker-attributed stages (completed off-main). Must NOT reduce main-thread untracked.
- `0.2.8/systems/perf_profiler.gd:145` # Godot 4 Performance monitors (bytes).
- `0.2.8/systems/perf_profiler.gd:156` ## or Godot double-frees the Callable lambdas on engine shutdown
- `0.2.8/systems/perf_profiler.gd:157` ## ("double free or corruption (!prev)" / "free(): invalid pointer").
- `0.2.8/systems/perf_profiler.gd:684` # Leaf record: pause parent exclusive so we don't double-count wall into parent.
- `0.2.8/systems/perf_profiler.gd:884` # Prefer exclusive only. Do not fall back to inclusive last_us for
- `0.2.8/systems/perf_profiler.gd:913` # Cap named to wall (mis-nested timers must not invent >100%).
- `0.2.8/systems/held_item_view.gd:3` ## Parts are created once and resized. A swing must not allocate.
- `0.2.8/systems/held_item_view.gd:143` # Raise through the wind-up, then the impact frame is the slam.
- `0.2.8/systems/held_item_view.gd:144` # The 0.65 split is the pre-hit hold: most of the wind-up is the raise,
- `0.2.8/systems/held_item_view.gd:145` # and the drop lands on the impact sample. Do not move that split.
- `0.2.8/systems/held_item_view.gd:236` ## The rest are offsets from the hand. Tall enough to read at ortho 16.
- `0.2.8/systems/held_item_view.gd:237` ## u is one voxel (voxel_scale). Every part is thick on X and Z so the iso
- `0.2.8/systems/performance_service.gd:89` # Do NOT mutate authored world_gen.caves_enabled — quality is policy-only.
- `0.2.8/systems/performance_service.gd:211` # Authored WorldGenConfig is not mutated by quality (composition policy).
- `0.2.8/systems/save_schema.gd:3` ## schema_version 1 = legacy flat terrain_edits/features/channels
- `0.2.8/systems/save_schema.gd:4` ## schema_version 2 = world_state authority block + revisions + integrity
- `0.2.8/systems/runtime_config_resolver.gd:5` ## Quality never mutates authored WorldGenConfig as sim authority; caves_enabled lives on the policy.
- `0.2.8/systems/runtime_config_resolver.gd:46` # Authored sim config is referenced, not mutated by quality.
- `0.2.8/systems/runtime_config_resolver.gd:52` # *runtime* cave rendering/query without rewriting the resource.
- `0.2.8/systems/crystal_texture_generator.gd:175` # Tools, weapons, blocks, and materials are 64 so the 48px slots do not
- `0.2.8/systems/juice.gd:4` ## (Godot 4.7 --headless does not set the "headless" feature) so probe timers stay in sync.
- `0.2.8/systems/juice.gd:190` # Drop the overlay once the flash is gone so hit enemies do not keep an extra pass.
- `0.2.8/weapons/weapon_controller.gd:109` # LMB breaks blocks only for the pick and other dig tools.
- `0.2.8/weapons/weapon_controller.gd:110` # Combat weapons (sword/bow/spear/hammer/sling/bomb): LMB is attack only — never dig or remove.
- `0.2.8/weapons/weapon_controller.gd:111` # Stone, wood, herbs, and other non-dig items do not break blocks.
- `0.2.8/weapons/weapon_controller.gd:139` # A right-click ability runs instead of placement and never places a block.
- `0.2.8/weapons/weapon_controller.gd:169` # Poses and ranged release share this clock. Hammer damage stays on its wind-up frame.
- `0.2.8/weapons/weapon_controller.gd:191` ## RMB use for herb, armor, bombs, and any item that sets alt_use. Never places.
- `0.2.8/weapons/weapon_controller.gd:360` # Item range is authored in columns; hit queries use world units.
- `0.2.8/weapons/weapon_controller.gd:515` ## 3×3 crystal splash. Low entity damage, heavy knockback. Never digs or changes height.
- `0.2.8/weapons/weapon_controller.gd:1028` # and do not restart it on every repeat tick.
- `0.2.8/player/move_feel.gd:3` ## Ramps, floor snap, and lighting do not read this.
- `0.2.8/player/voxel_floor_probe.gd:20` ## Disable with CRYSTALSTORM_PLAYER_HEIGHT_CACHE=0 for A/B measurement.
- `0.2.8/player/voxel_floor_probe.gd:155` # Column and edit delta are already separate components, so they do not alias.
- `0.2.8/player/voxel_floor_probe.gd:189` # Probe XZ is in column units. player_radius() is world units (voxel_scale wide).
- `0.2.8/player/voxel_floor_probe.gd:312` # A wall beside the body must not pull feet up onto that column.
- `0.2.8/player/voxel_floor_probe.gd:400` # Horizontal extent is columns; the body radius is authored in world units.
- `0.2.8/player/voxel_floor_probe.gd:441` ## Wood/stone walls block the column. Gates and bridges do not.
- `0.2.8/player/voxel_floor_probe.gd:442` ## Misses must not allocate: get_feature's default Dictionary is a heap alloc per call.
- `0.2.8/player/voxel_floor_probe.gd:488` # Wood and stone walls are WorldObjects. They do not raise the heightfield,
- `0.2.8/player/voxel_floor_probe.gd:490` # shuffle in the cell or leave it; probe offsets that only graze a wall do not.
- `0.2.8/player/voxel_floor_probe.gd:546` # Large steps settle faster so ledges don't feel floaty; micro deltas ease in.
- `0.2.8/player/player.gd:259` # voxel_position; a Continue boot must not fill the crystal heart first.
- `0.2.8/player/player.gd:672` # Fully blocked: kill residual velocity into the wall so we don't jitter.
- `0.2.8/player/camera.gd:21` ## Disabled: mouse at the screen edge must not pan or rotate the camera. Q/E yaw.
- `0.2.8/player/camera.gd:64` ## Ortho view height. 16 is about a third closer than the old 24 (30–40% band).
- `0.2.8/player/camera.gd:334` # get_list is editor-only; see _add_cutaway_global(
- `0.2.8/player/camera.gd:342` # Register once. Do not overwrite AO strength; quality owns that value.
- `0.2.8/player/camera.gd:353` # shared registry: camera + terrain_lighting both register terrain_*
- `0.2.8/player/action_targeting.gd:12` ## Slack as a fraction of voxel_scale. Just under half a column, so a ray through
- `0.2.8/player/action_targeting.gd:97` # Empty streamer (or unit probes): do not treat the world as unloaded for targeting.
- `0.2.8/player/action_targeting.gd:191` # Spatial index stores world-space positions (voxel_scale); probe must match.
- `0.2.8/player/action_targeting.gd:213` # Do not early-return empty: fall through to group scan if index is cold.
- `0.2.8/player/action_targeting.gd:333` # Always lock the column under the mouse when in range — solid checks must not
- `0.2.8/player/action_targeting.gd:413` # The ray hit something past interaction range. Do not pull that cell inward.
- `0.2.8/assets/structures/bridge/author_bridge.gd:2` ## Runtime bind multiplies XZ by voxel_scale and Y by ~1.15 — a LOW crossing
- `0.2.8/assets/structures/town_hall/author_town_hall.gd:2` ## Runtime bind multiplies XZ by voxel_scale; Y stays 1.0 — a WIDE hall
- `0.2.8/assets/structures/stone_wall/author_stone_wall.gd:2` ## Runtime bind multiplies XZ by WorldSettings.voxel_scale and uses a short Y cap.
- `0.2.8/assets/structures/stone_wall/author_stone_wall.gd:235` # Running bond: shift the first block so joints do not stack.
- `0.2.8/assets/structures/gate/author_gate.gd:2` ## Runtime bind multiplies XZ by voxel_scale. Y stays 1.0 — gate does not
- `0.2.8/assets/structures/ruin_pillar/author_ruin_pillar.gd:2` ## Runtime bind multiplies XZ by voxel_scale; Y stays 1.0 — a tall broken
- `0.2.8/assets/tiles/author_grass_dirt_variants.gd:32` ## Each row keeps one private column the neighbors in a 4-row window do not
- `0.2.8/game/game_manager.gd:174` # Field damage is a burn, not a hit. It must not grant or respect i-frames.
- `0.2.8/entities/crystal_enemy_spawner.gd:92` # Column-space distance (depth map is keyed by column, not world units).
- `0.2.8/entities/crystal_enemy_spawner.gd:109` # Don't dump a death burst during early orientation grace.
- `0.2.8/entities/world_entity.gd:253` ## Brain hit_radius is authored at voxel_scale 2. It tracks the world knob.
- `0.2.8/entities/world_entity.gd:539` ## Player voxel_position is column X/Z. Do not run it through column_pos.
- `0.2.8/entities/crystal_enemy.gd:474` # voxel_position is already column space. column_pos() expects world units.
- `0.2.8/entities/entity_navigation.gd:208` # Buoyancy owns vertical while submerged. A bed far below must not eat the step.
- `0.2.8/entities/entity_navigation.gd:293` ## Submerged bodies float toward the waterline and do not stay pinned to the bed.
- `0.2.8/tools/capture_blueprint.gd:22` # Keep the first-run tutorial from covering the shot. Do not save settings.
- `0.2.8/tools/capture_blueprint.gd:94` # In-memory only. Do not write player_settings.json.
- `0.2.8/fluids/voxel_fluid_service.gd:91` # sources and must not pull a whole marsh into the gather.
- `0.2.8/fluids/voxel_fluid_service.gd:133` # Cap work during interactive reflow so dig/channel do not freeze the main thread.
- `0.2.8/fluids/voxel_fluid_service.gd:138` # Local-only subset: do not scan every fluid cell in the world on each dig.
- `0.2.8/fluids/voxel_fluid_service.gd:409` # Already-full cells must not spend the new-cell budget, or the
- `0.2.8/fluids/voxel_fluid_service.gd:418` # Cells the wave has not reached yet must stay wet. Drying
- `0.2.8/world/world_bake_service.gd:7` ## Disk layout (v4):
- `0.2.8/world/world_bake_service.gd:9` ##     world.index          — lightweight bounds + flags (only thing loaded at startup)
- `0.2.8/world/world_bake_service.gd:11` ##     static_meta.json     — optional non-authoritative placement hints
- `0.2.8/world/world_bake_service.gd:16` ## (feature_cleared tombstones prevent re-applying destroyed plants).
- `0.2.8/world/world_bake_service.gd:17` ## Never procedural-generates static terrain/vegetation for coords covered by a valid index.
- `0.2.8/world/world_bake_service.gd:60` ## True while a deferred fill is running. `valid` stays false until world.index is written.
- `0.2.8/world/world_bake_service.gd:130` ## Runtime isolation counters (baked world must stay at 0 for in-package cells).
- `0.2.8/world/world_bake_service.gd:199` ## Returns {} if outside package or package unavailable (caller must not noise for covered cells).
- `0.2.8/world/world_bake_service.gd:210` ## Compose quantized surface from baked base + WorldState height delta (world units).
- `0.2.8/world/world_bake_service.gd:348` ## Mask to unsigned 32-bit for store_32 / get_32 checksum compare.
- `0.2.8/world/world_bake_service.gd:459` ## Catalog metadata only. Does not mutate the active bake session or open packages.
- `0.2.8/world/world_bake_service.gd:1752` ## (re-installing veg packages must not force plan repair every boot).
- `0.2.8/world/world_bake_service.gd:1954` # Do not keep per-chunk data in RAM after bake.
- `0.2.8/world/world_bake_service.gd:2217` # Terrain+veg counts checksum (store_var payloads validated by size + load success).
- `0.2.8/world/world_bake_service.gd:2867` # checksum ignored for legacy
- `0.2.8/world/world_viewer.gd:615` # 1. Connected components via proximity (real fragmentation + longest connected feature span in world units)
- `0.2.8/world/validation_yard.gd:87` ## band; south/north stay on the low z band so the runs do not climb onto
- `0.2.8/world/feature_registry.gd:117` # Session tombstone so streamed baked vegetation is not re-installed.
- `0.2.8/world/world_features.gd:224` ## must not wait for a fully validated bake — only decide if packages will supply veg.
- `0.2.8/world/world_features.gd:292` # Prefer composition-resolved policy when available so legacy path
- `0.2.8/world/town_manager.gd:140` # Heights are in current world units (voxel_scale), not legacy 0–158.
- `0.2.8/world/terrain_editor.gd:633` # Only unstack height that this structure actually added. Do not dig
- `0.2.8/world/world_object.gd:3` ## Terrain voxels stay MultiMesh; do not instance this per voxel.
- `0.2.8/world/world_visuals.gd:99` # Do not refresh all layers on every chunk_ready — that path regenerated the
- `0.2.8/world/channel_registry.gd:3` ## Water is the primary fluid (water_level / flow_dir — save-compatible).
- `0.2.8/world/world_bake_worker_job.gd:3` ## Must not touch Nodes, scene tree, live WorldState overlays, crystal, or water.
- `0.2.8/world/town_defense_manager.gd:136` ## Production content / harness: put a town under pressure without rewriting crystal sim.
- `0.2.8/world/InfiniteNoiseWorld.gd:8` # node is freed or engine shutdown hits a dead noise object.
- `0.2.8/world/InfiniteNoiseWorld.gd:483` # Pure compute path. Safe for background worker threads (never mutates caches).
- `0.2.8/world/InfiniteNoiseWorld.gd:684` ## Worker-thread safe: pass terrain edits captured on the main thread (no shared dict access).
- `0.2.8/world/InfiniteNoiseWorld.gd:686` # Isolation counter: in a complete baked world this must stay 0 for package cells.
- `0.2.8/world/InfiniteNoiseWorld.gd:701` ## Worker-thread safe: pass tile overrides captured on the main thread.
- `0.2.8/world/InfiniteNoiseWorld.gd:756` # Quantize to voxel-layer steps (each layer = WorldSettings.layer_height world units).
- `0.2.8/world/feature_visual_layer.gd:221` # Do not build vegetation/building nodes inside ChunkManager apply (measured
- `0.2.8/world/living_force.gd:15` ## Added to the equipped tool's dig_radius. [ / ] adjust this while a dig tool is held.
- `0.2.8/world/living_force.gd:24` ## Existing crystal near a dig or a new wall gains a little depth. Never seeds a new cell.
- `0.2.8/world/mesh_plan_cache.gd:595` # don't retain full quad arrays in log
- `0.2.8/world/world_state.gd:29` ## Session tombstones: baked static vegetation/features removed by dig/absorb/harvest.
- `0.2.8/world/world_state.gd:355` ## Apply legacy flat save-dict fields (terrain_edits/features/channels).
- `0.2.8/shaders/StructureCutaway.gdshader:3` // Same cone as helpers/camera_cutaway.gd and the terrain shaders: screen-door
- `0.2.8/shaders/StructureCutaway.gdshader:34` // Keep in sync with helpers/camera_cutaway.gd (T_MIN 0.05) and ChunkSurfaceMesh.gdshader.
- `0.2.8/shaders/crystal_pulse.gdshader:4` // A built-in TIME read would pulse without that bind, so the check would miss a stale material.
- `0.2.8/shaders/ChunkRamp.gdshader:4` // (ChunkView) discards non-axis faces and punched black diamonds in the
- `0.2.8/shaders/ChunkRamp.gdshader:5` // landing column. This shader always draws the wedge/corner.
- `0.2.8/shaders/ChunkRamp.gdshader:8` // Cave cutaway. Ramp geometry is unchanged. Keep in sync with helpers/camera_cutaway.gd.
- `0.2.8/shaders/ChunkRamp.gdshader:61` // Same near-black gate as ChunkSurfaceMesh. 0.04 flattened real tile texels.
- `0.2.8/shaders/water_surface.gdshader:3` // water_time is written on the material the water mesh draws. A built-in TIME
- `0.2.8/shaders/water_surface.gdshader:33` // 0.12 m crest. Visible at ortho 16, far below one 2 m layer.
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:3` // Face-authored shade (COLOR.b) plus a world-up hemisphere. Engine Lambert
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:9` // Cave cutaway. Keep in sync with helpers/camera_cutaway.gd and ChunkView.gdshader.
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:32` // Lambert black-out. Chunks are not rotated; NORMAL is world-ish.
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:72` // sample the black unused cells of Cube.png — those read as opaque black
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:77` // Near-black unused slots only. A 0.04 cutoff also matched the dark half of
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:79` // color, which reads as a grid at ortho 16.
- `0.2.8/shaders/ChunkView.gdshader:5` // Cave cutaway. Literals for the rim match helpers/camera_cutaway.gd (T_MIN 0.05).
- `0.2.8/shaders/ChunkView.gdshader:33` // This is before any view/model transforms, so directions are pure axis for our
- `0.2.8/shaders/ChunkView.gdshader:34` // scale-only instance transforms. Avoids using view-space NORMAL (which depends on
- `0.2.8/shaders/ChunkView.gdshader:35` // camera angle and was causing all faces to be discarded → white voxels).
- `0.2.8/shaders/ChunkView.gdshader:37` //   (prevents "bottom face appearing on a side face").
- `0.2.8/shaders/ChunkView.gdshader:39` // strict for pure axis normals after scaling
- `0.2.8/shaders/ChunkView.gdshader:40` // face_code is floor(...) + small frac from uv_h/100
- `0.2.8/shaders/ChunkView.gdshader:99` // Face-based pixel-art shading. Do not rely on Lambert for side faces —
- `0.2.4/project.godot:5` ; Format:
- `0.2.4/chunks/chunk_data.gd:18` # Legacy 3D paths (if any) will see AIR / false.
- `0.2.4/chunks/chunk_data.gd:76` # fallback; use uncached for thread safety (called from bg meshing)
- `0.2.4/chunks/chunk_manager.gd:120` # provides the underside with its own UV winding (fract repeat + atlas still
- `0.2.4/world/world_viewer.gd:615` # 1. Connected components via proximity (real fragmentation + longest connected feature span in world units)
- `0.2.4/world/InfiniteNoiseWorld.gd:303` # Pure compute path. Safe for background worker threads (never mutates caches).
- `0.2.4/world/InfiniteNoiseWorld.gd:397` # Use real noise (not a linear fmod hash) for the "random" breach decision so we don't get
- `0.2.4/shaders/ChunkView.gdshader:22` // This is before any view/model transforms, so directions are pure axis for our
- `0.2.4/shaders/ChunkView.gdshader:23` // scale-only instance transforms. Avoids using view-space NORMAL (which depends on
- `0.2.4/shaders/ChunkView.gdshader:24` // camera angle and was causing all faces to be discarded → white voxels).
- `0.2.4/shaders/ChunkView.gdshader:26` //   (prevents "bottom face appearing on a side face").
- `0.2.4/shaders/ChunkView.gdshader:28` // strict for pure axis normals after scaling
- `0.2.4/shaders/ChunkView.gdshader:29` // face_code is floor(...) + small frac from uv_h/100
- `crystalstorm0.2.0/project.godot:5` ; Format:
- `0.2.6/project.godot:5` ; Format:
- `0.2.6/crystal/crystal_manager.gd:1130` # Loaded chunk set from ChunkManager (façade gathers; sim never touches the tree).
- `0.2.6/crystal/crystal_manager.gd:1535` # Crystal never expands past the intentional playable map edge.
- `0.2.6/crystal/crystal_manager.gd:2230` # Missing key must not wipe live win targets (empty {} import used to clear all).
- `0.2.6/helpers/voxel_primitive_meshes.gd:4` ## +X = east, +Z = south, +Y = up.
- `0.2.6/helpers/voxel_primitive_meshes.gd:5` ## Ramp/corner/concave meshes include slopes plus back/floor/side fills (greedy skips these cells).
- `0.2.6/helpers/voxel_primitive_meshes.gd:6` ## Cardinal +Z ramps are derived from the west (toward-low-west) reference via axis transforms.
- `0.2.6/helpers/voxel_primitive_meshes.gd:126` ## Reference mesh: toward-low-west landing (high east back, side fills peak on east edge).
- `0.2.6/helpers/voxel_primitive_meshes.gd:157` ## Reference mesh: toward-low-west + toward-low-north corner (high WN, fills on east/south).
- `0.2.6/helpers/macro_terrain_perf_gate.gd:3` ## Frozen perf contract for macro vs legacy median comparison (probe must not redefine).
- `0.2.6/helpers/terrain_ramps.gd:96` # Only sloped walkable face + underside — no vertical box walls.
- `0.2.6/helpers/terrain_ramps.gd:125` # Winding must face +Y so the walkable top renders (was inverted).
- `0.2.6/helpers/voxel_types.gd:56` ## new_tile_set.tres / voxelsnew.png use a different 64 px strip layout — do not bind to ChunkView.
- `0.2.6/helpers/voxel_types.gd:67` ## Minecraft-style face picking: grass tops on FACE_TOP, dirt/earth on vertical sides, dirt underside.
- `0.2.6/helpers/chunk_data_pool.gd:43` # Never pool the same shell twice (double free / RefCounted corruption).
- `0.2.6/config/world_settings.gd:12` ## Hard cap on generated terrain height, measured in voxel layers (not world units).
- `0.2.6/config/world_settings.gd:61` ## Feet sit on top of the solid voxel column (surface_y + layer_height).
- `0.2.6/chunks/chunk_data.gd:15` ## Macro terrain authority (v2). Legacy maps are synced views for mesh/verify scripts.
- `0.2.6/chunks/chunk_data.gd:31` # Snapshotted on main thread before worker generation (avoids live WorldState races).
- `0.2.6/chunks/chunk_data.gd:36` ## Halo-region height deltas (world units), same dim as _halo_surface — worker-safe.
- `0.2.6/chunks/chunk_data.gd:50` ## Legacy bound — prefer WorldSettings.get_active().chunk_height_bound() for checks.
- `0.2.6/chunks/chunk_data.gd:59` # Legacy 3D paths (if any) will see AIR / false.
- `0.2.6/chunks/chunk_data.gd:200` # Read authority storage once; convert height layers → world units for workers.
- `0.2.6/chunks/chunk_data.gd:350` # Outside package bounds, or no valid bake: legacy noise (allowed for out-of-bounds).
- `0.2.6/chunks/chunk_data.gd:617` ## Dirty column = baked base (or legacy noise outside package) + frozen WorldState overlays.
- `0.2.6/chunks/chunk_data.gd:717` # Worker / post-capture path: never re-read live WorldState.
- `0.2.6/chunks/chunk_manager.gd:21` ## Main-thread applies per frame (legacy path when FrameBudgetScheduler absent).
- `0.2.6/chunks/chunk_manager.gd:86` # Mirrored from WorldBorder — worker threads cannot call class_name statics reliably.
- `0.2.6/chunks/chunk_manager.gd:289` # or engine shutdown corrupts heap (SIGSEGV mutex=0x1c0 / free invalid).
- `0.2.6/chunks/chunk_manager.gd:294` ## wait left handles for engine teardown to free twice / UAF.
- `0.2.6/chunks/chunk_manager.gd:313` ## Safe to remove_child + free views here. Must NOT be used from _exit_tree (double free).
- `0.2.6/chunks/chunk_manager.gd:338` # Explicit teardown: do not pool — free views we own while tree is live.
- `0.2.6/chunks/chunk_manager.gd:360` ## Children will be freed by the engine — DO NOT queue_free ChunkViews here
- `0.2.6/chunks/chunk_manager.gd:361` ## (that is the double-free root cause: parent frees children twice).
- `0.2.6/chunks/chunk_manager.gd:391` # Null MultiMesh refs so RID teardown is single-owner.
- `0.2.6/chunks/chunk_manager.gd:619` # edge stream jobs do not cold-load packages inside sample_base.
- `0.2.6/chunks/chunk_manager.gd:1189` # Worker path: never touch live world/registries for halo neighbors.
- `0.2.6/chunks/chunk_manager.gd:1850` # Do not recreate the pre-dig horizontal cap at natural_h (greedy top uses cur_h).
- `0.2.6/chunks/chunk_manager.gd:2233` # Finite world: do not stream/generate infinite terrain outside playable bounds.
- `0.2.6/chunks/chunk_manager.gd:2803` # Do not null data.world here: regen reuses view.chunk_data and concurrent main-thread
- `0.2.6/chunks/chunk_manager.gd:2804` # rebuild enqueue can race a still-running or just-finished worker if world is cleared early.
- `0.2.6/chunks/chunk_manager.gd:2810` ## True when a completed mesh job must not be applied (token or WorldState mesh stamp).
- `0.2.6/chunks/chunk_manager.gd:2834` # Reap pool task id first (wait_for_task_completion). Must not only erase.
- `0.2.6/chunks/chunk_manager.gd:2862` # Worker-stage attribution only (must not count as main-thread tracked).
- `0.2.6/chunks/chunk_view.gd:71` # IMPORTANT: Do NOT remove_child/queue_free LayerContainer children here.
- `0.2.6/chunks/chunk_view.gd:72` # queue_free of those Multimesh nodes here was a proven double-free
- `0.2.6/chunks/chunk_view.gd:73` # (glibc: "double free or corruption (!prev)").
- `0.2.6/chunks/chunk_view.gd:74` # Only detach MultiMesh Resource refs so RID ownership is single-path.
- `0.2.6/chunks/chunk_view.gd:396` ## Prevents heap corruption when stream-unload races the main-thread upload drain.
- `0.2.6/chunks/voxel_world.gd:26` # Legacy path without composition root.
- `0.2.6/chunks/chunk_pipeline.gd:41` # Full-world bake: never procedural-generate static terrain in package bounds.
- `0.2.6/chunks/chunk_pipeline.gd:232` ## Full worker path: column → mesh → buffer. Host must not use shared manager scratch.
- `0.2.6/systems/spatial_query_layer.gd:25` ## Default grid cell size in world units (XZ). ChunkData.SIZE is 16; half is a good default.
- `0.2.6/systems/combat_visual_feedback.gd:71` # Bind handles once; do not regenerate combat textures on every handoff.
- `0.2.6/systems/save_game_service.gd:134` # Seal after all fields present; re-seal after validate so on-disk checksum matches load.
- `0.2.6/systems/save_game_service.gd:260` # Migrated/legacy flat path
- `0.2.6/systems/game_visual_registry.gd:11` ## World units per texture pixel (= voxel_scale * factor in 0.025–0.04 band).
- `0.2.6/systems/game_visual_registry.gd:135` ## Back-compat alias — do not block on ChunkManager (avoids VoxelWorld deadlock).
- `0.2.6/systems/game_visual_registry.gd:172` # Reuse session textures — never regenerate the full bundle on refresh.
- `0.2.6/systems/perf_profiler.gd:5` ## Worker-attributed stages (completed off-main). Must NOT reduce main-thread untracked.
- `0.2.6/systems/perf_profiler.gd:145` # Godot 4 Performance monitors (bytes).
- `0.2.6/systems/perf_profiler.gd:156` ## or Godot double-frees the Callable lambdas on engine shutdown
- `0.2.6/systems/perf_profiler.gd:157` ## ("double free or corruption (!prev)" / "free(): invalid pointer").
- `0.2.6/systems/perf_profiler.gd:684` # Leaf record: pause parent exclusive so we don't double-count wall into parent.
- `0.2.6/systems/perf_profiler.gd:884` # Prefer exclusive only. Do not fall back to inclusive last_us for
- `0.2.6/systems/perf_profiler.gd:913` # Cap named to wall (mis-nested timers must not invent >100%).
- `0.2.6/systems/performance_service.gd:88` # Do NOT mutate authored world_gen.caves_enabled — quality is policy-only.
- `0.2.6/systems/performance_service.gd:209` # Authored WorldGenConfig is not mutated by quality (composition policy).
- `0.2.6/systems/save_schema.gd:3` ## schema_version 1 = legacy flat terrain_edits/features/channels
- `0.2.6/systems/save_schema.gd:4` ## schema_version 2 = world_state authority block + revisions + integrity
- `0.2.6/systems/runtime_config_resolver.gd:5` ## Quality never mutates authored WorldGenConfig as sim authority; caves_enabled lives on the policy.
- `0.2.6/systems/runtime_config_resolver.gd:46` # Authored sim config is referenced, not mutated by quality.
- `0.2.6/systems/runtime_config_resolver.gd:52` # *runtime* cave rendering/query without rewriting the resource.
- `0.2.6/weapons/weapon_controller.gd:324` # Don't steal R/interact while a terminal win/lose panel is up (restart uses interact).
- `0.2.6/player/voxel_floor_probe.gd:18` ## Disable with CRYSTALSTORM_PLAYER_HEIGHT_CACHE=0 for A/B measurement.
- `0.2.6/player/voxel_floor_probe.gd:406` # Large steps settle faster so ledges don't feel floaty; micro deltas ease in.
- `0.2.6/player/player.gd:498` # Fully blocked: kill residual velocity into the wall so we don't jitter.
- `0.2.6/player/action_targeting.gd:84` # Empty streamer (or unit probes): do not treat the world as unloaded for targeting.
- `0.2.6/player/action_targeting.gd:169` # Spatial index stores world-space positions (voxel_scale); probe must match.
- `0.2.6/player/action_targeting.gd:191` # Do not early-return empty: fall through to group scan if index is cold.
- `0.2.6/player/action_targeting.gd:307` # Always lock the column under the mouse when in range — solid checks must not
- `0.2.6/entities/crystal_enemy_spawner.gd:86` # Column-space distance (depth map is keyed by column, not world units).
- `0.2.6/entities/crystal_enemy_spawner.gd:103` # Don't dump a death burst during early orientation grace.
- `0.2.6/fluids/voxel_fluid_service.gd:161` # Natural river beds stay sources; don't register/unregister them as player channels.
- `0.2.6/world/world_bake_service.gd:7` ## Disk layout (v4):
- `0.2.6/world/world_bake_service.gd:9` ##     world.index          — lightweight bounds + flags (only thing loaded at startup)
- `0.2.6/world/world_bake_service.gd:11` ##     static_meta.json     — optional non-authoritative placement hints
- `0.2.6/world/world_bake_service.gd:16` ## (feature_cleared tombstones prevent re-applying destroyed plants).
- `0.2.6/world/world_bake_service.gd:17` ## Never procedural-generates static terrain/vegetation for coords covered by a valid index.
- `0.2.6/world/world_bake_service.gd:83` ## Runtime isolation counters (baked world must stay at 0 for in-package cells).
- `0.2.6/world/world_bake_service.gd:150` ## Returns {} if outside package or package unavailable (caller must not noise for covered cells).
- `0.2.6/world/world_bake_service.gd:161` ## Compose quantized surface from baked base + WorldState height delta (world units).
- `0.2.6/world/world_bake_service.gd:285` ## Mask to unsigned 32-bit for store_32 / get_32 checksum compare.
- `0.2.6/world/world_bake_service.gd:1004` ## (re-installing veg packages must not force plan repair every boot).
- `0.2.6/world/world_bake_service.gd:1243` # Do not keep per-chunk data in RAM after bake.
- `0.2.6/world/world_bake_service.gd:1518` # Terrain+veg counts checksum (store_var payloads validated by size + load success).
- `0.2.6/world/world_bake_service.gd:2144` # checksum ignored for legacy
- `0.2.6/world/world_viewer.gd:615` # 1. Connected components via proximity (real fragmentation + longest connected feature span in world units)
- `0.2.6/world/feature_registry.gd:117` # Session tombstone so streamed baked vegetation is not re-installed.
- `0.2.6/world/world_features.gd:219` ## must not wait for a fully validated bake — only decide if packages will supply veg.
- `0.2.6/world/world_features.gd:287` # Prefer composition-resolved policy when available so legacy path
- `0.2.6/world/town_manager.gd:140` # Heights are in current world units (voxel_scale), not legacy 0–158.
- `0.2.6/world/world_visuals.gd:99` # Do not refresh all layers on every chunk_ready — that path regenerated the
- `0.2.6/world/channel_registry.gd:3` ## Water is the primary fluid (water_level / flow_dir — save-compatible).
- `0.2.6/world/town_defense_manager.gd:132` ## Production content / harness: put a town under pressure without rewriting crystal sim.
- `0.2.6/world/InfiniteNoiseWorld.gd:439` # Pure compute path. Safe for background worker threads (never mutates caches).
- `0.2.6/world/InfiniteNoiseWorld.gd:640` ## Worker-thread safe: pass terrain edits captured on the main thread (no shared dict access).
- `0.2.6/world/InfiniteNoiseWorld.gd:642` # Isolation counter: in a complete baked world this must stay 0 for package cells.
- `0.2.6/world/InfiniteNoiseWorld.gd:656` ## Worker-thread safe: pass tile overrides captured on the main thread.
- `0.2.6/world/InfiniteNoiseWorld.gd:711` # Quantize to voxel-layer steps (each layer = WorldSettings.layer_height world units).
- `0.2.6/world/feature_visual_layer.gd:204` # Do not build vegetation/building nodes inside ChunkManager apply (measured
- `0.2.6/world/mesh_plan_cache.gd:582` # don't retain full quad arrays in log
- `0.2.6/world/world_state.gd:29` ## Session tombstones: baked static vegetation/features removed by dig/absorb/harvest.
- `0.2.6/world/world_state.gd:351` ## Apply legacy flat save-dict fields (terrain_edits/features/channels).
- `0.2.6/shaders/ChunkView.gdshader:22` // This is before any view/model transforms, so directions are pure axis for our
- `0.2.6/shaders/ChunkView.gdshader:23` // scale-only instance transforms. Avoids using view-space NORMAL (which depends on
- `0.2.6/shaders/ChunkView.gdshader:24` // camera angle and was causing all faces to be discarded → white voxels).
- `0.2.6/shaders/ChunkView.gdshader:26` //   (prevents "bottom face appearing on a side face").
- `0.2.6/shaders/ChunkView.gdshader:28` // strict for pure axis normals after scaling
- `0.2.6/shaders/ChunkView.gdshader:29` // face_code is floor(...) + small frac from uv_h/100
- `yweauh-2/project.godot:5` ; Format:
- `0.2.5/project.godot:5` ; Format:
- `0.2.5/helpers/terrain_ramps.gd:135` # Winding must face +Y so the walkable top renders (was inverted).
- `0.2.5/config/world_settings.gd:12` ## Hard cap on generated terrain height, measured in voxel layers (not world units).
- `0.2.5/config/world_settings.gd:61` ## Feet sit on top of the solid voxel column (surface_y + layer_height).
- `0.2.5/chunks/chunk_data.gd:16` # Snapshotted on main thread before worker generation (avoids TerrainEdits/FeatureRegistry races).
- `0.2.5/chunks/chunk_data.gd:26` ## Legacy bound — prefer WorldSettings.get_active().chunk_height_bound() for checks.
- `0.2.5/chunks/chunk_data.gd:33` # Legacy 3D paths (if any) will see AIR / false.
- `0.2.5/chunks/chunk_manager.gd:40` # Mirrored from WorldBorder — worker threads cannot call class_name statics reliably.
- `0.2.5/chunks/chunk_manager.gd:346` # Worker path: never touch live world/registries for halo neighbors.
- `0.2.5/world/world_viewer.gd:615` # 1. Connected components via proximity (real fragmentation + longest connected feature span in world units)
- `0.2.5/world/InfiniteNoiseWorld.gd:416` # Pure compute path. Safe for background worker threads (never mutates caches).
- `0.2.5/world/InfiniteNoiseWorld.gd:525` ## Worker-thread safe: pass terrain edits captured on the main thread (no shared dict access).
- `0.2.5/world/InfiniteNoiseWorld.gd:532` ## Worker-thread safe: pass tile overrides captured on the main thread.
- `0.2.5/world/InfiniteNoiseWorld.gd:587` # Quantize to voxel-layer steps (each layer = WorldSettings.layer_height world units).
- `0.2.5/shaders/ChunkView.gdshader:22` // This is before any view/model transforms, so directions are pure axis for our
- `0.2.5/shaders/ChunkView.gdshader:23` // scale-only instance transforms. Avoids using view-space NORMAL (which depends on
- `0.2.5/shaders/ChunkView.gdshader:24` // camera angle and was causing all faces to be discarded → white voxels).
- `0.2.5/shaders/ChunkView.gdshader:26` //   (prevents "bottom face appearing on a side face").
- `0.2.5/shaders/ChunkView.gdshader:28` // strict for pure axis normals after scaling
- `0.2.5/shaders/ChunkView.gdshader:29` // face_code is floor(...) + small frac from uv_h/100

### Next sentence of a kept constraint (same comment block)

- `crystalstorm0.2.2/shaders/ChunkView.gdshader:3` // Turning off depth tracking completely stops the invisible outer corners of your cards
- `0.2.8/main.gd:83` ## is the only chance to write the alive snapshot before the process ends.
- `0.2.8/crystal/crystal_manager.gd:544` # Floor heights change with dig/build — rebuild nearby crystal meshes so clusters
- `0.2.8/crystal/crystal_manager.gd:2090` ## Crystal top only. -INF when the column has no walkable crystal, so callers
- `0.2.8/crystal/crystal_fluid_sim.gd:622` # leave its mass on the opposite parity — the checkerboard blink.
- `0.2.8/ui/game_overlay.gd:602` # Map-wide percent rounds to 0.0% for thousands of cells; live tile count is
- `0.2.8/ui/game_overlay.gd:604` # the 0.0% that made the threat look absent.
- `0.2.8/ui/hotbar.gd:56` # also moves this bar to the front of the canvas while it is open.
- `0.2.8/helpers/world_visual_coords.gd:5` ## and never treat voxel_position.x as a world-space metre.
- `0.2.8/config/world_settings.gd:102` ## (about a Minecraft player). Radius is half the scout's body width, and that
- `0.2.8/config/world_settings.gd:103` ## width scales with height (opaque art is 16×34, not the padded 32×48 canvas).
- `0.2.8/chunks/chunk_data.gd:697` # the floor under them. Feature tile overrides (water replace, paths,
- `0.2.8/chunks/chunk_data.gd:698` # farmland) apply even when height is unchanged.
- `0.2.8/chunks/chunk_data.gd:1005` ## change the column the mesh plan was stored against.
- `0.2.8/chunks/chunk_manager.gd:323` # Required: every WorkerThreadPool task id must be waited exactly once
- `0.2.8/chunks/chunk_manager.gd:328` ## Godot requires wait_for_task_completion for each add_task id; erasing without
- `0.2.8/chunks/chunk_manager.gd:653` # Always warm the ring even when the target is *outside* package bounds so
- `0.2.8/chunks/chunk_manager.gd:1352` ## (that is the second slope immediately off the first landing).
- `0.2.8/chunks/chunk_manager.gd:1873` # mid-heights — that kept the old terrain visible in the pit. The new
- `0.2.8/chunks/chunk_manager.gd:1874` # floor is the column FACE_TOP; pit walls are neighbor side faces.
- `0.2.8/chunks/chunk_manager.gd:2028` # is re-derived deterministically from reachable samples. Non-ramp
- `0.2.8/chunks/chunk_manager.gd:2029` # columns always fill — any far cut exposes this face, and a solid far
- `0.2.8/chunks/chunk_manager.gd:2030` # cell just buries the quad. Ramp-owned columns fill only against a
- `0.2.8/chunks/chunk_manager.gd:2031` # crossing far slope: a parallel far cardinal shares this column's
- `0.2.8/chunks/chunk_manager.gd:2660` # Terrain + ramp + corner + diagonal can queue together; 1/frame left
- `0.2.8/chunks/chunk_manager.gd:2784` # override an interior column the walk mesh was built from.
- `0.2.8/chunks/chunk_manager.gd:3637` ## pay capture_worker_snapshot / enqueue N times for N edits in one frame.
- `0.2.8/systems/player_settings.gd:237` # quality_preset / render_distance from player_settings.json.
- `0.2.8/systems/game_visual_registry.gd:488` # Authored walls are in column units (width ≈ 1). XZ fill the column;
- `0.2.8/systems/perf_profiler.gd:155` ## Monitor ids registered with Performance — must be removed before autoload free
- `0.2.8/systems/perf_profiler.gd:885` # envelopes (inclusive would double-count nested leaves into Unknown).
- `0.2.8/systems/held_item_view.gd:238` ## camera sees a side, not a paper edge.
- `0.2.8/systems/save_schema.gd:5` ## Terrain overlay contract (macro/micro):
- `0.2.8/systems/save_schema.gd:6` ## - Persist only WorldState height_delta / build_tile (and features/channels).
- `0.2.8/systems/save_schema.gd:7` ## - Micro bricks are runtime-derived from overlays on generate/rebuild — never saved.
- `0.2.8/systems/save_schema.gd:8` ## - v1→v2 migration lifts flat terrain_edits into world_state; load rebuild re-derives micro.
- `0.2.8/systems/runtime_config_resolver.gd:3` ## Explicit configuration precedence:
- `0.2.8/systems/runtime_config_resolver.gd:4` ##   author defaults → project/authored config → quality preset → platform overrides → runtime debug overrides
- `0.2.8/systems/runtime_config_resolver.gd:51` # Authored world_gen may declare caves for generation; quality policy may disable
- `0.2.8/systems/crystal_texture_generator.gd:176` # upscale them. A smaller file is ignored rather than stretched up.
- `0.2.8/systems/juice.gd:3` ## Gameplay hit-stop and shake no-op when DisplayServer.get_name() == "headless"
- `0.2.8/weapons/weapon_controller.gd:1027` # Dig, place, and herb already resolved. Play the swing from the ready pose
- `0.2.8/player/voxel_floor_probe.gd:489` # so the step test refuses entering that column. A body already inside can
- `0.2.8/player/player.gd:258` # Publish the alive-quit column before the stream wait. ChunkManager follows
- `0.2.8/player/action_targeting.gd:13` ## a cell center is not stolen by a neighbor.
- `0.2.8/player/action_targeting.gd:334` # discard the pick (missed digs/placements). try_dig/try_build validate later.
- `0.2.8/assets/structures/bridge/author_bridge.gd:3` ## cap on raised-over-dig terrain, not a wall, gate, or floor tile.
- `0.2.8/assets/structures/town_hall/author_town_hall.gd:3` ## with a pitched roof, not a wall, gate, pillar, or deck.
- `0.2.8/assets/structures/gate/author_gate.gd:3` ## raise terrain, so this is a full-height arch, not a short wall cap.
- `0.2.8/assets/structures/ruin_pillar/author_ruin_pillar.gd:3` ## column, not a wall cap and not a gate arch.
- `0.2.8/assets/tiles/author_grass_dirt_variants.gd:33` ## use, so the non-fill mask cannot repeat for four rows.
- `0.2.8/fluids/voxel_fluid_service.gd:90` # Only registered water expands to neighbors. Natural river tiles are visual
- `0.2.8/fluids/voxel_fluid_service.gd:410` # wave stops on the first empty column past a pool.
- `0.2.8/fluids/voxel_fluid_service.gd:419` # them here would erase the pool on every capped frame.
- `0.2.8/world/world_bake_service.gd:1751` ## Count world-seeded tile stamps that affect mesh plans, excluding baked-static vegetation
- `0.2.8/world/validation_yard.gd:85` ## Four model-A landings whose plateau, landing, and 8-cell terrace all sit
- `0.2.8/world/validation_yard.gd:86` ## inside the one chunk that contains `origin`. East/west share the high z
- `0.2.8/world/validation_yard.gd:88` ## each other or off the chunk (halo samples would reject the cardinal).
- `0.2.8/world/world_features.gd:222` ## Runtime scatter is a legacy fallback. Production streams plants from bake packages
- `0.2.8/world/world_features.gd:223` ## (WorldBakeService v4+). Feature seed runs *before* ChunkManager bootstrap, so we
- `0.2.8/world/world_features.gd:293` # still honors platform/debug overrides.
- `0.2.8/world/terrain_editor.gd:634` # the supporting terrain under a WorldObject-only wall/gate/bridge.
- `0.2.8/world/world_visuals.gd:100` # full texture bundle and repopulated every feature chunk (multi-ms hitch).
- `0.2.8/world/InfiniteNoiseWorld.gd:7` # Bake jobs sample this node on the thread pool. Join them before the
- `0.2.8/world/feature_visual_layer.gd:222` # ~9ms of _on_chunk_ready after setup was only ~0.75ms). Queue for budgeted drain.
- `0.2.8/shaders/StructureCutaway.gdshader:4` // rim, keep fragments at or below the feet. Globals are written once per frame
- `0.2.8/shaders/StructureCutaway.gdshader:5` // by player/camera.gd. Cast shadow stays off on the MeshInstance3D.
- `0.2.8/shaders/ChunkRamp.gdshader:3` // Ramps are custom meshes with sloped normals. The voxel face-select shader
- `0.2.8/shaders/water_surface.gdshader:4` // read would move even when that bind is missing.
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:4` // with a single directional light blacks any face away from the sun — unusable
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:5` // at the iso camera. Unshaded fill never drops a readable terrain/ramp face
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:6` // to black. cull_disabled keeps 45° slopes visible from both sides.
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:31` // Fake iso key light so slopes, tops, and vertical cuts read apart without
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:71` // Out-of-range COLOR (missing vertex color / empty atlas slot) used to
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:73` // holes, not missing geometry.
- `0.2.8/shaders/ChunkSurfaceMesh.gdshader:78` // real tiles (grass sits on that line) and replaced them with one flat
- `0.2.8/shaders/ChunkView.gdshader:36` // - No leakage: e.g. a lip box's own top/bottom (Y normals) or ends never render
- `0.2.8/shaders/ChunkView.gdshader:100` // the iso camera leaves them nearly black under a single key light.
- `0.2.4/chunks/chunk_manager.gd:119` # uv_w/uv_h same for bottom (face_code=2) as top (0); the BoxMesh -Y face
- `0.2.4/chunks/chunk_manager.gd:121` # produces consistent texturing across faces).
- `0.2.4/world/InfiniteNoiseWorld.gd:398` # diagonal stripes of stone/cave-mouth tiles vs normal biome tiles.
- `0.2.4/shaders/ChunkView.gdshader:25` // - No leakage: e.g. a lip box's own top/bottom (Y normals) or ends never render
- `0.2.6/chunks/chunk_manager.gd:288` # Required: every WorkerThreadPool task id must be waited exactly once
- `0.2.6/chunks/chunk_manager.gd:293` ## Godot requires wait_for_task_completion for each add_task id; erasing without
- `0.2.6/chunks/chunk_manager.gd:618` # Always warm the ring even when the target is *outside* package bounds so
- `0.2.6/systems/perf_profiler.gd:155` ## Monitor ids registered with Performance — must be removed before autoload free
- `0.2.6/systems/perf_profiler.gd:885` # envelopes (inclusive would double-count nested leaves into Unknown).
- `0.2.6/systems/save_schema.gd:5` ## Terrain overlay contract (macro/micro):
- `0.2.6/systems/save_schema.gd:6` ## - Persist only WorldState height_delta / build_tile (and features/channels).
- `0.2.6/systems/save_schema.gd:7` ## - Micro bricks are runtime-derived from overlays on generate/rebuild — never saved.
- `0.2.6/systems/save_schema.gd:8` ## - v1→v2 migration lifts flat terrain_edits into world_state; load rebuild re-derives micro.
- `0.2.6/systems/runtime_config_resolver.gd:3` ## Explicit configuration precedence:
- `0.2.6/systems/runtime_config_resolver.gd:4` ##   author defaults → project/authored config → quality preset → platform overrides → runtime debug overrides
- `0.2.6/systems/runtime_config_resolver.gd:51` # Authored world_gen may declare caves for generation; quality policy may disable
- `0.2.6/player/action_targeting.gd:308` # discard the pick (missed digs/placements). try_dig/try_build validate later.
- `0.2.6/world/world_bake_service.gd:1003` ## Count world-seeded tile stamps that affect mesh plans, excluding baked-static vegetation
- `0.2.6/world/world_features.gd:217` ## Runtime scatter is a legacy fallback. Production streams plants from bake packages
- `0.2.6/world/world_features.gd:218` ## (WorldBakeService v4+). Feature seed runs *before* ChunkManager bootstrap, so we
- `0.2.6/world/world_features.gd:288` # still honors platform/debug overrides.
- `0.2.6/world/world_visuals.gd:100` # full texture bundle and repopulated every feature chunk (multi-ms hitch).
- `0.2.6/world/feature_visual_layer.gd:205` # ~9ms of _on_chunk_ready after setup was only ~0.75ms). Queue for budgeted drain.
- `0.2.6/shaders/ChunkView.gdshader:25` // - No leakage: e.g. a lip box's own top/bottom (Y normals) or ends never render
- `0.2.5/shaders/ChunkView.gdshader:25` // - No leakage: e.g. a lip box's own top/bottom (Y normals) or ends never render
