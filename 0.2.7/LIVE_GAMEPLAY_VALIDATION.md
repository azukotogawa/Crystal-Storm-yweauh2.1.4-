# Live gameplay validation

**Date:** 2026-08-17  
**Stop line:** audit / validation only. No ruin/town assets, no world-gen rule changes, no rewrite.  
**Driver:** `scripts/display_gameplay_validation.gd` on production `scenes/main.tscn` with the real gameplay camera.  
**Yard:** `world/validation_yard.gd` at columns (24,24).  
**Raw JSON:** written beside the screenshots by the display driver.

Classifications: **A** visually verified · **B** gameplay verified · **C** automated-only · **D** still broken · **E** design decision.

---

## 1. Live World Inspector (F4)

F4 is the detailed object tool. It now prints, for the cursor/pinned cell:

| Field | Source |
|---|---|
| gameplay coordinate | integer `wx,wz` |
| visual coordinate | `WorldVisualCoords.cell_center` (column × voxel_scale) |
| voxel / visual ID | tile + feature `build_id` |
| surface / walkable height | WorldState + probe / ramp entry |
| rendered AABB | WorldObject mesh if present, else column AABB |
| collision AABB | heightfield column (`voxel_scale` × walk span) |
| owning chunk / node path | ChunkView or WorldObject |
| yaw | FeatureRegistry / WorldObject |
| terrain layer | height_delta / layer_height |
| origin | baked / streamed / live |
| collision exists + kind | `heightfield_probe` / `passage` / `none` |
| interactable | dig/build/feature/entity |
| **discrepancies** | red `⚠` lines; green `agree` when empty |

**A** — Screenshot `00_yard_overview.png` and `cell_stone_wall_26_27.png` show the panel on the live camera with green agree, both coordinate spaces, both AABBs, collision kind, mesh_cover, origin.

Pin API (`inspector.pin_cell`) used so the panel tracks the yard cell, not a stray mouse ray.

---

## 2. Validation yard (gameplay camera)

Placed and photographed: flat, raised stone, four attempted ramp landings, wood wall, stone wall, gate, bridge, adjacent palisade pair, water/channel, crystal seed cell, then dig/build sequence.

**A** — `cell_wood_wall_24_27.png`, `cell_stone_wall_26_27.png`, `cell_gate_28_27.png`, `cell_bridge_30_27.png`: distinct authored meshes (palisade, masonry, arch, deck) from the iso camera. F3 compact overlay is on the same frames.

---

## 3. Ramps (four directions)

| Intent | Result | Class |
|---|---|---|
| Stamp 4 generated steps (east/west/south/north) | `has_ramp=false` on all four landing cells. Surface-map stamp did not survive the mesh snapshot / emit path. | **D** for this fixture |
| Walk math vs mesh `dir` | Unchanged contract (`dir` = toward low). Headless `verify_ramp_slope` still passes. | **C** |
| Accidental natural ramp at yard “flat” (24,24) | `has_ramp=true`, `dir=(0,-1)`, `approach=true`, inspector flagged `MESH_HOLE` because approach columns skip the greedy top (the wedge is the visual). Walk 9 vs surface 6. | **A** (one real ramp) + **E** (approach hole is emit design, not a clip bug) |

**Not claimed fixed:** visual correctness of wedges in all four compass directions. The yard did not produce those four meshes. Do not treat the slope unit test as camera proof.

---

## 4. Terrain edits / disappearing coverage

After dig one, dig adjacent, and dig under a greedy slab:

- edited column `column_mesh_covered=true`
- all four neighbors `covered=true`
- no `MESH_HOLE` on those cells
- `edit_dig_slab.png`: inspector `mesh_cover true`, Δh −2, green agree; surrounding tiles still present

**A + B** for the disappearing-greedy-slab class (clip contract + live camera).

Build on the “flat” ramp-approach cell stayed `MESH_HOLE` (same approach-skip as §3). Neighbors stayed covered. **E** — not the old “whole slab vanished” failure.

---

## 5. Building placement

| id | WorldObjects | IDs match | collision kind | disc |
|---|---|---|---|---|
| wood_wall | 1 | yes | heightfield_probe | none |
| stone_wall | 1 | yes | heightfield_probe | none |
| gate | 1 | yes | **passage** | none |
| bridge | 1 | yes | heightfield_probe | none |

Adjacent palisade pair both `yaw=0` (east–west run). **A + B**.

Raised walls: surface 8 / walk 10 / layer 1. Gate: surface 6 / walk 8 / not raised. Bridge over a dig: surface 6 / walk 8.

---

## 6. Hitboxes

`is_colliding_at` at **walkable top + 0.2** of the stone wall and of the gate were both **false**.

That is expected for the current model: the probe treats the raised column as a floor, not a solid you stand inside. A wall “blocks” by failing the step-up from the low neighbor, not by a Godot body. A gate does not raise, so it is a passage.

**E — keep the hybrid:**

- **Terrain / walls / bridges / ramps:** custom `VoxelFloorProbe` heightfield. Do **not** add per-voxel `StaticBody3D`.
- **Gates:** gameplay passage (no height). `WorldObject` `Area3D` is debug visualization only (`collision_layer=0`).
- **Entities / player:** existing `CharacterBody3D` capsule + probe. Combat uses the spatial query layer, not physics queries.

Putting `StaticBody3D` on authored structures would fight the probe (double collision) unless the probe learned to ignore them. Not recommended without a dedicated follow-up.

`wall_blocks=false` in the JSON is **not** proof the wall is walk-through from the low side.

---

## 7. Godot node / scene opportunities (report only)

Use native nodes where they already help. Do not Node-ize voxels.

| Keep as-is | Why |
|---|---|
| Chunk MultiMesh / greedy quads | Required for horizon + edit cost |
| VoxelFloorProbe | Authoritative walk / hit for terrain |
| Crystal / water sim maps | Not scene objects |

| Worth a later, narrow scene | Why |
|---|---|
| `WorldObject` (already) | Authored wall/gate/bridge/hall/ruin — editor-visible, F4 path, debug Area3D |
| Player `CharacterBody3D` | Already a scene node; do not drive it with `move_and_slide` on terrain |
| Pause / loading / HUD | Already Controls |
| Entity `WorldEntity` | Could gain a real `CollisionShape3D` for combat debug; gameplay radius stays in the query layer |
| `RayCast3D` | Targeting is a custom ortho plane pick; a ray would disagree with the iso camera |
| `GPUParticles` | Dig dust / build flash already exist as one-off VFX; not a representation bug |

---

## 8. Debug UI

| Key | Role | Evidence |
|---|---|---|
| **F3** | Compact FPS / column / chunk / crystal / hottest line | **A** — visible on every yard screenshot (`F3  5 fps  col …`) |
| **F4** | Live World Inspector | **A** |
| **F11** | Bug report (`BugReporter` + `DevToolsCoordinator`) | **C** — input action registered; coordinator now spawned from `main.gd` |
| **ESC** | Pause | **C** — `ui/pause_menu.gd` + structural verify |

Input map now includes `debug_overlay_toggle` (F3) and `bug_report` (F11).

---

## 9. Escape menu

`PauseMenu` (process always): **Resume**, **Settings** (preset / render distance / vegetation / combat visuals only), **Return to World Select**, **Quit**. Sets `GameplayInput.pause_open` and `get_tree().paused`.

**C** (structural + API). Not photographed in the yard run.

---

## 10. World generation / loading (player view)

Warm 5×5 bake (radius-2 smoke world), Play = instantiate `main.tscn`:

| Metric | Value |
|---|---|
| Play → start region ready | **17.3 s** (`play_to_start_region_ms=17263`) |
| Start region | **36 / 36** resident, **36 / 36** packages |
| Input blocked until ready | **true** |
| Loading labels | increment `Start region 0/36` … `36/36` (live occupancy, not a canned %) |
| Bake still filling after playable? | **no** (`bake_in_progress_at_playable=false`, `valid=true`) |
| ICS frames | 112 |
| Frame after play | **3–8 FPS**, frame 265–438 ms, **100% spikes** |

Main-thread work **after** playable, this run (not bake fill):

- `VoxelFluidService::_tick_water` **357 ms** (max 641)
- entity physics / navigation ~7 / 3 ms
- `process_callbacks` 363 ms (dominated by fluid)

Entering early is gated. Visible “generation stalls” after play on this warm world are **fluid + living-world**, not package fill.

Frontend cold-boot-to-menu was not timed in this pass (entry was `main.tscn` directly). Menu itself is a Control tree with no bake.

---

## 11. Water (measurement only)

`VoxelFluidService.get_sim_diagnostics()` during the yard:

| | |
|---|---|
| Channel cells | 2482 |
| Loaded channel cells | 2421 |
| Off-screen channel cells | 61 |
| Engine depth cells | 4287 |
| Subset loaded each tick | **4626** |
| Cap | 96 flow cells / tick |
| Active gate | `chunk_manager.is_world_cell_loaded` |
| CPU | **357 ms / tick** `_tick_water` |

**Why off-screen water still costs:** `_load_water_subset` copies **every** `ChannelRegistry` water cell plus neighbors into the engine every tick (`loads_all_channels_each_tick=true`). `is_cell_active` only skips *flow* on unloaded cells; it does not skip the gather. Inactive water is **not** frozen.

No simulation redesign in this pass.

---

## 12. Issue board

| Issue | Class | Notes |
|---|---|---|
| F4 inspector fields + discrepancy flags | **A** | Live camera |
| F3 compact overlay | **A** | Live camera |
| F11 bug report wiring | **C** | Actions + coordinator |
| ESC pause / settings / world select / quit | **C** | Scene + verify; not photographed |
| Start-region gate + live loading numbers | **A + B** | Labels 0→36; input locked |
| Building 1:1 feature↔WorldObject | **A + B** | Four types |
| Gate passage vs wall raise | **B** | Inspector kinds + heights |
| Disappearing greedy mesh after dig | **A + B** | Neighbors covered; slab shot |
| Ramp visual vs walk, all 4 dirs | **D** | Yard stamp did not emit ramps |
| Ramp approach `MESH_HOLE` flag | **E** | Wedge replaces greedy top |
| Wall “hitbox” vs Godot body | **E** | Heightfield step, not StaticBody |
| Crystal seeded yard cell | **D** | No `has_crystal` at (27,30) |
| Water CPU / off-screen gather | **C** (measured) | 357 ms; do not treat as fixed |
| Deferred fill hitch after play | **C** | Did not run (bake already valid) |
| Face-orientation greedy Y-down | **C** | Prior mesh-contract verify; not re-photographed as a before/after |

---

## How to replay

```
godot scenes/main.tscn
# F3 compact debug · F4 inspector · F11 bug report · ESC pause
```

Yard (dev): after start region, run `/` assistant or `ValidationYard.apply(tree)`.

Windowed driver: `godot --path . -s scripts/display_gameplay_validation.gd`
