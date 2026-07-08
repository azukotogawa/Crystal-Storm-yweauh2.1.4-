extends SceneTree
## Runs smoke wrapper and proves manual_verification.md is untouched.

const MANUAL := "/tmp/grok-goal-e8916ce4c6d5/implementer/manual_verification.md"
const SMOKE_EVIDENCE := "/tmp/grok-goal-e8916ce4c6d5/implementer/scripted_smoke_evidence.md"
const WRAPPER := "res://scripts/run_smoke_gameplay.sh"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	if not FileAccess.file_exists(MANUAL):
		push_error("missing manual_verification.md")
		quit(1)
		return
	var before := FileAccess.get_file_as_string(MANUAL)
	if "PENDING" not in before or "human-hand ONLY" not in before:
		push_error("manual_verification.md must be human-hand template before probe")
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
	var after := FileAccess.get_file_as_string(MANUAL)
	if after != before:
		push_error("manual_verification.md changed after smoke probe")
		ok = false
	if not FileAccess.file_exists(SMOKE_EVIDENCE):
		push_error("scripted_smoke_evidence.md not written")
		ok = false
	else:
		var evidence := FileAccess.get_file_as_string(SMOKE_EVIDENCE)
		if "chunk mesh surface_y" not in evidence:
			push_error("smoke evidence missing chunk mesh dig corroboration")
			ok = false
		if "SMOKE GAMEPLAY OK" not in text and "**Session OK**" not in evidence:
			push_error("smoke evidence missing session OK marker")
			ok = false
	if ok:
		print("OK manual pristine after smoke probe")
	quit(0 if ok else 1)