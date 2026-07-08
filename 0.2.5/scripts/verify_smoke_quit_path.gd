extends SceneTree
## Proves smoke emits exactly one terminal marker; forced fail must not print OK.

const ROOT := "res://"
const WRAPPER := "res://scripts/run_smoke_gameplay.sh"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _run_case("pass", "", true) and ok
	ok = _run_case("fail_entities", "entities", false) and ok
	ok = _run_case("fail_all", "1", false) and ok
	if ok:
		print("All smoke quit-path tests OK")
	quit(0 if ok else 1)


func _run_case(label: String, force_env: String, expect_ok: bool) -> bool:
	var wrapper := ProjectSettings.globalize_path(WRAPPER)
	if not FileAccess.file_exists(wrapper):
		push_error("missing run_smoke_gameplay.sh")
		return false
	var cmd := "bash \"%s\"" % wrapper
	if not force_env.is_empty():
		cmd = "SMOKE_FORCE_FAIL=%s %s" % [force_env, cmd]
	var output: Array = []
	var exit_code := OS.execute("bash", ["-c", cmd], output, true, false)
	var text := "\n".join(output)
	print("--- quit-path case %s wrapper_exit=%d ---" % [label, exit_code])
	var ok_count := text.count("SMOKE GAMEPLAY OK")
	var fail_count := text.count("SMOKE GAMEPLAY FAILED")
	if expect_ok:
		if exit_code != 0:
			push_error("case %s wrapper expected 0 got %d" % [label, exit_code])
			return false
		if ok_count != 1 or fail_count != 0:
			push_error("case %s expected single OK got ok=%d fail=%d" % [label, ok_count, fail_count])
			return false
		if "**Dig FAIL**" in text or "**Entities FAIL**" in text:
			push_error("case %s unexpected FAIL body markers" % label)
			return false
	else:
		if exit_code == 0:
			push_error("case %s wrapper expected non-zero got 0" % label)
			return false
		if fail_count != 1 or ok_count != 0:
			push_error("case %s expected single FAILED got ok=%d fail=%d" % [label, ok_count, fail_count])
			return false
	print("OK quit-path case %s" % label)
	return true