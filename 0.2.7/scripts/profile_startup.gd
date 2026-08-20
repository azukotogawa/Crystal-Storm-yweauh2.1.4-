extends SceneTree
## Profile production main boot stages. Writes startup_profile.json under SCRATCH.
## Usage: CRYSTALSTORM_STARTUP_PROFILE=1 godot --headless -s scripts/profile_startup.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_STARTUP_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	# Prefer loading existing bake; do not force plan rebuild.
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		_ProbeExit.finish_tree(self, 1, "STARTUP_PROFILE FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 3600:
		await process_frame
		frames += 1
	# Allow a few more frames for first stream mesh apply.
	for _i in 30:
		await process_frame
	# Capture if CompositionRoot already wrote; else dump current profiler.
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-3c89103bbbb9/implementer"
	var path := scratch.path_join("startup_profile.json")
	if not FileAccess.file_exists(path):
		var SP = load("res://systems/startup_profiler.gd")
		if SP:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_string(SP.to_json_string())
				f.close()
			SP.print_report()
	else:
		print("STARTUP_PROFILE file exists: %s" % path)
		var txt := FileAccess.get_file_as_string(path)
		print(txt.substr(0, mini(txt.length(), 4000)))
	# Mesh plan mode evidence
	print("MESH_PLAN_NOTE see [MeshPlanCache] mode= in boot log (streamed|loaded|miss|baked)")
	if compose and bool(compose.get("_boot_done")):
		print("STARTUP_BOOT_DONE elapsed_ms=%s" % str(compose.get_diagnostics().get("elapsed_ms", -1)))
	_ProbeExit.finish_tree(self, 0, "STARTUP_PROFILE_OK")
