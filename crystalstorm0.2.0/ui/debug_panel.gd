extends Control

@onready var label = $DebugLabel

func _process(_delta):
	if not label:
		return
	
	var seed_val = "???"
	var chunks = 0
	var h_level = "??"
	var p_level = "??"
	var tile_name = "??"
	var px = 0
	var py = 0
	var cx = 0
	var cy = 0
	var map_pos = []
	var btype = "??"
	var logical_pos = Vector3.ZERO # New variable for the debug UI
	
	if not label: return

	var main = get_tree().root.get_node_or_null("Main")
	if not main: return

	# Get Player Position first
	var player = main.get_node_or_null("Player")
	if not player: return
	var player_pos = player.position

	if main:
		seed_val = str(main.get("current_seed") if main.get("current_seed") != null else "???")
		
		if main.has_node("Player"):
			player_pos = main.get_node("Player").position

		var raw_tile_pos = main.get("raw_world_tile_pos")
		var world_node = main.get("world")
		
		if raw_tile_pos != null and world_node != null:
	# Convert player screen position to grid coordinates
			var cm = main.get_node_or_null("ChunkManager")
			var active_layer = null

			# We iterate through the chunks dictionary in the ChunkManager 
			if cm and cm.chunks.size() > 0:
				for key in cm.chunks:
					var chunk = cm.chunks[key]
					# Check if this chunk's wall_layer is valid 
					if is_instance_valid(chunk.main_layer):
						# Convert world position to local space of the chunk [cite: 15]
						var local_pos = chunk.main_layer.to_local(player_pos)
						map_pos = chunk.main_layer.local_to_map(local_pos)
						
						# If the map_pos is inside the 0-15 grid of this chunk, we found it!
						if map_pos.x >= 0 and map_pos.x < 16 and map_pos.y >= 0 and map_pos.y < 16:
							active_layer = chunk.main_layer
							# Set the grid coordinates
							px = int(floor(chunk.cx * 16 + map_pos.x))
							py = int(floor(chunk.cy * 16 + map_pos.y))
							cx = chunk.cx
							cy = chunk.cy
							break
							
			#var data_grid_pos = IsoMath.screen_to_grid(player_pos)
			# Apply the + 0.5 offset to match the Chunk's sampling logic
			#var sample_grid = Vector2(floor(data_grid_pos.x) + 0.5, floor(data_grid_pos.y) + 0.5)
			#var biome = world_node.get_biome(sample_grid.x, sample_grid.y)

			
			'''if biome:
				h_level = str(biome.get("h_level", "??"))
				p_level = str(biome.get("p_level", "??"))
				tile_name = str(biome.get("name", "??"))
				btype = str(biome.get("type"))'''
		
		var cm = main.get_node_or_null("ChunkManager")
		if cm and cm.get("chunks") != null:
			chunks = cm.chunks.size()
			
		var current_grid_pos = Vector2i(px, py)
		logical_pos = CoordMapper.get_logical_coord(current_grid_pos, world_node, cm)
			
	label.text = "Seed: %s\nPos: %.0f, %.0f\nTile: %s\nh_level: %s | p_level: %s\nFPS: %d\nChunks: %d\nPlayer Tile: %d, %d\nChunk: %d, %d\nBiome: %s\nLogical Coord: %s" % [
		seed_val,
		player_pos.x, player_pos.y,
		tile_name,
		h_level,
		p_level,
		Engine.get_frames_per_second(),
		chunks,
		px, py,
		cx, cy,
		btype,
		str(logical_pos)
	]
