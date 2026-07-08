extends SceneTree
## Audits display_session_probe.gd for skeptic-flagged regressions.

const PROBE := "res://scripts/display_session_probe.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(PROBE))
	if text.is_empty():
		push_error("missing display_session_probe.gd")
		quit(1)
		return
	if 'SCRATCH_PATH := "' in text and "manual_verification.md" in text.split("SCRATCH_PATH")[1].split("\n")[0]:
		push_error("probe must not write manual_verification.md")
		ok = false
	if "display_session_evidence.md" not in text:
		push_error("probe must write display_session_evidence.md")
		ok = false
	if "visible terrain edit" in text.to_lower():
		push_error("probe must not claim visible dig without human confirmation")
		ok = false
	if "Vector3(1.0, 8.0" in text or "+ Vector3(1.0, 8.0" in text:
		push_error("probe must not Y-teleport for jump test")
		ok = false
	if 'Input.action_press("jump")' not in text:
		push_error("probe must use jump input for P1 jump test")
		ok = false
	if 'Input.action_press("ui_right")' not in text:
		push_error("probe must use ui_right for jump-while-moving test")
		ok = false
	if "data only; visual confirm pending" not in text:
		push_error("probe dig line must state data-only / visual pending")
		ok = false
	if "_ensure_texture_generator_autoload" not in text:
		push_error("probe must bootstrap CrystalTextureGenerator for SceneTree runs")
		ok = false
	if "probe_exit.gd" not in text:
		push_error("probe must use probe_exit.gd for harness teardown")
		ok = false
	if "- PASS " not in text:
		push_error("probe evidence must use PASS bullets (not manual [x] checkboxes)")
		ok = false
	if "FileAccess.open(MANUAL" in text or 'FileAccess.open("%s"' % "manual_verification" in text:
		push_error("probe must not open manual_verification.md for writing")
		ok = false
	if ok:
		print("OK display probe contract audit")
	quit(0 if ok else 1)