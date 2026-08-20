extends SceneTree
func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_run")
func _run() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f:=0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f+=1
	for _i in 90:
		await process_frame
	print("[REPRO] compose.shutdown then quit (no queue_free)")
	if compose: compose.shutdown()
	await process_frame
	quit(0)
