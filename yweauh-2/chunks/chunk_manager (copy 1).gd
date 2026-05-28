class_name ChunkManager
extends Node

const CHUNK_SIZE_x = 16
const CHUNK_SIZE_y = 16

@export var world: InfiniteNoiseWorld     
@export var tile_set: TileSet

var chunks: Dictionary = {}
var camera: Camera2D
var current_angle_index: int = 0

var loading_queue: Array[Vector2i] = []
var biome_data_cache: Dictionary = {}

func update(grid_tile_pos: Vector2):
	# 1. Directly locate the player's current unrotated chunk indices on the tile grid model
	var player_chunk_x = int(floor(grid_tile_pos.x / CHUNK_SIZE_x))
	var player_chunk_y = int(floor(grid_tile_pos.y / CHUNK_SIZE_y))

	# 2. Scan a square visibility grid around the player.
	# We use a symmetrical radius of 5 chunks so that no matter how the camera rotates on the GPU,
	# the view space is always fully populated with chunks and never runs out of bounds.
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var target_key = Vector2i(player_chunk_x + dx, player_chunk_y + dy)
			
			if not chunks.has(target_key) and not loading_queue.has(target_key):
				loading_queue.append(target_key)

	# 3. Process the loading queue sequentially over consecutive frames
	var chunks_processed_this_frame = 0
	while loading_queue.size() > 0 and chunks_processed_this_frame < 3:
		var next_chunk = loading_queue.pop_front()
		_load_chunk(next_chunk.x, next_chunk.y)
		chunks_processed_this_frame += 1

	# 4. Clean up distant chunks outside the standard tracking margin
	for key in chunks.keys():
		var rel_cx = key.x - player_chunk_x
		var rel_cy = key.y - player_chunk_y
		
		# Safely unload if chunks fall outside the extended loading visibility window
		if abs(rel_cx) > 6 or abs(rel_cy) > 6:
			_unload_chunk(key.x, key.y)

func _load_chunk(cx: int, cy: int):
		
	var key = Vector2i(cx, cy)
	if chunks.has(key):
		return
		
	# Instantiates the chunk using true unrotated data coordinates
	var chunk = Chunk.new(cx, cy, world) 
	chunk.mask_viewport = get_node("/root/Main/WorldContainer/SubViewport")
	chunk.current_angle_index = current_angle_index 
	chunk.generate(tile_set) 
	
	# Project this chunk origin using the exact same isometric metrics as main.gd
	var chunk_start_grid = Vector2i(cx * CHUNK_SIZE_x, cy * CHUNK_SIZE_y)
	chunk.position = IsoMath.grid_to_screen(chunk_start_grid)
		
	var container = get_node_or_null("/root/Main/WorldContainer") 
	if container:
		container.add_child(chunk) 
	else: 
		add_child(chunk) 
		
	chunks[key] = chunk
	
func _unload_chunk(cx: int, cy: int):
	var key = Vector2i(cx, cy)
	if chunks.has(key):
		var chunk = chunks[key]
		if chunk and is_instance_valid(chunk):
			if chunk.has_method("clear_chunk_tiles"):
				chunk.clear_chunk_tiles()
			if chunk.get_parent():
				chunk.get_parent().remove_child(chunk)
			chunk.queue_free()
		chunks.erase(key)

func clear_all_active_chunks():
	loading_queue.clear()
	chunks.clear()
	var container = get_node_or_null("/root/Main/WorldContainer")
	var root_node = container if container else self
	for child in root_node.get_children():
		if child is Chunk:
			if child.has_method("clear_chunk_tiles"):
				child.clear_chunk_tiles()
			child.queue_free()

func get_cached_biome_data(wx: int, wy: int) -> Dictionary:
	var cache_key = Vector2i(wx, wy)
	if biome_data_cache.has(cache_key):
		return biome_data_cache[cache_key]
		
	var fresh_data = world.get_biome(wx, wy)
	biome_data_cache[cache_key] = fresh_data
	return fresh_data
	
func get_drift_at(grid_pos: Vector2i) -> Vector2i:
	var cx = int(floor(grid_pos.x / 16.0))
	var cy = int(floor(grid_pos.y / 16.0))
	var chunk_key = Vector2i(cx, cy)

	if chunks.has(chunk_key):
		var chunk = chunks[chunk_key]
		var local_pos = Vector2i(grid_pos.x % 16, grid_pos.y % 16)
		return chunk.drift_map.get(local_pos, Vector2i.ZERO)
	return Vector2i.ZERO

func get_chunk_at(grid_pos: Vector2i) -> Chunk:
	# 1. Calculate chunk coordinates based on your 16x16 size
	var cx = int(floor(grid_pos.x / 16.0))
	var cy = int(floor(grid_pos.y / 16.0))
	var chunk_key = Vector2i(cx, cy)

	# 2. Return the chunk if it exists in your dictionary
	if chunks.has(chunk_key):
		return chunks[chunk_key]

	return null
