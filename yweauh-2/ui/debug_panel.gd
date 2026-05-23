# ui/debug_panel.gd
extends Control

@onready var label = $DebugLabel

func _process(_delta):
	if not label:
		return
	
	var seed_val = "???"
	var posx = Vector2.ZERO
	var posy = Vector2.ZERO
	var chunks = 0
	var h_level = "??"
	var p_level = "??"
	var tile_name = "??"
	var player_tile = []
	var cx = 0
	var cy = 0
	var player_pos = Vector2.ZERO
	
	var main = get_tree().get_root().get_node_or_null("Main")
	if main:
		seed_val = str(main.get("current_seed") if main.get("current_seed") != null else "???")
		
		if main.has_node("Player"):
			var player = main.get_node("Player")
			player_pos = player.position

			# Get biome at player position
			var world_node = get_node_or_null("/root/Main/World")
			if world_node is InfiniteNoiseWorld:
				var ground_layer = get_node_or_null("/root/Main/WorldContainer/WorldTileMap")
				var map_tile_coords = ground_layer.local_to_map(ground_layer.to_local(player.global_position))
				
				var x_plus_y = map_tile_coords.y
				var x_minus_y = (map_tile_coords.x * 2) - 16
				
				var sample_x = int(floor((x_plus_y + x_minus_y) / 2.0))
				var sample_y = int(floor((x_plus_y - x_minus_y) / 2.0))
				
				# 3. Sample your noise world using the corrected coordinates
				var biome = world_node.get_biome(sample_x, sample_y)
				
				h_level = str(biome.get("h_level", "??"))
				p_level = str(biome.get("p_level", "??"))
				tile_name = str(biome.get("name", "??"))
				
				player_tile = [sample_x, sample_y]
				
				cx = int(floor(sample_x / 16.0))
				cy = int(floor(sample_y / 16.0))
		
		# Chunk count
		var cm = main.get_node_or_null("ChunkManager")
		if cm and cm.get("chunks") != null:
			chunks = cm.chunks.size()
	
	label.text = """Seed: %s
Pos: %.0f, %.0f
Tile: %s
h_level: %s | p_level: %s
FPS: %d
Chunks: %d
Player Tile: %.0f, %.0f
Chunk: %.0f, %.0f""" % [
		seed_val,
		player_pos.x, player_pos.y,
		tile_name,
		h_level,
		p_level,
		Engine.get_frames_per_second(),
		chunks,
		player_tile[0], player_tile[1],
		cx, cy
	]
	
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var tile_width = 64.0
	var tile_height = 32.0
		
		# Isometric inverse transform
	var world_x = (screen_pos.x / (tile_width / 2.0) + screen_pos.y / (tile_height / 2.0)) / 2.0
	var world_y = (screen_pos.y / (tile_height / 2.0) - screen_pos.x / (tile_width / 2.0)) / 2.0

	return Vector2(world_x, world_y)
