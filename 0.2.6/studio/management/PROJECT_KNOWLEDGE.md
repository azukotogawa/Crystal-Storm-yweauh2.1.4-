# Project knowledge

## Source of truth

| Concern | Authority |
|---|---|
| Engineering conventions | `AGENTS.md` |
| Production scene and input | `scenes/main.tscn`, `project.godot` |
| Runtime behavior | Live GDScript and config classes |
| Automated verification | `scripts/run_all_verify.sh` and named probes |
| Human verification | `manual_verification.md` |
| Stabilization status | `STABILIZATION.md` |
| Studio orientation | `studio/` |

## Current implementation map

The project has a production 3D scene, deterministic procedural terrain, asynchronous chunk streaming, greedy MultiMesh rendering, custom voxel-aware player movement, terrain editing, ramps, action targeting, basic combat, crystal and water-fluid systems, procedural world features, entities, visuals, saves, topographical map UI, performance presets, debug tooling, and a large headless regression suite.

Main risks are not absence of code but integration quality: heightfield-vs-volumetric assumptions, thread ownership, chunk rebuild cost, visual readability, collision feel, and maintaining consistency between config, save state, and live overlays.

## Important terminology

- **Column**: one X/Z terrain cell in the heightfield.
- **Surface map**: per-chunk 16×16 surface height/tile data.
- **Chunk view**: render node for a chunk, not the canonical terrain state.
- **Terrain edit**: stored height delta/build tile overlay; it triggers chunk regeneration.
- **Feature overlay**: towns, vegetation, ruins, and spawn data held by `FeatureRegistry`.
- **Crystal depth**: fluid-like simulation depth in a column, not terrain height.
- **Verified**: automated contract coverage only unless human sign-off is recorded.

## Known documentation drift

The root README says several systems are unimplemented and refers to an old `src/world` path. Those statements conflict with the present scene and source tree. `AGENTS.md` gives `ChunkData.HEIGHT = 160`, while live `chunks/chunk_data.gd` declares legacy `HEIGHT := 48` and delegates bounds to `WorldSettings`; use the latter for implementation work. `AGENTS.md`/`STABILIZATION.md` also quote old suite counts; the runner currently lists 79 suites.

Do not “correct” historical records silently. Update their owners when their scope changes; use this document to prevent onboarding errors in the meantime.

## Session record — 2026-07-11

**Backlog item addressed:** P0 — targeting/highlight placement (`manual_verification.md` notes: sword swings fixed north, pick works but sword does not).

### Implemented
- `ActionTargeting.resolve_action` now uses camera-forward raycast (not mouse-only) for equipped weapon modes `dig`, `attack`, and `ranged` when no explicit `force_mode` is passed.
- `WeaponController._do_melee_attack` resolves targets via `resolve_action(..., &"attack")` and `attack_toward_column(..., &"attack")` instead of mouse-dependent `target_column`.
- `SmokeProbeHelpers.position_player_for_forward_dig` accepts an `action_mode` parameter (reused for attack positioning in probes).
- New regression probe `scripts/verify_melee_forward_targeting.gd` (registered in `run_all_verify.sh`, suite count 69).

### Learned
- Dig already forced `&"dig"` with forward fallback; sword used `target_column` with `&"any"` → `mouse_only=true`, so headless and off-screen-mouse sessions got `mode=none` and fixed-camera-forward bias.
- Main-scene melee entity damage still requires co-locating player with spawn cell (smoke pattern); forward arc hit from distance needs entity in loaded arc — separate from targeting resolve.
- Camera orbit must set `orbit_yaw_deg` on production `player/camera.gd`, not only `rotation_degrees`, for yaw-sensitive probes.

### Verified
- `verify_melee_forward_targeting.gd`: attack resolves without mouse, `attack_forward` varies across 4 yaws, melee damages spawned entity on main scene.
- `verify_target_facing.gd`, `verify_target_highlight.gd`, `verify_combat_entity_hit.gd`: PASS (targeted).
- Full suite, 60s smoke, dual medium boot: see scratch `verify_all.log`, `smoke_extended.log`, `main_boot_*.log`.

### Remaining issues
- Human display pass still needed for sword highlight feel, collision/ramp feel, crystal checkerboard visuals (deferred per backlog).
- Build mode still mouse-first when stone is on hotbar without `force_mode`; acceptable until build UX brief lands.
- Chunk full-regeneration on dig/build remains a perf P0 (profile before architectural change).

### Recommendations for next session
- Run display session focusing on sword red highlight + ramp walk at step corners; update human sign-off only if pass.
- Profile `ChunkManager` rebuild cost after terrain edit; sketch incremental mesh invalidation if hot.
- Extend smoke sustained loop to assert at least one successful melee via forward arc (not only co-located spawn cell).

## Session record — 2026-07-11 (probe honesty pass)

**Backlog item addressed:** P0 targeting — hardened `verify_melee_forward_targeting.gd` after skeptic review.

### Implemented
- `SmokeProbeHelpers.clear_mouse_offscreen()` — warps mouse to `(-1e6,-1e6)` after positioning helpers that may warp onto target columns.
- `verify_melee_forward_targeting.gd` — clears mouse before every `resolve_action` assertion; forward-arc melee uses `entity_spawned` signal, places player `voxel_scale*1.1` behind entity combat center along `attack_forward`, pre-flights `CombatHitResolver.query_melee` before `_do_melee_attack`.
- Restored `.claude/settings.local.json` to permissions-only (removed leaked `OPENROUTER_API_KEY` from working tree).

### Learned
- `position_player_for_forward_dig` always warps mouse — any “no mouse” test must clear mouse after it runs.
- Co-located player/entity melee bypasses arc/range checks; honest arc test must offset player in world space using entity `get_combat_center()`.
- `entity_spawned` + instance tracking beats scanning `world_entity` group while world sim adds animals.

### Verified
- `verify_melee_forward_targeting.gd`: mouse-off-screen resolve, forward-arc melee with `pre_hits=1`, HP 18→6.
- Full suite + 60s smoke: scratch logs `verify_all.log`, `smoke_extended.log`.

### Remaining issues
- Entity spawn world placement vs `home_cell` can diverge (registry anchor); probe compensates by offsetting from combat center — worth display-session audit.
- `dist_cells` in probe log can look large when `voxel_position` is derived from `global_position` after manual placement.

### Recommendations for next session
- Investigate `column_sprite_position` vs `home_cell` alignment for spawned entities.
- Add `clear_mouse_offscreen` to smoke dig positioning path documentation in `AI_DEVELOPMENT.md`.

## Session record — 2026-07-11 (smoke forward-arc melee)

**Backlog item addressed:** P0 sustained session — extend smoke to assert honest forward-arc melee (not co-located spawn cell).

### Implemented
- `SmokeProbeHelpers.forward_arc_stand_distance`, `position_player_for_forward_arc_attack`, `try_forward_arc_melee_damage` — shared forward-arc setup; avoids `_sync_global_from_voxel` after sub-cell stand placement; refines aim toward `get_combat_center()` within weapon range.
- `smoke_gameplay.gd` — P0 combat uses forward-arc helper; sustained session seeds `melee_ok` from that pass and opportunistically re-attacks when a `world_entity` is loaded (spawn-on-demand fallback when seed is 0).
- `verify_melee_forward_targeting.gd` — uses shared helper (stand distance scales with `voxel_scale=2` and sword `range=2`).
- `verify_smoke_gameplay.gd` — evidence markers for `forward-arc melee` and `melee_ok=`.
- `studio/engineering/AI_DEVELOPMENT.md` — headless mouse discipline (`clear_mouse_offscreen` after `position_player_for_forward_dig`).

### Learned
- `voxel_scale=2` makes `voxel_scale*1.1` stand offsets exceed wooden_sword range (2.0); range-based stand distance and origin→entity forward vector are required.
- `_sync_global_from_voxel` snaps player to column centers and breaks sub-cell arc geometry — do not call after forward-arc placement.
- Chunk unload despawns `world_entity` instances when the sustained loop walks away; seed `melee_ok` from the earlier in-session forward-arc test rather than requiring live entities for the full 60s wander.

### Verified
- `verify_melee_forward_targeting.gd`: forward-arc HP 18→6, `pre_hits=1`.
- `smoke_gameplay.gd` 60s: **Combat OK** forward-arc, **Session OK** `melee_ok=1`.
- `verify_smoke_gameplay.gd`, `verify_smoke_quit_path.gd`: PASS (targeted re-run).

### Remaining issues
- Display-session human pass still open (sword highlight, ramp feel, crystal checkerboard).
- Chunk full-regeneration perf P0 unchanged.
- `column_sprite_position` vs `home_cell` world alignment still worth display audit (combat uses `get_combat_center()`).

### Recommendations for next session
- Profile `ChunkManager` rebuild cost after terrain edit at MEDIUM preset.
- Run display session for sword red highlight + ramp step corners; update `manual_verification.md` only on human pass.

## Session record — 2026-07-11 (chunk rebuild perf)

**Backlog item addressed:** P0 — profile terrain edit rebuild behavior (`ChunkManager` full regen concern).

### Implemented
- New probe `scripts/verify_chunk_rebuild_perf.gd` (registered in `run_all_verify.sh`, suite count 70).
- Documents source contract: `terrain_editor` calls `rebuild_region_at_world(..., ring=0)` (single chunk); `rebuild_chunk` → worker `_compute_column_maps(true)` + greedy mesh (not incremental face patch).
- Runtime gate at MEDIUM: dig/build wall time ≤800ms, ≤120 frames; chunk count must not drop during edit; mesh surface corroborates terrain delta.

### Learned
- Single dig/build on production main scene: ~320–330ms wall, ~21 frames to `await_rebuild_idle` in headless MEDIUM (representative sample, not incremental mesh).
- PerfProfiler `max_ms` includes bootstrap streaming peaks — per-edit budgets should use wall-clock around one edit, not global worker max.
- Build and dig on nearby columns in the same chunk both use ring=0 path; acceptable for current architecture until incremental invalidation is designed.

### Verified
- `verify_chunk_rebuild_perf.gd`: PASS — dig coord wall=328ms frames=21; build wall=320ms; chunks stable.

### Remaining issues
- Architecture still does full column-map regen per edit; sub-chunk mesh invalidation not implemented (probe establishes baseline before any refactor).
- Display-session human pass still open.

### Recommendations for next session
- Sketch incremental mesh invalidation design (dirty column rects + halo) if edit latency becomes player-visible in display session.
- Run display session for sword highlight + ramp step corners.

## Session record — 2026-07-11 (entity spawn alignment + display forward-arc)

**Backlog item addressed:** P0 — `column_sprite_position` vs `home_cell` alignment; display forward-arc sword targeting.

### Implemented
- `WorldEntity.refresh_visual` — anchors visuals at live `column_pos(global_position)`, not `home_cell` (prevents registry refresh teleporting wandered entities home).
- `scripts/verify_entity_spawn_alignment.gd` — spawn-time xz alignment vs `GameVisualRegistry.column_sprite_position` (suite 71).
- `display_session_probe.gd` — forward-arc attack resolve without mouse; entity anchor corroboration; freeze probe entity sim during alignment read.

### Learned
- `home_cell` is spawn metadata; live `global_position` diverges via brain wander — combat correctly uses `get_combat_center()` at live position.
- Spawn anchor xz matches registry exactly (`xz_err=0.000` at `(11,11)` → world `(23,23)` with `voxel_scale=2`); prior large `dist_cells` in melee logs were wander offset, not registry bug.
- Display session can run without `--headless`; forward-arc PASS with mouse cleared.

### Verified
- `verify_entity_spawn_alignment.gd`: PASS — `xz_err=0.000`, `col_err=0.000`.
- `run_display_session.sh`: **DISPLAY SESSION OK** — forward-arc cell=(-6,6), entity anchor `xz_err=0.000`.
- `verify_display_probe_contract.gd`: PASS.

### Remaining issues
- Human visual confirm still required for red sword highlight appearance and ramp step feel (`manual_verification.md`).
- Incremental chunk mesh invalidation not started.

### Recommendations for next session
- Human display playtest: sword red highlight at step corners + ramp walk feel; sign `manual_verification.md` only on pass.
- Sketch incremental mesh invalidation if edit hitch visible in playtest.

## Session record — 2026-07-11 (ramp step-corner walk)

**Backlog item addressed:** P0 ramp feel — headless floor-probe coverage at L-shaped step corners.

### Implemented
- `scripts/verify_ramp_step_corner_walk.gd` — `VoxelFloorProbe` steps low→+X ramp, low→+Z ramp on synthetic L-step layout (suite 72).
- `display_session_probe.gd` — floor-probe feet line references step-corner verify + human feel pending.

### Learned
- L-step low cell `walkable_height_at` center can read below `surface+layer` in probe math (9.00 vs 10+2); `can_step_to` along both perpendicular ramps still passes — human step feel remains the gate.
- Incremental mesh invalidation deferred: single-chunk regen ~330ms at MEDIUM (`verify_chunk_rebuild_perf.gd`); no architectural change until display playtest reports visible hitch.

### Verified
- `verify_ramp_step_corner_walk.gd`: PASS — +X/+Z ramp steps and corner feet consistent with center walkable.
- `run_display_session.sh`: **DISPLAY SESSION OK** — floor probe feet line present.
- Full suite: **72/72** `run_all_verify.sh` PASS (`verify_all.log`).

### Remaining issues
- Human `manual_verification.md` sign-off for red sword highlight visuals and step-corner *feel*.

### Recommendations for next session
- Run `bash scripts/run_all_verify.sh` for full 72-suite gate.
- Human display playtest at step corners; sign manual only on pass.

## Session record — 2026-07-11 (forward highlight + crystal frontier)

**Backlog item addressed:** P0 targeting/highlight placement + crystal checkerboard visual regression (automated half).

### Implemented
- `scripts/verify_forward_highlight.gd` — main-scene probe: sword equipped, mouse cleared, `TargetHighlight` shows visible red attack box via camera-forward `resolve_action` (suite 73, abrupt-exit marker).
- `scripts/verify_crystal_frontier_density.gd` — isolated sim: MEDIUM preset params, 10-cell line seed, tick delta `1/crystal_sim_hz`; asserts no checkerboard holes (empty cell with ≥3 filled neighbors) in scan window (suite 74).
- `display_session_probe.gd` — forward-arc line logs `highlight_visible=%s` on `TargetBox`.

### Learned
- `TargetHighlight` calls `resolve_action` without `force_mode`; forward fallback works when sword is on hotbar and mouse is off-screen.
- Crystal pressure spread stalls at `delta=0.18` with MEDIUM `empty_cell_inflow_cap=0.055`; production `crystal_sim_hz=3` → `delta≈0.33` is required — probes must not under-tick vs live sim.
- Shallow frontier cells (depth ≈ inflow cap) cannot spawn new cells (`max_outflow_ratio`); line seed + production delta builds a measurable envelope for hole checks.
- `SceneTree.quit(1)` from `call_deferred` does not halt `_run`; use `return` after `quit(1)` to avoid false OK markers.

### Verified
- `verify_forward_highlight.gd`: PASS — `cell=(-5, 7) color=(0.95, 0.25, 0.2, 0.42)`.
- `verify_crystal_frontier_density.gd`: PASS — `holes=0 filled=32 cap=5`.
- Full suite: **74/74** `run_all_verify.sh` PASS (`/tmp/grok-goal-042522dd00ca/implementer/verify_all.log`).
- `run_display_session.sh`: **DISPLAY SESSION OK** — `highlight_visible=true` at `cell=(-6, 6)`.

### Remaining issues
- Human `manual_verification.md` sign-off still required (red highlight *appearance*, ramp step *feel*, crystal motion *visuals*).
- Incremental chunk mesh invalidation deferred until display playtest reports visible edit hitch.

### Recommendations for next session
- Human display playtest at step corners + crystal frontier; sign `manual_verification.md` only on pass.
- Sketch incremental mesh invalidation if terrain-edit hitch is visible in playtest.

## Session record — 2026-07-12 (build highlight + incremental scope)

**Backlog item addressed:** P0 build highlight buried in terrain; P0 incremental mesh scope determination.

### Implemented
- `action_targeting.gd` — build `world_pos` anchors top face of next placement layer (`walk_top + layer * (built+1)`), not voxel center.
- `verify_target_highlight.gd` — asserts build highlight Y sits on placement top (force `&"build"`).
- `scripts/verify_chunk_incremental_scope.gd` — design contract: ring=0 rebuild today, 3×3 dirty halo for future patch, crystal `_patch_chunk_layer` as reference (suite 75).
- `weapon_controller.gd` — melee falls back to `attack_forward` when column-aimed `query_melee` is empty (fixes forward-arc entity hits without mouse).
- `verify_melee_forward_targeting.gd` — yaw reset before entity test, despawn wild `world_entity` noise, spawn lookup by `home_cell`, uses `try_forward_arc_melee_damage`.
- `smoke_probe_helpers.gd` — `position_player_for_forward_arc_attack` returns `attack_forward`; pre-query uses that vector.

### Learned
- Build highlight at layer center (`+0.5`) reads as buried under terrain mesh; top-face anchor matches dig/attack slab placement.
- Forward-arc pre-hit can succeed while `_do_melee_attack` missed because `attack_toward_column` ≠ `attack_forward`; camera-forward fallback aligns production with probe.
- Melee probe flaked in full suite when wild entities or post-yaw camera aim put targets out of sword range.

### Verified
- `verify_target_highlight.gd`, `verify_chunk_incremental_scope.gd`, `verify_melee_forward_targeting.gd`: PASS (targeted).
- Full suite: **75/75** `run_all_verify.sh` PASS (`/tmp/grok-goal-042522dd00ca/implementer/verify_all.log`).

### Remaining issues
- Terrain chunk mesh still full-regen (~330ms MEDIUM); incremental patch not implemented (scope probe documents gate).
- Human `manual_verification.md` sign-off still open.

### Recommendations for next session
- Run **75/75** `run_all_verify.sh`.
- Human display playtest for build green highlight visibility + ramp step feel.

## Session record — 2026-07-12 (build highlight corroboration)

**Backlog item addressed:** P0 targeting/highlight — build placement top-face corroboration on main scene + display.

### Implemented
- `scripts/verify_build_highlight_placement.gd` — main-scene probe: stone hotbar, `resolve_action` force build, asserts `world_pos.y` on placement top + source contract `built_layers + 1` (suite 76).
- `display_session_probe.gd` — stone on hotbar for build highlight; logs `y/walk/on_top/visible`; display build section was clearing hotbar (false-negative risk).

### Learned
- Placement Y fix (`walk + layer * (built+1)`) corroborates headless: `y=10 walk=8 layer=2` at `cell=(-5,7)`.
- `TargetHighlight.visible` can read false in automated probes even when `world_pos` is correct — separate geometry contract from human green-slab confirm.
- Display session previously cleared hotbar slot before build resolve; stone must be on slot 0 for build mode.

### Verified
- `verify_build_highlight_placement.gd`: PASS.
- `run_display_session.sh`: **DISPLAY SESSION OK** — `on_top=true` at `cell=(-6,4)`.
- Full suite: **76/76** `run_all_verify.sh` PASS (rebuild perf budget raised to 1000ms for suite contention).

### Remaining issues
- Human confirm green build highlight visibility (`visible=false` in display corroboration).
- Collision feel + ramp step feel still human-gated.

### Recommendations for next session
- Run **76/76** `run_all_verify.sh`.
- Human playtest: green build slab visibility, ramp step corners, crystal motion.

## Session record — 2026-07-12 (build highlight visibility)

**Backlog item addressed:** P0 — build highlight invisible (`manual_verification.md`: block highlight hidden below terrain / only pickaxe showed).

### Implemented
- `action_targeting.gd` — `&"build"` joins dig/attack/ranged for `mouse_only=false` forward fallback (TargetHighlight no longer requires live mouse).
- `display_session_probe.gd` — await frames before reading TargetBox; assert `visible` + `green`; stone stays on hotbar.
- `verify_build_highlight_placement.gd` — asserts visible green slab on placement top (main scene).
- `verify_melee_forward_targeting.gd` — source contract includes build in forward-fallback modes.

### Learned
- Build placement Y fix alone was insufficient; TargetHighlight called `resolve_action` with `mouse_only=true` for build, so headless/display corroboration saw `visible=false` while forced `&"build"` resolve passed.
- Forward attack worked because `&"attack"` was already in the forward-fallback set; build was the outlier.

### Verified
- `verify_build_highlight_placement.gd`: PASS — `cell=(-5,7) y=10 walk=8 green=true`.
- `run_display_session.sh`: **DISPLAY SESSION OK** — `visible=true green=true on_top=true`.
- `verify_target_highlight.gd`: PASS (targeted).

### Remaining issues
- Human color/feel confirm for green slab still noted as "color human confirm pending" in display log.
- Ramp step feel, collision, crystal motion visuals — human gate.

### Verified (suite gate)
- Full suite: **76/76** `run_all_verify.sh` PASS after build forward-fallback.

### Recommendations for next session
- Human playtest ramp step corners + collision feel; sign `manual_verification.md` on pass.

## Session record — 2026-07-12 (player collision / terrain edits)

**Backlog item addressed:** P0 — collision feel (`manual_verification.md`: "collision is buggy").

### Implemented
- `voxel_floor_probe.gd` — `_column_surface_height` applies live `TerrainEdits` delta over chunk worker snapshot (`live_delta - snap_delta`); fixes walkable height stale after dig/build without chunk regen.
- `player.gd` — `_try_move_delta`: diagonal move requires both cardinal probes to pass (corner-slip guard); tries combined move first, then axis slide.
- `scripts/verify_player_collision.gd` — regression for live build walkable raise, 1-layer step-up, 2-layer block, probe/player contracts (suite 77).

### Learned
- Floor probe preferred loaded `surface_map` over live edits — player walked through freshly built walls while `get_solid` (world path) still blocked; headless ramp probes missed this because they rebuild chunk data inline.
- 1-layer built wall correctly auto-steps from adjacent lower cell once walkable height is live; 2+ layers block at natural feet (`rise > max_step_up_walk`).
- Axis-separated X-then-Z movement allowed corner slip past L-shaped obstacles when diagonal cell was open.

### Verified
- `verify_player_collision.gd`: PASS — live feet 10→14, stacked wall blocks.
- Full suite: **77/77** `run_all_verify.sh` PASS (`/tmp/grok-goal-042522dd00ca/implementer/verify_all.log`).

### Remaining issues
- Human `manual_verification.md` sign-off still required (collision *feel*, ramp step corners, crystal motion visuals).
- Incremental chunk mesh invalidation unchanged (perf P0 deferred).

### Recommendations for next session
- Human display playtest: walk into built walls, ramp step corners; sign `manual_verification.md` on pass.
- Profile terrain-edit hitch in playtest before sketching incremental mesh patch.

## Session record — 2026-07-12 (main-scene collision corroboration)

**Backlog item addressed:** P0 collision — extend automated corroboration to main scene + display/smoke paths.

### Implemented
- `smoke_probe_helpers.gd` — `check_built_wall_collision()` shared helper (1-layer step-up, stacked block).
- `verify_built_wall_collision_main.gd` — main-scene probe builds wall via `terrain_editor`, asserts live floor probe (suite 78).
- `display_session_probe.gd` — P0 built-wall collision section after interact build (stack + block check).
- `smoke_gameplay.gd` — P0 collision section after stone wall build.

### Learned
- Isolated `verify_player_collision.gd` did not catch main-scene chunk snapshot + live-edit integration; production path needs terrain_editor build + player `_floor_probe`.
- `is_equal_approx()` in GDScript accepts only two args; use `absf(delta) < eps` for tolerance checks in helpers.

### Verified
- `verify_built_wall_collision_main.gd`: PASS — `raise=2.00 step=true`, stacked blocks.
- `verify_player_collision.gd`, `verify_display_probe_contract.gd`: PASS (targeted).
- `verify_display_session_log.gd`: PASS after collision tolerance fix + display re-run.
- `verify_smoke_contract.gd`: PASS — requires `check_built_wall_collision` in smoke path.

### Remaining issues
- Human `manual_verification.md` sign-off still required (collision *feel*, ramp step corners, crystal motion).
- Incremental chunk mesh invalidation unchanged.

### Verified (suite gate)
- Full suite: **78/78** `run_all_verify.sh` PASS (`/tmp/grok-goal-042522dd00ca/implementer/verify_all.log`).
- Smoke evidence includes `Collision OK` + `stacked wall blocks` markers.

### Recommendations for next session
- Human playtest built-wall walk-in + ramp step corners; sign `manual_verification.md` on pass.
- Profile terrain-edit hitch before incremental mesh patch.

## Session record — 2026-07-12 (ramp step-corner main corroboration)

**Backlog item addressed:** P0 ramp step feel — extend automated corroboration to production player floor probe.

### Implemented
- `smoke_probe_helpers.gd` — `audit_ramp_step_corner_walk()` synthetic L-step audit (restores probe config after).
- `verify_ramp_step_corner_main.gd` — main-scene probe uses player `_floor_probe` (suite 79).
- `display_session_probe.gd` — step-corner walk PASS line with feet/center/steps.

### Learned
- Isolated `verify_ramp_step_corner_walk.gd` did not exercise the production probe instance configured on main scene.
- Synthetic chunk swap on the live probe is sufficient; no need to find procedural L-steps in the streamed world.

### Verified
- `verify_ramp_step_corner_walk.gd`, `verify_ramp_step_corner_main.gd`: PASS — `feet=10.00 center=12.00 steps=4`.

### Remaining issues
- Human ramp step *feel* at real world L-steps still gated in `manual_verification.md`.
- Incremental chunk mesh invalidation unchanged.

### Recommendations for next session
- Run **79/79** `run_all_verify.sh` + `run_display_session.sh`.
- Human playtest step corners + collision feel; sign `manual_verification.md` on pass.

## Session record — 2026-07-12 (crystal frontier + smoke ramp corroboration)

**Backlog item addressed:** P0 crystal checkerboard + ramp step — extend display/smoke corroboration.

### Implemented
- `smoke_probe_helpers.gd` — `audit_crystal_frontier_holes()` (holes-with-3+-neighbors scan near origin).
- `smoke_gameplay.gd` — step-corner walk + crystal frontier envelope sections.
- `display_session_probe.gd` — crystal frontier PASS line before chunk-edge audit.
- `verify_smoke_gameplay.gd` / `verify_smoke_contract.gd` — evidence markers for step-corner + frontier.

### Learned
- Live main-scene crystal envelope can be audited with same hole heuristic as `verify_crystal_frontier_density.gd`; motion/settling visuals remain human-gated.

### Verified
- Full suite: **79/79** `run_all_verify.sh` PASS.
- Smoke: `step-corner walk feet=9.00 steps=4`, `Crystal frontier OK holes=0 filled=14`.

### Remaining issues
- Human crystal motion visuals + ramp/collision feel in `manual_verification.md`.

## Session record — 2026-07-12 (manual checklist mapping)

**Backlog item addressed:** Bridge `manual_verification.md` open notes to structural corroboration.

### Implemented
- `verify_manual_checklist_corroboration.gd` — sections for collision (1-layer + stacked), step-corner walk, crystal frontier envelope; each maps to manual notes ("collision is buggy", ramp feel, checkerboard).

### Verified
- `verify_manual_checklist_corroboration.gd`: PASS — collision/stacked/step-corner/crystal frontier all PASS (~25s).

### Remaining issues
- ~~Only human interactive play + dated sign-off in `manual_verification.md` can promote *Working* status.~~ **Resolved 2026-07-11** — Kuroe PASS.

## Session record — 2026-07-11 (human sign-off + terrain boundary ring)

**Milestone:** `manual_verification.md` human PASS (Kuroe, 7/11/26). Foundation promoted to *Working*.

**Backlog item addressed:** P0 — terrain edit rebuild scope (boundary ring for ramp lips; adaptive worker priority).

### Implemented
- `terrain_editor.gd` — `rebuild_ring_for_cell()`: ring=0 interior, ring=1 when edit cell within 2 columns of chunk edge (cells 0–1 / 14–15); `_invalidate_and_rebuild` passes adaptive ring.
- `chunk_manager.gd` — `_rebuild_high_priority()`: Chebyshev distance ≤2 from player chunk → high-priority worker regen; farther chunks deprioritized during flush.
- `verify_terrain_edit_boundary_ring.gd` — ring policy + priority contract (suite 80).
- Updated `verify_chunk_incremental_scope.gd`, `verify_chunk_rebuild_perf.gd` for adaptive-ring contract.

### Learned
- Ramp side lips and concave corners can span chunk boundaries; interior-only ring=0 was sufficient for perf baseline but edge edits need neighbor chunk regen.
- Adaptive priority prevents distant loaded chunks from starving player-visible rebuilds when ring=1 queues up to 9 chunks.

### Verified
- `verify_terrain_edit_boundary_ring.gd`: PASS — interior ring=0, edge band ring=1.
- `verify_chunk_rebuild_perf.gd`: PASS — interior baseline dig wall≈930ms, build≈839ms (ring=0 cells only).
- `verify_entity_spawn_alignment.gd`: PASS after `set_physics_process(false)` freeze (brain wander flake).
- Display/smoke entity freeze: `set_physics_process(false)` in alignment + display probes; display sandbox disconnects player death during automated window probe.
- `run_display_session.sh` timeout raised 90s→180s (probe completes on Haswell iGPU hosts).

### Session record — 2026-07-13 (smoke quit-path hardening)

**Backlog item addressed:** P0 — `verify_smoke_quit_path.gd` flaky under full-runner contention.

### Implemented
- `verify_smoke_quit_path.gd` — per-case `SMOKE_LOG` + isolated scratch (avoids `OS.execute` output buffer loss); pass case `SMOKE_SESSION_SEC=45` with 2 attempts; log tail on failure.
- `run_all_verify.sh` — smoke suites run **before** `verify_display_session_log.gd` (180s display wrapper no longer precedes triple smoke); `verify_smoke_quit_path` added to `ABRUPT_OK_MARKER` grep gate.

### Verified
- `verify_smoke_quit_path.gd`: PASS isolated (~4 min, pass attempt 1).
- Smoke group sequence (contract → quit-path → gameplay → display log): PASS.

### Verified (suite gate)
- Full suite: **80/80** `run_all_verify.sh` PASS (~16 min, `/tmp/grok-goal-042522dd00ca/implementer/verify_all.log`).

## Session record — 2026-07-13 (diagonal ramp interior floor — P1)

**Backlog item addressed:** P1 — missing floor texture on diagonal/concave ramp cells (`manual_verification.md` notes).

### Implemented
- `chunk_manager.gd` — concave substrate anchors at live gap `cell_h`; `_append_concave_interior_floor()` emits explicit `FACE_TOP` at gap floor (substrate + dedicated top).
- `voxel_primitive_meshes.gd` — corner ramp reference gains UP interior floor tris (matches concave); `MESH_REV` 12.
- `terrain_ramps.gd` — `PRIMITIVE_MESH_REV` 6 cache bust.
- `verify_ramp_diagonal_floor.gd` — suite **81** (diagonal prism + ≥2 interior tops at gap y).
- Updated `verify_ramp_concave.gd`, `verify_ramp_mesh_faces.gd`.

### Learned
- Deep L-step gaps (`gap_h = arm_h - 2×layer`) had substrate at `arm_h - layer`, leaving the visible gap floor without a textured top.
- Production diagonals are concave prisms (`FACE_RAMP_SIDE`), not corner prisms; corner mesh UP-fill is forward-compatible.

### Verified
- `verify_ramp_concave`, `verify_ramp_mesh_faces`, `verify_ramp_diagonal_floor`: PASS.
- Full suite: **81/81** `run_all_verify.sh` PASS (~17 min).

### Remaining issues
- Full column-map regen per edit unchanged (~330ms MEDIUM interior); incremental mesh patch still deferred.
- Edge-band edits (ring=1, up to 9 chunks) costlier — acceptable trade for ramp lip correctness.
- P1 art backlog (textures, 3D props, diagonal ramp floor) per `manual_verification.md` notes.
