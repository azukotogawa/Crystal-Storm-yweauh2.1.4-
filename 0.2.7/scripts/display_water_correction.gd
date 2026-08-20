extends SceneTree
## Windowed water after-correction sample on production main (no yard teleports).

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("no main scene")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		push_error("start region not ready")
		quit(1)
		return
	for _w in 20:
		await process_frame
	var worst_us := 0
	var slept := 0
	var last: Dictionary = {}
	for _i in 30:
		await process_frame
		var fluid = get_first_node_in_group("voxel_fluid_service")
		if fluid == null or not fluid.has_method("get_sim_diagnostics"):
			continue
		last = fluid.get_sim_diagnostics()
		var us: int = int(last.get("last_tick_us", 0))
		if us > worst_us:
			worst_us = us
		if bool(last.get("sleeping", false)):
			slept += 1
	print("WATER_AFTER sleeping=%d/30 worst_us=%d last=%s" % [slept, worst_us, str(last)])
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if not scratch.is_empty():
		var f := FileAccess.open(scratch.path_join("water_after.json"), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({
				"sleep_frames": slept,
				"worst_tick_us": worst_us,
				"last": last,
			}, "\t"))
			f.close()
	_ProbeExit.finish_tree(self, 0, "WATER CORRECTION SAMPLE OK")
