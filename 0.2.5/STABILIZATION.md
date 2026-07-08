# Crystal Storm — Stabilization Board

Last updated: 2026-07-08T21:11 (skeptic gaps remediated — no Working without human-hand)

**Rule:** *Working* only after dated bullets in `manual_verification.md` from **human-hand** interactive play. Automated probes → *Partially Working* at best.

Evidence (`/tmp/grok-goal-e8916ce4c6d5/implementer/`):
| File | Role |
|------|------|
| `manual_verification.md` | Human-hand checklist (**PENDING**) |
| `interactive_manual_verification.md` | Step-by-step play guide |
| `display_session_evidence.md` | Automated display-window corroboration |
| `scripted_smoke_evidence.md` | Headless smoke |
| `run_all_verify.log` | Regression suite |

```bash
CRYSTALSTORM_PERF_PRESET=medium godot scenes/main.tscn   # required for Working
bash scripts/run_display_session.sh                      # corroboration only
bash scripts/run_smoke_gameplay.sh
bash scripts/run_all_verify.sh
```

## P0 — Must work before new features

| Subsystem | Status | Evidence | Regression test |
|-----------|--------|----------|-----------------|
| Runtime errors/warnings | Partially Working | WeaponController `is_tool` crash fixed; 25s headless `main.tscn` clean; display probe no longer emits CrystalTextureGenerator warning; **probe teardown may abort(134)** (harness) | `verify_weapon_attack.gd`, `verify_evidence_split.gd`, `verify_display_probe_contract.gd` |
| Pickaxe / digging | Partially Working | Attack input lowers height (3,5) 8→6 in probes; **visual carve unconfirmed by human** | `verify_terrain_dig.gd`, `verify_smoke_gameplay.gd` |
| Entity sprites | Partially Working | 1/1 textured in automated probes; **human confirm pending** | `verify_visual_pipeline.gd`, `verify_smoke_gameplay.gd` |
| Vegetation billboards | Partially Working | 1/1 textured in probes; **human confirm pending** | `verify_visual_pipeline.gd` |
| Chunk streaming | Partially Working | +64 move stable in probes; **human long-move pending** | `verify_smoke_gameplay.gd` |

## P1 — Core loop smoke

| Subsystem | Status | Evidence | Regression test |
|-----------|--------|----------|-----------------|
| Jump while moving | Partially Working | Smoke + display probes use `jump` + `ui_right` through player physics (no Y-teleport); **human feel pending** | `verify_player_jump.gd`, `verify_smoke_contract.gd`, `display_session_evidence.md` |
| Ramp collision / steps | Partially Working | Ramp math in probes; step feel untested | `verify_smoke_gameplay.gd` |
| Crystal loaded/unloaded chunks | Partially Working | Far cell edge checks in probes | `verify_loaded_chunk_bounds.gd` |
| Save/load terrain edits | Partially Working | Slot 7/8 roundtrip in probes; quick-save keys untested by human | `verify_save_slot_main.gd` |

## P2 — Presets & stability

| Subsystem | Status | Evidence | Regression test |
|-----------|--------|----------|-----------------|
| Performance presets | Partially Working | Config gates headless | `verify_stability_perf.gd` |
| Visuals per preset | Partially Working | MEDIUM probe OK | `verify_visual_perf.gd` |
| Long-session stability | Untested | — | — |

## Known harness limitations

- SceneTree probes (`smoke_gameplay.gd`, `display_session_probe.gd`) may exit **134** after OK markers during Godot teardown. Wrappers map markers → exit 0. **Not equivalent to in-game runtime failure** but blocks marking runtime *Working* from harness alone.

## Changelog

- 2026-07-08T21:11: Skeptic remediation — `smoke_gameplay.gd` jump uses real input (removed Y-teleport); dig lines data-only; chunk teardown `queue_free`+`remove_child`; `verify_smoke_contract.gd` extended. Evidence: `skeptic_remediation_proof.md`.
- 2026-07-08T21:06: Display probe bootstraps `CrystalTextureGenerator`; `game_visual_registry.gd` uses `get_tree().root` lookup (removed noisy fallback warning). 26/26 verify suites pass; display session OK without texture-gen warning.
- 2026-07-08: Skeptic fix — probes no longer write `manual_verification.md`; downgraded board; jump uses real input; dig labeled data-only; `verify_evidence_split.gd`.
- 2026-07-08: **P0 pickaxe bug** — `weapon_controller.gd` category check (GDScript.is_tool shadow).
- 2026-07-08: `verify_display_probe_contract.gd` — jump input + dig label + evidence path guards.
- 2026-07-08: Smoke/display corroboration infrastructure, 26 verify suites.