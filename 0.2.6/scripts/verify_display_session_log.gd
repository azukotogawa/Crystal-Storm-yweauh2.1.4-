extends SceneTree
## Runs display wrapper; audits log for skeptic-flagged regressions.

const MANUAL := "/tmp/grok-goal-e8916ce4c6d5/implementer/manual_verification.md"
const EVIDENCE := "/tmp/grok-goal-e8916ce4c6d5/implementer/display_session_evidence.md"
const LOG := "/tmp/grok-goal-e8916ce4c6d5/implementer/display_session.log"
const WRAPPER := "res://scripts/run_display_session.sh"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	if not FileAccess.file_exists(MANUAL):
		push_error("missing manual_verification.md")
		quit(1)
		return
	var manual_before := FileAccess.get_file_as_string(MANUAL)
	if "PENDING" not in manual_before:
		push_error("manual_verification.md must be PENDING before display probe")
		ok = false
	var wrapper := ProjectSettings.globalize_path(WRAPPER)
	var output: Array = []
	OS.execute("bash", [wrapper], output, true, false)
	var log_text := "\n".join(output)
	if FileAccess.file_exists(LOG):
		log_text = FileAccess.get_file_as_string(LOG)
	if "DISPLAY SESSION OK" not in log_text:
		push_error("display log missing DISPLAY SESSION OK")
		ok = false
	if "DISPLAY SESSION FAILED" in log_text:
		push_error("display log contains FAILED marker")
		ok = false
	if "double free or corruption" in log_text.to_lower():
		push_error("display log must not contain double-free after abrupt exit")
		ok = false
	if "visible terrain edit" in log_text.to_lower():
		push_error("display log must not claim visible terrain edit")
		ok = false
	if "Vector3(1.0, 8.0" in log_text:
		push_error("display log must not show Y-teleport jump hack")
		ok = false
	var manual_after := FileAccess.get_file_as_string(MANUAL)
	if manual_after != manual_before:
		push_error("display probe changed manual_verification.md")
		ok = false
	if not FileAccess.file_exists(EVIDENCE):
		push_error("display_session_evidence.md not written")
		ok = false
	else:
		var ev := FileAccess.get_file_as_string(EVIDENCE)
		if "human visual confirm still pending" not in ev and "data only; visual confirm pending" not in ev:
			push_error("display evidence must not claim visible dig without human pending label")
			ok = false
		if "chunk mesh surface_y=" not in ev:
			push_error("display evidence must corroborate chunk mesh surface after dig")
			ok = false
		if "Jump input + ui_right" not in ev:
			push_error("display evidence must document jump via input")
			ok = false
		if "- PASS " not in ev:
			push_error("display evidence must use PASS bullets")
			ok = false
	if ok:
		print("OK display session log audit")
	quit(0 if ok else 1)