extends SceneTree
func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
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
	# Order: dependents first, then chunk world
	var order = [
		"Player",
		"GameManager", 
		"CrystalManager",
		"WorldVisuals",
		"WorldFeatures",
		"TerrainEditor",
		"SaveGameService",
		"SpatialQueryService",
		"VoxelWorld", # contains ChunkManager
		"World",
		"GameVisualRegistry",
		"PerformanceService",
		"ConfigService",
		"CompositionRoot",
	]
	for n in order:
		var node = game.get_node_or_null(n)
		if node == null:
			# ChunkManager may live under VoxelWorld only
			print("[REPRO] skip missing ", n)
			continue
		print("[REPRO] freeing ", n, " class=", node.get_class())
		if n == "VoxelWorld" or n == "Player":
			var cmg = get_first_node_in_group("chunk_manager")
			if cmg and cmg.has_method("release_all_chunks_for_teardown"):
				print("[REPRO] release_all chunks=", cmg.chunks.size())
				cmg.release_all_chunks_for_teardown()
				await process_frame
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()
		await process_frame
		print("[REPRO] OK freed ", n)
	print("[REPRO] quit after full strip")
	quit(0)
