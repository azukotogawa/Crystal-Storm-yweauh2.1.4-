extends SceneTree
## Runs smoke wrapper and proves manual_verification.md is untouched.

const _ProbePaths = preload("res://scripts/probe_paths.gd")
const WRAPPER := "res://scripts/run_smoke_gameplay.sh"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var manual_path := _ProbePaths.manual_verification_path()
	var smoke_evidence := _ProbePaths.smoke_evidence_path()
	if not FileAccess.file_exists(manual_path):
		push_error("missing manual_verification.md")
		quit(1)
		return
	var before := FileAccess.get_file_as_string(manual_path)
	if "human-hand ONLY" not in before:
		push_error("manual_verification.md must be human-hand template before probe")
		ok = false
	elif "PENDING" not in before and "Working" not in before:
		push_error("manual_verification.md must be PENDING or Working before probe")
		ok = false
	var wrapper := ProjectSettings.globalize_path(WRAPPER)
	if not FileAccess.file_exists(wrapper):
		push_error("missing run_smoke_gameplay.sh")
		quit(1)
		return
	var output: Array = []
	var exit_code := OS.execute(
		"bash",
		["-c", "SMOKE_SESSION_SEC=10 %s" % wrapper],
		output,
		true,
		false
	)
	if exit_code != 0:
		push_error("smoke wrapper failed exit=%d" % exit_code)
		ok = false
	var text := "\n".join(output)
	if "double free or corruption" in text:
		push_error("smoke log must not contain double-free after abrupt exit")
		ok = false
	var after := FileAccess.get_file_as_string(manual_path)
	if after != before:
		push_error("manual_verification.md changed after smoke probe")
		ok = false
	if not FileAccess.file_exists(smoke_evidence):
		push_error("scripted_smoke_evidence.md not written at %s" % smoke_evidence)
		ok = false
	else:
		var evidence := FileAccess.get_file_as_string(smoke_evidence)
		if "chunk mesh surface_y" not in evidence:
			push_error("smoke evidence missing chunk mesh dig corroboration")
			ok = false
		if "SMOKE GAMEPLAY OK" not in text and "**Session OK**" not in evidence:
			push_error("smoke evidence missing session OK marker")
			ok = false
	if ok:
		print("OK manual pristine after smoke probe")
	quit(0 if ok else 1)