extends Control

@onready var label = $DebugLabel

var _update_counter := 0
const DEBUG_UPDATE_EVERY := 12

func _process(_delta: float) -> void:
	if not label:
		return
	
	_update_counter += 1
	if _update_counter % DEBUG_UPDATE_EVERY != 0:
		return

	var seed_val := "???"
	var chunks_count := 0
	var player_voxel := Vector3.ZERO
	var current_chunk := Vector2i.ZERO
	var biome_name := "???"
	var tile_name := "Unknown"
	var h := "???"
	var cam_rot := 0
	var crystal_tiles := 0
	var crystal_power := 0.0
	var crystal_tier := 0
	var crystal_frontier := 0
	var crystal_dist := "???"

	# Find main nodes safely
	var main = get_tree().root.get_node_or_null("Game")
	var player = get_tree().get_first_node_in_group("player")
	var world = get_tree().get_first_node_in_group("world")
	var camera = get_tree().get_first_node_in_group("camera")
	var chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	var crystal_manager = get_tree().get_first_node_in_group("crystal_manager")

	# Seed
	if world and "world_seed" in world:
		seed_val = str(world.world_seed)

	# Chunks
	if chunk_manager:
		if chunk_manager.has_method("get_chunk_count"):
			chunks_count = chunk_manager.get_chunk_count()
		else:
			var prop_list = chunk_manager.get_property_list()
			var has_chunks_prop := false
			for prop in prop_list:
				if prop.name == "chunks":
					has_chunks_prop = true
					break
			if has_chunks_prop:
				var chunks_prop = chunk_manager.get("chunks")
				if chunks_prop is Dictionary:
					chunks_count = chunks_prop.size()
				elif chunks_prop is Array:
					chunks_count = chunks_prop.size()

	# Player position
	if player:
		if player.has_method("get_voxel_position"):
			player_voxel = player.get_voxel_position()
		elif "voxel_position" in player:
			player_voxel = player.voxel_position
		elif "global_position" in player:
			player_voxel = player.global_position

	# Current chunk
	if player_voxel != Vector3.ZERO:
		current_chunk = Vector2i(
			floori(player_voxel.x / ChunkData.SIZE),
			floori(player_voxel.z / ChunkData.SIZE)
		)

	# Biome & Tile
	if world and player_voxel != Vector3.ZERO:
		var biome = world._get_biome_compute(player_voxel.x, 0.0, player_voxel.z)
		if biome is Dictionary:
			if "type" in biome and biome.type != null:
				biome_name = str(biome.type)
			elif "name" in biome and biome.name != null:
				biome_name = str(biome.name).capitalize()
			else:
				biome_name = "Unknown"
		else:
			biome_name = "None (invalid biome dict)"

		var raw_tile = world.get_tile_type(player_voxel.x, player_voxel.z)
		if raw_tile == 37:
			tile_name = "RIVER"
		else:
			tile_name = str(raw_tile)

	# Height
	if world and player_voxel != Vector3.ZERO:
		h = "%.1f" % world.get_surface_height_uncached(player_voxel.x, player_voxel.z)

	# Camera rotation
	if camera and "rotation_degrees" in camera:
		cam_rot = int(camera.rotation_degrees.y)

	# Crystal
	if crystal_manager and crystal_manager.has_method("get_debug_stats"):
		var stats: Dictionary = crystal_manager.get_debug_stats()
		crystal_tiles = int(stats.get("tiles", 0))
		crystal_power = float(stats.get("power", 0.0))
		crystal_tier = int(stats.get("tier", 0))
		crystal_frontier = int(stats.get("frontier", 0))
	if crystal_manager and player_voxel != Vector3.ZERO and crystal_manager.has_method("get_nearest_crystal_distance"):
		var dist: float = crystal_manager.get_nearest_crystal_distance(player_voxel)
		if dist == INF:
			crystal_dist = "none"
		else:
			crystal_dist = "%.1f" % dist

	label.text = """Seed: %s
Voxel Pos: %.1f, %.1f, %.1f
Chunk: %d, %d
Chunks Loaded: %d
Tile: %s
Biome: %s
Height: %s
Cam Rot: %d
Crystal Tiles: %d
Crystal Power: %.1f (T%d)
Crystal Frontier: %d
Nearest Crystal: %s
FPS: %d""" % [
		seed_val,
		player_voxel.x, player_voxel.y, player_voxel.z,
		current_chunk.x, current_chunk.y,
		chunks_count,
		tile_name,
		biome_name,
		h,
		cam_rot,
		crystal_tiles,
		crystal_power, crystal_tier,
		crystal_frontier,
		crystal_dist,
		Engine.get_frames_per_second()
	]
