extends SceneTree
## Regression: run smoke via wrapper; audit enhanced gameplay evidence file.

const _ProbePaths = preload("res://scripts/probe_paths.gd")
const WRAPPER := "res://scripts/run_smoke_gameplay.sh"
const RUNS := 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var wrapper := ProjectSettings.globalize_path(WRAPPER)
	if not FileAccess.file_exists(wrapper):
		push_error("Missing smoke wrapper")
		quit(1)
		return
	var ok := true
	for run_idx in RUNS:
		var output: Array = []
		var exit_code := OS.execute(
			"bash",
			["-c", "SMOKE_SESSION_SEC=30 %s" % wrapper],
			output,
			true,
			false
		)
		var text := "\n".join(output)
		print("--- smoke run %d/%d wrapper_exit=%d ---" % [run_idx + 1, RUNS, exit_code])
		if exit_code != 0:
			push_error("Smoke run %d wrapper exit %d" % [run_idx + 1, exit_code])
			ok = false
			break
		var smoke_evidence := _ProbePaths.smoke_evidence_path()
		if not FileAccess.file_exists(smoke_evidence):
			push_error("Smoke run %d missing evidence file at %s" % [run_idx + 1, smoke_evidence])
			ok = false
			break
		var evidence := FileAccess.get_file_as_string(smoke_evidence)
		if "SMOKE GAMEPLAY OK" not in text and "**Session OK**" not in evidence:
			push_error("Smoke run %d missing OK marker" % (run_idx + 1))
			ok = false
			break
		if text.count("SMOKE GAMEPLAY OK") > 1 or "SMOKE GAMEPLAY FAILED" in text:
			push_error("Smoke run %d bad terminal marker count" % (run_idx + 1))
			ok = false
			break
		for marker in [
			"chunk mesh surface_y",
			"EntityManager spawn",
			"billboards textured",
			"mesh instances, no holes",
			"Combat VFX OK",
			"Session OK",
			"30s target",
		]:
			if marker not in evidence:
				push_error("Smoke run %d missing evidence marker: %s" % [run_idx + 1, marker])
				ok = false
				break
		if not ok:
			break
		if "**Dig FAIL**" in evidence or "**Entities FAIL**" in evidence or "**Vegetation FAIL**" in evidence \
				or "**Combat VFX FAIL**" in evidence or "**Session FAIL**" in evidence:
			push_error("Smoke run %d contains FAIL markers" % (run_idx + 1))
			ok = false
			break
	if ok:
		print("All smoke gameplay tests OK (%d runs)" % RUNS)
	quit(0 if ok else 1)