extends SceneTree
## Measure CrystalManager cost for first 300 frames after crystal init.
## Usage:
##   CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE=1 CRYSTALSTORM_BAKE_RADIUS=2 \
##     godot --headless -s scripts/profile_crystal_startup.gd

const MAIN := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE", "1")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/crystal-startup-measure")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_environment("CRYSTALSTORM_SCRATCH"))
	var packed: PackedScene = load(MAIN) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "CRYSTAL_MEASURE_FAIL no main")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var crystal = null
	var frames := 0
	var saw_init := false
	var report_done := false
	while frames < 6000:
		await process_frame
		frames += 1
		if crystal == null:
			crystal = get_first_node_in_group("crystal_manager")
		if crystal and bool(crystal.get("_initialized")):
			saw_init = true
		# Wait until measure report printed (300 frames after init)
		if saw_init and crystal and int(crystal.get("_measure_frame_i")) >= 300:
			report_done = true
			break
		if compose and int(compose.stage) == 9:
			break
	print("CRYSTAL_MEASURE probe_frames=%d saw_init=%s report_done=%s" % [frames, str(saw_init), str(report_done)])
	if crystal:
		print("CRYSTAL_MEASURE cells=%s expansion=%s sim_hz=%s" % [
			str(crystal.get("covered_cells")),
			str(crystal.get("expansion_enabled")),
			str(crystal.get("_perf_sim_hz")),
		])
	_ProbeExit.finish_tree(self, 0 if report_done else 1, "CRYSTAL_MEASURE_OK" if report_done else "CRYSTAL_MEASURE_INCOMPLETE")
