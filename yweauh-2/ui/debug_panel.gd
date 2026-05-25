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
	var player_pos = Vector2.ZERO
	
	var main = get_tree().get_root().get_node_or_null("Main")
	if main:
		seed_val = str(main.get("current_seed") if main.get("current_seed") != null else "???")
		
		if main.has_node("Player"):
			player_pos = main.get_node("Player").position

		var raw_tile_pos = main.get("raw_world_tile_pos")
		var world_node = main.get("world")
		
		if raw_tile_pos != null and world_node != null:
	# Convert player screen position to grid coordinates
			var grid_pos = IsoMath.screen_to_grid(player_pos)
			px = int(floor(grid_pos.x))
			py = int(floor(grid_pos.y))
			
			cx = int(floor(px / 16.0))
			cy = int(floor(py / 16.0))
			var biome = world_node.get_biome(grid_pos.x, grid_pos.y)
			
			if biome:
				h_level = str(biome.get("render_height", biome.get("h_level", "??")))
				p_level = str(biome.get("p_level", "??"))
				tile_name = str(biome.get("name", "??"))
		
		var cm = main.get_node_or_null("ChunkManager")
		if cm and cm.get("chunks") != null:
			chunks = cm.chunks.size()
			
	label.text = "Seed: %s\nPos: %.0f, %.0f\nTile: %s\nh_level: %s | p_level: %s\nFPS: %d\nChunks: %d\nPlayer Tile: %d, %d\nChunk: %d, %d" % [
		seed_val,
		player_pos.x, player_pos.y,
		tile_name,
		h_level,
		p_level,
		Engine.get_frames_per_second(),
		chunks,
		px, py,
		cx, cy
	]
