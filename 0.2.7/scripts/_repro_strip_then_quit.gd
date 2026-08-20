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
	for _i in 30:
		await process_frame
	# Strip subsystems one by one before quit, logging
	var names = [
		"WorldVisuals",
		"WorldFeatures",
		"CrystalManager",
		"VoxelWorld",
		"World",
		"Player",
		"GameManager",
		"SaveGameService",
		"TerrainEditor",
		"PerformanceService",
		"ConfigService",
		"GameVisualRegistry",
		"SpatialQueryService",
		"CompositionRoot",
	]
	for n in names:
		var node = game.get_node_or_null(n)
		if node == null:
			continue
		print("[REPRO] freeing ", n)
		if n == "VoxelWorld":
			var cm = node.get_node_or_null("ChunkManager")
			# chunk manager may be child
			var cmg = get_first_node_in_group("chunk_manager")
			if cmg and cmg.has_method("release_all_chunks_for_teardown"):
				cmg.release_all_chunks_for_teardown()
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()
		await process_frame
		print("[REPRO] freed ", n)
	print("[REPRO] quit after strip")
	quit(0)
