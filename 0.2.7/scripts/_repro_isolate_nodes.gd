extends SceneTree
## Remove named nodes from main.tscn before add_child to isolate double-free.

func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_go")


func _go() -> void:
	var mode := OS.get_environment("CRYSTALSTORM_ISOLATE")
	if mode.is_empty():
		mode = "NO_VOXEL"
	print("[ISO_NODES] mode=", mode)

	var kill: PackedStringArray = []
	match mode:
		"NO_VOXEL":
			kill = PackedStringArray(["VoxelWorld"])
		"NO_VOXEL_PLAYER":
			kill = PackedStringArray(["VoxelWorld", "Player"])
		"NO_VOXEL_CRYSTAL":
			kill = PackedStringArray(["VoxelWorld", "CrystalManager"])
		"NO_VOXEL_PLAYER_CRYSTAL_VIS":
			kill = PackedStringArray(["VoxelWorld", "Player", "CrystalManager", "WorldVisuals"])
		"ONLY_SERVICES":
			# Keep only config/perf/composition/world - no voxel, player, crystal, features, UI
			kill = PackedStringArray([
				"VoxelWorld", "Player", "CrystalManager", "WorldVisuals",
				"WorldFeatures", "TerrainEditor", "SaveGameService",
				"SpatialQueryService", "GameManager", "CanvasLayer",
				"DeveloperAssistant", "WorldEnvironment", "DirectionalLight3D",
				"World",
			])
		"ONLY_VOXEL":
			# Strip everything except VoxelWorld path + services needed to boot chunks
			kill = PackedStringArray([
				"Player", "CrystalManager", "WorldVisuals",
				"WorldFeatures", "TerrainEditor", "SaveGameService",
				"SpatialQueryService", "GameManager", "CanvasLayer",
				"DeveloperAssistant",
			])
		"FULL":
			kill = PackedStringArray([])
		_:
			print("[ISO_NODES] unknown ", mode)
			quit(1)
			return

	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	for name in kill:
		var n = game.get_node_or_null(name)
		if n:
			game.remove_child(n)
			n.free()
			print("[ISO_NODES] removed ", name)
		else:
			print("[ISO_NODES] missing ", name)

	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f := 0
	while compose and not bool(compose.get("_boot_done")) and f < 2400:
		await process_frame
		f += 1
		# If no compose or stuck, break early
		if compose == null:
			break
	for _i in 45:
		await process_frame

	var cm = get_first_node_in_group("chunk_manager")
	print("[ISO_NODES] boot_done=", compose.get("_boot_done") if compose else "no_compose",
		" chunks=", cm.chunks.size() if cm and "chunks" in cm else -1,
		" stage=", compose.get_stage_name() if compose and compose.has_method("get_stage_name") else "?")
	print("[ISO_NODES] quit")
	quit(0)
