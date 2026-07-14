extends SceneTree
## Proves smoke emits exactly one terminal marker; forced fail must not print OK.


const WRAPPER := "res://scripts/run_smoke_gameplay.sh"
const _ProbePaths = preload("res://scripts/probe_paths.gd")

const PASS_SESSION_SEC := "45"
const PASS_ATTEMPTS := 2


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _run_pass_case() and ok
	ok = _run_case("fail_entities", "entities", false) and ok
	ok = _run_case("fail_all", "1", false) and ok
	if ok:
		print("All smoke quit-path tests OK")
	quit(0 if ok else 1)


func _run_pass_case() -> bool:
	for attempt in range(1, PASS_ATTEMPTS + 1):
		if _run_case("pass", "", true, attempt):
			return true
		if attempt < PASS_ATTEMPTS:
			print("retry smoke quit-path pass attempt %d/%d" % [attempt + 1, PASS_ATTEMPTS])
	return false


func _run_case(label: String, force_env: String, expect_ok: bool, attempt: int = 1) -> bool:
	var wrapper := ProjectSettings.globalize_path(WRAPPER)
	if not FileAccess.file_exists(wrapper):
		push_error("missing run_smoke_gameplay.sh")
		return false

	var scratch_root := _ProbePaths.scratch_dir()
	var case_scratch := "%s/smoke_quit_%s" % [scratch_root, label]
	DirAccess.make_dir_recursive_absolute(case_scratch)
	var log_path := "%s/smoke_quit_%s_%d.log" % [scratch_root, label, attempt]

	var env_parts: PackedStringArray = [
		"CRYSTALSTORM_SCRATCH=%s" % case_scratch,
		"SMOKE_LOG=%s" % log_path,
	]
	if label == "pass":
		env_parts.append("SMOKE_SESSION_SEC=%s" % PASS_SESSION_SEC)
	if not force_env.is_empty():
		env_parts.append("SMOKE_FORCE_FAIL=%s" % force_env)
	var cmd := "%s bash \"%s\"" % [" ".join(env_parts), wrapper]

	var output: Array = []
	var exit_code := OS.execute("bash", ["-c", cmd], output, true, false)
	var text := _read_log_text(log_path, output)
	print("--- quit-path case %s attempt=%d wrapper_exit=%d ---" % [label, attempt, exit_code])

	var ok_count := text.count("SMOKE GAMEPLAY OK")
	var fail_count := text.count("SMOKE GAMEPLAY FAILED")
	if expect_ok:
		if exit_code != 0:
			push_error("case %s expected wrapper exit 0 got %d (log=%s)" % [label, exit_code, log_path])
			_emit_log_tail(text)
			return false
		if ok_count != 1 or fail_count != 0:
			push_error("case %s expected single OK got ok=%d fail=%d" % [label, ok_count, fail_count])
			_emit_log_tail(text)
			return false
		if "**Dig FAIL**" in text or "**Entities FAIL**" in text:
			push_error("case %s unexpected FAIL body markers" % label)
			_emit_log_tail(text)
			return false
	else:
		if exit_code == 0:
			push_error("case %s wrapper expected non-zero got 0" % label)
			_emit_log_tail(text)
			return false
		if fail_count != 1 or ok_count != 0:
			push_error("case %s expected single FAILED got ok=%d fail=%d" % [label, ok_count, fail_count])
			_emit_log_tail(text)
			return false
	print("OK quit-path case %s" % label)
	return true


func _read_log_text(log_path: String, output: Array) -> String:
	if FileAccess.file_exists(log_path):
		return FileAccess.get_file_as_string(log_path)
	return "\n".join(output)


func _emit_log_tail(text: String) -> void:
	var lines := text.split("\n")
	var tail_start := maxi(lines.size() - 12, 0)
	for i in range(tail_start, lines.size()):
		if not lines[i].strip_edges().is_empty():
			print(lines[i])