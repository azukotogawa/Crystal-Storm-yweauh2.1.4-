# Crystal Storm — Stabilization Board

Last updated: 2026-07-09T01:31 (47 verify suites; landing-cell ramps; human visual PASS pending)

**Rule:** *Working* only after dated PASS in `manual_verification.md` from human interactive play.

Evidence (`/tmp/grok-goal-4d59198f47c0/implementer/`):
| File | Role |
|------|------|
| `manual_verification.md` | Human checklist (**PENDING** re-test after fixes) |
| `manual_gate.txt` | Harness cannot substitute for human sign-off |
| `smoke_gameplay.log` | `SMOKE GAMEPLAY OK` (mouse-warp dig) |
| `display_session.log` | `DISPLAY SESSION OK` (dig/build/highlight/jump) |
| `scripted_smoke_evidence.md` | Headless smoke evidence file |
| `display_session_evidence.md` | Display-window corroboration |
| `interactive_manual_verification.md` | Step-by-step human play guide |
| `manual_gate.txt` | Harness cannot substitute for human sign-off |
| `core_verify.log` | 10 gating suites exit 0 (incl. `verify_target_facing`, stacked build) |
| `main_boot_low/medium/high.log` | 12s preset boots clean |

```bash
CRYSTALSTORM_PERF_PRESET=medium godot scenes/main.tscn
bash scripts/run_smoke_gameplay.sh
godot --headless -s scripts/verify_target_facing.gd
godot --headless -s scripts/verify_terrain_build.gd
```

## P0 — Must work before new features

| Subsystem | Status | Evidence | Regression test |
|-----------|--------|----------|-----------------|
| Facing-aware targeting | Partially Working | Camera `basis.z` + movement rotation; 4 orbit cells; **human dig/build direction pending** | `verify_target_facing.gd`, `verify_target_highlight.gd` |
| Stacked build mesh | Partially Working | `_emit_build_strata` emits intermediate tops; verify 2-layer quads; **human stack pending** | `verify_terrain_build.gd` |
| Terrain atlas | Partially Working | `Cube.png` 7×10; 5 biome types across chunks; **human variety pending** | `verify_chunk_atlas.gd` |
| Dig + highlight | Partially Working | Smoke dig + orange highlight; **human carve pending** | `verify_terrain_dig.gd`, `verify_smoke_gameplay.gd` |
| Combat + swing VFX | Partially Working | `weapon.attacked` burst; entity damage; **human melee highlight pending** | `verify_combat_entity_hit.gd` |
| Diagonal ramps | Partially Working | L-step corner prisms emit (corner=2 in spawn); concave rev 3; **human visual pending** | `verify_ramp_concave.gd`, `verify_ramp_corner.gd` |
| Entities / vegetation 3D | Partially Working | Voxel props scaled 0.32×; density ~2×; veg 15 in smoke; **human scale pending** | `verify_visual_texture_binding.gd` |
| Crystal fluid | Partially Working | Per-tick cap + incremental mesh_dirty; **human flow smoothness pending** | `verify_crystal_spread_limits.gd` |
| Chunk streaming | Partially Working | Smoke +64 stable | `verify_smoke_gameplay.gd` |
| Perf presets | Partially Working | LOW/MEDIUM/HIGH boot 12s each | `verify_perf_preset_boot.gd`, `main_boot_*.log` |

## Changelog

- 2026-07-09T00:10: Manual-note fixes — camera-facing targeting, stacked build strata, vegetation density/scale, concave rev 3, `verify_target_facing.gd`.
- 2026-07-09T00:15: Playable automated pass — build verify, swing VFX, biome scatter.
- 2026-07-08: Initial P0 ramp/atlas/highlight corroboration.