extends Control

@onready var label = $DebugLabel

func _process(_delta):
	if not label:
		return
	
	var seed_val = "???"
	var chunks_count = 0
	var player_voxel = Vector3.ZERO
	var current_chunk = Vector2i.ZERO
	var biome_name = "??"
	var tile_name = "Unknown"
	var h = "??"
	var cam_rot = 0
	
	var main = get_tree().root.get_node_or_null("Game")
	var player = main.get_node_or_null("Player") if main else \
		get_tree().get_first_node_in_group("player")
	var world = main.get_node_or_null("World") as InfiniteNoiseWorld if main else \
		get_tree().get_first_node_in_group("world")
	var camera = main.get_node_or_null("Player/Camera3D") if main else \
		get_tree().get_first_node_in_group("camera")
	
	# Chunk count
	var voxel_world = main.get_node_or_null("VoxelWorld") if main else null
	if voxel_world and "world" in voxel_world:
		seed_val = str(voxel_world.world.world_seed if "world_seed" in voxel_world.world else "0")
	if voxel_world and "manager" in voxel_world:
		var cm = voxel_world.manager
		chunks_count = cm.chunks.size() if cm and "chunks" in cm else 0
	
	if player:
		player_voxel = player.voxel_position if "voxel_position" in player else Vector3.ZERO
	
	if player_voxel:
		current_chunk = Vector2i(
			floori(player_voxel.x / ChunkData.SIZE),
			floori(player_voxel.y / ChunkData.SIZE)
		)
	
	if world and player_voxel:
		var biome = world.get_biome(player_voxel.x, player_voxel.y-1.0, player_voxel.z)
		if biome:
			tile_name = biome.get("name", "Unknown")
			biome_name = biome.get("type", "???")
	
	if camera:
		cam_rot = camera.orbit_rotation
	
	label.text = """Seed: %s
Voxel Pos: %.1f, %.1f, %.1f
Chunk: %d, %d
Chunks Loaded: %d
Tile: %s
Biome: %s
Cam Rot: %d
FPS: %d""" % [
		seed_val,
		player_voxel.x, player_voxel.y, player_voxel.z,
		current_chunk.x, current_chunk.y,
		chunks_count,
		tile_name,
		biome_name,
		cam_rot,
		Engine.get_frames_per_second()
	]
