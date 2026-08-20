# Gameplay integration status

**Date:** 2026-08-19  
**Source of truth:** windowed `scenes/main.tscn` via `scripts/autonomous_gameplay_audit.gd` (gameplay camera, F3, F4 / LiveWorldQuery). Headless verify names are **not** grades.  
**Raw:** `{SCRATCH}/autonomous_audit.md`, `{SCRATCH}/autonomous_audit.json`, `{SCRATCH}/quality_*.json`, `{SCRATCH}/audit_*.png`.

Grades: **A** proven in the live camera · **B** works in isolation, fails in integration · **C** partial · **D** prototype only · **E** broken · **F** not meaningfully tested in this session.

---

## Systems

| SYSTEM | CURRENT STATE | LIVE GAME VERIFIED? | KNOWN BUGS | INTERACTIONS | PRIORITY | NEXT ACTION | GRADE |
|---|---|---|---|---|---|---|---|
| World generation | InfiniteNoiseWorld + bake packages stream at play | Yes — MEDIUM start `chunks_ready=39`, biomes steppe→marsh | Crystal origin relocates off water; start steppe far from crystal/town | Bake, stream, biomes | P2 | Spawn-vs-threat distance is vitality, not a crash | A |
| Biome generation | 5 biomes; HUD name updates (`First steps in Marsh`) | Yes — steppe at spawn, marsh after +48 columns | Marsh/steppe ground read as similar grass albedo | LivingWorldDirector toasts | P3 | Art differentiation, not this pass | A |
| Terrain height | WorldState overlays + surface maps | Yes — dig Δh, wall raise, F4 surf/walk | — | Mesh, collision, ramps | P2 | — | A |
| Terrain materials | Atlas tiles; F4 voxel/visual ids | Yes — tile 10 plains, 37/38 water, 39 wall, 40/41 builds | — | Mesh atlas | P3 | — | A |
| Chunk streaming | Player ring **plus crystal origin ±1** in `update_stream` / `start_stream_coords` | Yes — env medium dist=2, ICS includes chunk (−1,0); travel streamQ; explicit unload/reload AGREE | Return-travel still queues a few frames; audit waits resident+anchor | Bake, visuals, overlays, crystal sim | P2 | Keep origin extras; do not unload while player is far | A |
| Deferred baking | Valid v4 5×5 index; fill idle after stream-ready | Yes — occupancy loading then idle | Runtime vegetation scatter skipped because `vegetation_baked` | Features, veg | P2 | Confirm baked veg actually populates ground cover | A |
| Terrain editing | TerrainEditor.try_dig/try_build | Yes — dig, adj, under-wall, F4 covered | No first-class demolish verb (overlay clear) | Mesh, water, features | P2 | Add demolish through TerrainEditor | A |
| Digging | try_dig + immediate remesh + water reflow | Yes — trenches visible; neighbors covered | Spawn hitch ~300ms on first look | Mesh rebuild | P2 | Budget remesh | A |
| Building | stone/wood wall, gate, bridge WorldObjects | Yes — stream restore shot shows palisade, arch, deck | Builds shot can miss the mesh if camera is 2 cells south | FeatureVisualLayer, orientation | P1 | — | A |
| Ramps | Generated yard ramps; F4 landing + FACE_RAMP | Yes — ramps `has_ramp` + disc=[]; spawn re-audit **faces [0]** not orphan 7 | — | Mesh cover query | P2 | Cover clip shipped | A |
| Walls | stone_wall WorldObject, Δh, heightfield | Yes — pin 42,11 after unload/reload | Dig-under-wall keeps visual | Collision is floor probe | A | — | A |
| Bridges | try_build after trench | Yes — WorldObject yes; restore shot shows deck | Early builds PNG framed empty grass | Feature visuals | A | — | A |
| Gates | passage collision, rebuild after remove | Yes — arch in restore shot; F4 passage | Remove is overlay-hack not a verb | Crystal baffle | P2 | TerrainEditor.try_remove | A |
| Vegetation | Bake packages; runtime scatter skipped | Partial — trees on camera at spawn; 16×16 overlay plants=2 visuals=2 (agree, sparse) | `skip_runtime_vegetation=true` when bake veg valid; steppe ground cover sparse | FeatureVisualLayer billboard budget | P2 | Density is bake/biome, not a populate miss | C |
| Water | VoxelFluidService dirty-region; channel + natural river | Yes — channel cell visual 38; natural water 24,6; F3 water sleep | Diagnostics still list 121 loaded channels from last tick | Crystal conductivity, dig | P2 | Keep sleep path | A |
| Crystal | 8/8 spawns, origin (−10,10) | Yes — HUD **Crystal 54c · cap 72% · 57c W**; at origin F4 depth + **purple spawn marker**; `front` when close | Spawn camera still does not see the mass (56c, keep ≥20) | Enemies, HUD, presentation | P2 | Marker is readable; volume mesh still subtle on water | A |
| Enemies | 28s grace; mites unlocked at boot; ring 3–10 columns | Yes — **0** at maze spawn (56c, by design); toast + purple voxel mite **on camera** after walking to origin | Maze camp stays mite-free until the player closes | Crystal, combat, HUD | P1 | — | A |
| Combat | LMB sword; range in world units; adjacent fallback | Yes — `crystal_mite hit 12.0 → 12 HP`, VFX bursts, mite voxel on `open_combat.png` | First 70° mouse arc can miss without hover; adjacent fallback now connects | Spatial query, VFX | P2 | Hover-aim still the intended player path | A |
| Player movement | Voxel floor probe, teleport/walk in audit | Yes — walk 6 columns, far travel, snap-to-ground | Red debug hex, not the sprite, is the body | Camera, collision | A | — | A |
| Collision | heightfield_probe; walls block by step-up | Yes — F4 collision_kind; gate passage | WorldObject Area3D debug-only (by design) | Ramps, walls | A | — | A |
| World persistence | WorldState overlay bundle export | Save_slot called; persist keys recorded | Full leave/reload of a second world not driven this session | SaveGameService | P2 | Frontend round-trip | C |
| Save/load | SaveGameService.save_slot(0) | Call succeeded (err 0 in actions) | No load_slot round-trip in this audit | WorldState | P2 | Resume world from frontend | C |
| Inventory/relics | Hotbar + stone/wood counts after dig/build | Yes — HUD x96 stone/wood, pick/dig | Relic line empty | TerrainEditor consume | A | — | A |
| World selection | Frontend exists; not booted this session | No — audit used main.tscn directly | — | WorldManager | P2 | Drive frontend.tscn | F |
| Camera | Continuous yaw 12°–333°; F4 cell stable | Yes — six headings, same cell origin/life | Builds PNG look-at offset | Action targeting | A | — | A |
| Loading | Occupancy + lock hint | Yes — prior goal shots + stream-ready gate | get_biome arity error in audit (fixed) | CompositionRoot | A | — | A |
| Pause | ESC panel; F3 PAUSE | Yes — `audit_pause.png`, F3 text PAUSE | Opening pause can re-apply settings | PlayerSettings | P2 | Preset change snaps distance | A |
| Settings | Pause Low/Med/High + rd slider | Yes — Perf `preset=1 dist=2 env=medium` this audit | Saved slider used to replace env preset (fixed) | PerformanceService | P0 | **Fixed prior pass** | A |

---

## Prioritized integration bug list

1. **P0 — Quality preset vs leftover player settings (FIXED prior pass).** Saved `render_distance=5` replaced env LOW. Native LOW dist=1 / HIGH dist=3 confirmed.
2. **P1 — Crystal HUD 0.0% (FIXED this pass).** HUD now prints live `covered_cells` (`Crystal 22c · cap 72%`) instead of map-wide 0.0%. Re-audit: no `0.0%` in HUD while tiles=22→53.
3. **P1 — Crystal origin outside MEDIUM player ring (FIXED this pass).** Sim is loaded-chunks-only. `start_stream_coords` + `update_stream` keep origin chunk ±1 resident. Re-audit: origin (−10,10) chunk (−1,0) in start stream, ICS loads it, F4 **CRYSTAL depth 2.27**, purple mesh on `audit_crystal.png`.
4. **P1 — Vegetation vitality.** Overlay=visuals (2=2) so populate is not dropping plants. Steppe 16×16 is sparse; camera still shows trees. Runtime scatter skipped because bake veg is valid. Density, not a restore bug.
5. **P1 — Stream return sampled mid-bake (FIXED prior: wait resident+anchor).** `return_wall` AGREE with palisade in this re-audit.
6. **P2 — FACE_RAMP greedy span (query clip shipped).** Re-audit spawn MESH not orphan 7.
7. **P2 — No demolish gameplay verb.** Remove used FeatureRegistry.clear.
8. **P2 — Enemies/combat untested** until mites unlock (0 crystal_enemy, 21 world_entity, 28s grace + grass absorption). Origin chunks now stay loaded so absorption *can* progress.
9. **P3 — Biome materials look similar** across steppe/marsh.
10. **P3 — Spawn camera does not see the purple front** (~46 columns west). Toast says “Watch the purple front”; HUD now shows tile count. Early-survival verify wants spawn ≥20 from origin — do not collapse that gap.

---

## Performance (idle-settled after stream queue/mesh/inflight == 0)

Headless `scripts/profile_quality_live.gd`. **Do not change HIGH knobs from the old 40 ms start-drain number.**

| Preset | when | avg frame_ms | worst | Hottest named (avg_ms) |
|---|---|---:|---:|---|
| MEDIUM (idle wait, still some mesh) | this goal | 31.4 | 61.1 | chunk_mesh 47.4, chunk_column 21.9, physics 19.6 |
| HIGH **start drain** (prior native) | dist=3 ICS 70 chunks | 40.1 | — | chunk_mesh 40 avg max 396 |
| HIGH **idle-settled** | this pass, 64 resident | **20.2** | 36.7 | physics 14.5, process 5.7, entity_physics 3.2, entity_nav 2.8, crystal_manager **1.33** |

HIGH extra vs MEDIUM at idle is **entities** (`use_lightweight_entity_nav=false`, max 96 vs 64), not `crystal_sim_hz=18` (1.3 ms at start size). `debug_expensive_queries=true` is unread dead config. Windowed MEDIUM re-audit settled ~10–26 ms after spawn hitch; F3 pause 48 fps.

Native env distances (composition skip leftover PlayerSettings): LOW dist=1 / MEDIUM dist=2 / HIGH dist=3 / SAFE dist=1 crystal=off.

### Windowed activity (crystal front, 90 frames)

| Preset | avg_ms | worst | Hottest |
|---|---:|---:|---|
| MEDIUM | 27.4 | 50.9 | physics 20.9, process 6.4, entity_phys 1.7, crystal 1.4 |
| HIGH | 30.8 | 61.3 | physics 24.1, entity_phys 5.7, entity_nav 4.6, crystal 2.3 |

HIGH extra in play is **entity_physics + entity_navigation**, not 18 Hz crystal. **No HIGH knobs changed.**

---

## Next

1. Mouse hover-aim is still the intended combat path; adjacent fallback covers standing next to a mite.
2. Crystal *volume* mesh on water is still subtler than the spawn-marker pyramid (marker is now on camera).
3. Frontend save/load round-trip still untested.
4. If HIGH needs more FPS later, look at `use_lightweight_entity_nav` first.
