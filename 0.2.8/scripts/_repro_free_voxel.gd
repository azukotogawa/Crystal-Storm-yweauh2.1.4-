extends SceneTree
func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_SHUTDOWN_TRACE", "1")
	call_deferred("_go")
func _go() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f:=0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f+=1
	for _i in 45:
		await process_frame
	var cmg = get_first_node_in_group("chunk_manager")
	print("[REPRO] chunks=", cmg.chunks.size() if cmg else -1)
	if cmg:
		cmg.release_all_chunks_for_teardown()
	await process_frame
	await process_frame
	print("[REPRO] after release children of voxel:")
	var vw = game.get_node_or_null("VoxelWorld")
	if vw:
		for c in vw.get_children():
			print("  child ", c.name, " ", c.get_class())
		print("[REPRO] free VoxelWorld")
		game.remove_child(vw)
		vw.free()
	await process_frame
	print("[REPRO] VoxelWorld free OK, quit")
	quit(0)
