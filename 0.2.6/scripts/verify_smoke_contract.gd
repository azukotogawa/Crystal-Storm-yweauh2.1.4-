extends SceneTree
## Audits smoke_gameplay.gd source + wrapper for skeptic-flagged regressions.

const SMOKE := "res://scripts/smoke_gameplay.gd"
const WRAPPER := "res://scripts/run_smoke_gameplay.sh"
const HELPERS := "res://scripts/smoke_probe_helpers.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var smoke_path := ProjectSettings.globalize_path(SMOKE)
	var text := FileAccess.get_file_as_string(smoke_path)
	if text.is_empty():
		push_error("could not read smoke_gameplay.gd")
		quit(1)
		return
	if "terrain.try_dig" in text:
		push_error("smoke must not call terrain.try_dig for dig proof")
		ok = false
	if "terrain_editor.try_dig" in text:
		push_error("smoke must not bypass WeaponController with terrain_editor.try_dig")
		ok = false
	if 'weapon.call("_try_dig")' not in text:
		push_error("smoke must call weapon.call(\"_try_dig\") on production dig path")
		ok = false
	if "warp_mouse_to_column" not in text and "position_player_for_forward_dig" not in text:
		push_error("smoke must position/warp for WeaponController dig targeting")
		ok = false
	if "resolve_action" not in text or '&"dig"' not in text:
		push_error("smoke must resolve dig action via ActionTargeting before _try_dig")
		ok = false
	if "session_digs_ok" not in text:
		push_error("smoke sustained session must track successful digs (session_digs_ok)")
		ok = false
	if 'SCRATCH_PATH := "' in text and "manual_verification.md" in text.split("SCRATCH_PATH")[1]:
		push_error("smoke SCRATCH_PATH must not be manual_verification.md")
		ok = false
	if "scripted_smoke_evidence.md" not in text and "smoke_evidence_path" not in text:
		push_error("smoke must write scripted_smoke_evidence.md only")
		ok = false
	if "probe_exit.gd" not in text or "_ProbeExit.finish_tree" not in text:
		push_error("smoke _finish must call probe_exit.finish_tree")
		ok = false
	if "Vector3(1.0, 8.0" in text or "+ Vector3(1.0, 8.0" in text:
		push_error("smoke must not Y-teleport for jump test")
		ok = false
	if 'Input.action_press("jump")' not in text:
		push_error("smoke must use jump input for P1 jump test")
		ok = false
	if 'Input.action_press("ui_right")' not in text:
		push_error("smoke must use ui_right for jump-while-moving test")
		ok = false
	if "chunk mesh surface_y" not in text:
		push_error("smoke must corroborate dig with chunk mesh surface_y")
		ok = false
	if "Combat VFX" not in text:
		push_error("smoke must include combat VFX section")
		ok = false
	if "Melee entity damage" not in text:
		push_error("smoke must include melee entity damage section")
		ok = false
	if "Sustained session" not in text:
		push_error("smoke must include sustained session section")
		ok = false
	if "Build / stone wall" not in text:
		push_error("smoke must include build wall section")
		ok = false
	if "Built wall collision" not in text or "check_built_wall_collision" not in text:
		push_error("smoke must corroborate built-wall collision via smoke_probe_helpers")
		ok = false
	if "audit_ramp_step_corner_walk" not in text:
		push_error("smoke must audit step-corner walk via smoke_probe_helpers")
		ok = false
	if "audit_crystal_frontier_holes" not in text:
		push_error("smoke must audit crystal frontier envelope via smoke_probe_helpers")
		ok = false
	if "SMOKE_SCENARIO" not in text or "scenario_presets.gd" not in text:
		push_error("smoke must support SMOKE_SCENARIO via scenario_presets")
		ok = false
	if "smoke_probe_helpers.gd" not in text:
		push_error("smoke must use smoke_probe_helpers for audits")
		ok = false
	if "audit_loaded_chunks" not in text:
		push_error("smoke must audit loaded chunks for streaming holes")
		ok = false
	if not FileAccess.file_exists(ProjectSettings.globalize_path(HELPERS)):
		push_error("missing smoke_probe_helpers.gd")
		ok = false
	var wrapper_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(WRAPPER))
	if "CRYSTALSTORM_PROBE_ABRUPT_EXIT=1" not in wrapper_text:
		push_error("smoke wrapper must set CRYSTALSTORM_PROBE_ABRUPT_EXIT=1")
		ok = false
	var wrapper_path := ProjectSettings.globalize_path(WRAPPER)
	if not FileAccess.file_exists(wrapper_path):
		push_error("missing run_smoke_gameplay.sh")
		ok = false
	if ok:
		print("OK smoke contract audit")
	quit(0 if ok else 1)