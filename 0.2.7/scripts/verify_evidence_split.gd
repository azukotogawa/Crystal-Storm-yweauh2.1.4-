extends SceneTree
## Ensures automated probes do not write manual_verification.md.

const _ProbePaths = preload("res://scripts/probe_paths.gd")
const DISPLAY_PROBE := "res://scripts/display_session_probe.gd"
const SMOKE := "res://scripts/smoke_gameplay.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var display_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(DISPLAY_PROBE))
	if 'SCRATCH_PATH := "' in display_text and "manual_verification.md" in display_text.split("SCRATCH_PATH")[1].split("\n")[0]:
		push_error("display_session_probe must not write manual_verification.md")
		ok = false
	if "display_session_evidence.md" not in display_text:
		push_error("display_session_probe must write display_session_evidence.md")
		ok = false
	var smoke_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(SMOKE))
	if 'SCRATCH_PATH := "' in smoke_text and "manual_verification.md" in smoke_text.split("SCRATCH_PATH")[1].split("\n")[0]:
		push_error("smoke_gameplay must not write manual_verification.md")
		ok = false
	var manual_path := _ProbePaths.manual_verification_path()
	if FileAccess.file_exists(manual_path):
		var manual := FileAccess.get_file_as_string(manual_path)
		if "PENDING" not in manual and "human-hand ONLY" not in manual:
			push_error("manual_verification.md must remain human-hand template")
			ok = false
		if "Display window probe" in manual and "PENDING" not in manual:
			push_error("manual_verification.md appears auto-filled by probe")
			ok = false
	else:
		push_error("manual_verification.md missing at %s" % manual_path)
		ok = false
	if ok:
		print("OK evidence split audit")
	quit(0 if ok else 1)