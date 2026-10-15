extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _STP = preload("res://systems/startup_total_profiler.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const MAX_WAIT_FRAMES := 90000


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_STARTUP_TOTAL_PROFILE", "1")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _scratch_dir() -> String:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = ProjectSettings.globalize_path("res://")
	return scratch


func _run() -> void:
	var run_label := OS.get_environment("CRYSTALSTORM_STARTUP_RUN")
	if run_label.is_empty():
		run_label = "unnamed"
	_STP.begin_session(run_label)
	_STP.event("profile_script.start", {
		"run": run_label,
		"engine_ms": Time.get_ticks_msec(),
		"user_data": OS.get_user_data_dir(),
	}, "process_start")

	var t_load := Time.get_ticks_usec()
	_STP.begin("PackedScene.load_main", "resource_loading")
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	_STP.end("PackedScene.load_main", {"ok": packed != null})
	if packed == null:
		_write_and_quit(1, "STARTUP_TOTAL_PROFILE FAILED: main missing")
		return

	_STP.begin("PackedScene.instantiate_main", "resource_loading")
	var game: Node = packed.instantiate()
	_STP.end("PackedScene.instantiate_main")
	_STP.event("main_scene.instantiated", {
		"load_instantiate_us": Time.get_ticks_usec() - t_load,
	}, "scene_load")

	root.add_child(game)
	_STP.event("main_scene.added_to_tree", {}, "scene_load")

	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	var saw_playable := false
	while frames < MAX_WAIT_FRAMES:
		if compose != null and bool(compose.get("_boot_done")):
			break
		if not saw_playable and _STP.report().get("playable_us", -1) >= 0:
			saw_playable = true
		await process_frame
		frames += 1

	for _i in 45:
		await process_frame

	var extra := {
		"frames_waited": frames,
		"boot_done": compose != null and bool(compose.get("_boot_done")),
		"compose_stage": str(compose.get_stage_name()) if compose and compose.has_method("get_stage_name") else "",
		"compose_elapsed_ms": (compose.get_diagnostics().get("elapsed_ms", -1) if compose and compose.has_method("get_diagnostics") else -1),
	}
	_STP.event("profile_script.complete", extra, "process_start")
	_STP.set_gauge("frames_waited", frames)
	_STP.set_gauge("boot_done", extra.boot_done)

	var scratch := _scratch_dir()
	var path := scratch.path_join("startup_phase_timings_%s.json" % run_label)
	_STP.write_report(path)
	_STP.write_report(scratch.path_join("startup_phase_timings.json"))
	print("STARTUP_TOTAL_PROFILE_OK run=%s wall_s=%.2f playable_ms=%.1f file=%s" % [
		run_label,
		float(_STP.now_us()) / 1_000_000.0,
		float(_STP.report().get("playable_ms", -1.0)),
		path,
	])
	_ProbeExit.finish_tree(self, 0, "STARTUP_TOTAL_PROFILE_OK")


func _write_and_quit(code: int, marker: String) -> void:
	_STP.write_report(_scratch_dir().path_join("startup_phase_timings.json"))
	_ProbeExit.finish_tree(self, code, marker)
