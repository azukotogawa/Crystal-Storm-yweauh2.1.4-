extends SceneTree
## Boot smoke for profiling instrumentation — ≥30 frames, no crash.


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "main boot profile FAILED")
		return
	var game: Node = main_packed.instantiate()
	root.add_child(game)
	var chunk_manager: ChunkManager = null
	for _i in 600:
		chunk_manager = get_first_node_in_group("chunk_manager")
		if chunk_manager != null and chunk_manager.chunks.size() >= 3:
			break
		await process_frame
	for _w in 30:
		await process_frame
	if chunk_manager == null or chunk_manager.chunks.size() < 3:
		_ProbeExit.finish_tree(self, 1, "main boot profile FAILED")
		return
	print("OK main boot profile chunks=%d frames=%d" % [chunk_manager.chunks.size(), Engine.get_process_frames()])
	_ProbeExit.finish_tree(self, 0, "main boot profile OK")