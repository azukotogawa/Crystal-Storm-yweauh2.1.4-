extends SceneTree
## Boot main but pause stream before first process; then quit.
func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
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
	var cm = get_first_node_in_group("chunk_manager")
	if cm:
		cm.stream_paused = true
		# Explicit release children without SceneTree conflict
		if cm.has_method("release_all_chunks_for_teardown"):
			print("[REPRO] explicit release_all before quit, views=", cm.chunks.size())
			cm.release_all_chunks_for_teardown()
		await process_frame
		await process_frame
	print("[REPRO] quit after explicit release_all")
	quit(0)
