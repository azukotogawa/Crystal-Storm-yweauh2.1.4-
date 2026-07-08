extends SceneTree
## Regression: run smoke via wrapper 3x; audit WeaponController + entity markers.

const WRAPPER := "res://scripts/run_smoke_gameplay.sh"
const RUNS := 3


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
		var exit_code := OS.execute("bash", [wrapper], output, true, false)
		var text := "\n".join(output)
		print("--- smoke run %d/%d wrapper_exit=%d ---" % [run_idx + 1, RUNS, exit_code])
		for line in output:
			print(line)
		if exit_code != 0:
			push_error("Smoke run %d wrapper exit %d" % [run_idx + 1, exit_code])
			ok = false
			break
		if "SMOKE GAMEPLAY FAILED" in text:
			push_error("Smoke run %d reported FAILED" % (run_idx + 1))
			ok = false
			break
		if "SMOKE GAMEPLAY OK" not in text:
			push_error("Smoke run %d missing OK marker" % (run_idx + 1))
			ok = false
			break
		if text.count("SMOKE GAMEPLAY OK") != 1 or text.count("SMOKE GAMEPLAY FAILED") != 0:
			push_error("Smoke run %d bad terminal marker count" % (run_idx + 1))
			ok = false
			break
		if "WeaponController column" not in text:
			push_error("Smoke run %d missing WeaponController dig proof" % (run_idx + 1))
			ok = false
			break
		if "EntityManager spawn" not in text:
			push_error("Smoke run %d missing EntityManager spawn proof" % (run_idx + 1))
			ok = false
			break
		if "**Dig FAIL**" in text or "**Entities FAIL**" in text or "**Vegetation FAIL**" in text:
			push_error("Smoke run %d contains FAIL markers" % (run_idx + 1))
			ok = false
			break
	if ok:
		print("All smoke gameplay tests OK (%d runs)" % RUNS)
	quit(0 if ok else 1)