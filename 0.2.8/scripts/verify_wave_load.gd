extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("wave load missing main")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var early := 0.0
	for i in 240:
		await process_frame
		if i >= 60:
			early += Engine.get_frames_per_second()
	var late := 0.0
	for _j in 180:
		await process_frame
		late += Engine.get_frames_per_second()
	var crystal = get_first_node_in_group("crystal_manager")
	var coverage := -1.0
	if crystal != null and crystal.has_method("get_coverage_ratio"):
		coverage = float(crystal.get_coverage_ratio())
	print("WAVE_FPS early=%.1f late=%.1f coverage=%.5f" % [early / 180.0, late / 180.0, coverage])
	print("WAVE LOAD OK")
	quit(0)
