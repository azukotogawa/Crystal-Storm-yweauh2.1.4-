extends SceneTree
## Saved player_settings.json must not replace CRYSTALSTORM_PERF_PRESET
## or stamp a leftover render_distance onto a different preset.

const _PS = preload("res://systems/player_settings.gd")
const _PQC = preload("res://config/performance_quality_config.gd")
const _Perf = preload("res://systems/performance_service.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961aca94c53e/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("test_player_settings.json")
	_PS.settings_path = path
	_PS.save_settings({
		"quality_preset": int(_PQC.Preset.MEDIUM),
		"render_distance": 5,
		"vegetation_scatter_multiplier": 1.0,
		"combat_visuals_enabled": true,
	})

	var low_cfg: _PQC = _PQC.apply_preset(_PQC.Preset.LOW)
	var low_dist: int = int(low_cfg.render_distance)

	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "low")
	var perf_env: Node = _Perf.new()
	root.add_child(perf_env)
	perf_env.quality = _PQC.apply_preset(_PQC.Preset.MEDIUM)
	perf_env.quality.render_distance = 5
	_PS.apply_to_performance(perf_env)
	if int(perf_env.quality.preset) != int(_PQC.Preset.LOW):
		push_error("env LOW overwritten by saved preset %s" % str(perf_env.quality.preset))
		failed += 1
	else:
		print("OK env LOW preset applied")
	if int(perf_env.quality.render_distance) != low_dist:
		push_error("env LOW dist=%s want preset default %s (saved slider was 5)" % [
			str(perf_env.quality.render_distance), str(low_dist)
		])
		failed += 1
	else:
		print("OK env LOW native render_distance=%d" % low_dist)

	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "")
	var perf_saved: Node = _Perf.new()
	root.add_child(perf_saved)
	perf_saved.quality = _PQC.apply_preset(_PQC.Preset.LOW)
	_PS.apply_to_performance(perf_saved)
	if int(perf_saved.quality.preset) != int(_PQC.Preset.MEDIUM):
		push_error("no-env should apply saved MEDIUM, got %s" % str(perf_saved.quality.preset))
		failed += 1
	else:
		print("OK no-env applies saved preset")
	if int(perf_saved.quality.render_distance) != 5:
		push_error("no-env saved dist want 5 got %s" % str(perf_saved.quality.render_distance))
		failed += 1
	else:
		print("OK no-env applies saved render_distance=5")

	if failed == 0:
		print("All quality preset distance tests OK")
		quit(0)
	else:
		print("QUALITY PRESET DISTANCE FAILED")
		quit(1)
