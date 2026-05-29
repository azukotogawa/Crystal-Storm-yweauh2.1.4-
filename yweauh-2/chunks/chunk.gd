class_name Chunk
extends Node2D

@onready var manager = get_node_or_null("../ChunkManager")

const CHUNK_SIZE_x = 16
const CHUNK_SIZE_y = 16

var cx: int
var cy: int
var world: InfiniteNoiseWorld

var current_angle_index: int = 0

var main_layer: TileMapLayer
@export var wall_layer: TileMapLayer

var front_left_offset: Vector2i = Vector2i(-1, 0)
var front_right_offset: Vector2i = Vector2i(0, -1)
var left_wall_key: String = "front_left"
var right_wall_key: String = "front_right"

var drift_map: Dictionary = {}

var tile_registry = {
	"deep_ocean": {"top": Vector2i(0, 0), "back_left": Vector2i(0, 0), "front_right": Vector2i(0, 0), "back_right": Vector2i(0, 0), "front_left": Vector2i(0, 0)},
	"ocean": {"top": Vector2i(0, 0), "back_left": Vector2i(0, 0), "front_right": Vector2i(0, 0), "back_right": Vector2i(0, 0), "front_left": Vector2i(0, 0)},
	"shallow sea": {"top": Vector2i(0, 0), "back_left": Vector2i(0, 0), "front_right": Vector2i(0, 0), "back_right": Vector2i(0, 0), "front_left": Vector2i(0, 0)},
	"beach": {"top": Vector2i(0, 1), "back_left": Vector2i(2, 2), "front_right": Vector2i(3, 2), "back_right": Vector2i(4, 2), "front_left": Vector2i(5, 2)},
	"sandy beach": {"top": Vector2i(0, 2), "back_left": Vector2i(2, 2), "front_right": Vector2i(3, 2), "back_right": Vector2i(4, 2), "front_left": Vector2i(5, 2)},
	"coral reef": {"top": Vector2i(0, 3), "back_left": Vector2i(2, 2), "front_right": Vector2i(3, 2), "back_right": Vector2i(4, 2), "front_left": Vector2i(5, 2)},
	"grass": {"top": Vector2i(0, 4), "back_left": Vector2i(2, 4), "front_right": Vector2i(3, 4), "back_right": Vector2i(4, 4), "front_left": Vector2i(5, 4)},
	"meadow": {"top": Vector2i(0, 5), "back_left": Vector2i(2, 4), "front_right": Vector2i(3, 4), "back_right": Vector2i(4, 4), "front_left": Vector2i(5, 4)},
	"plains": {"top": Vector2i(0, 6), "back_left": Vector2i(2, 4), "front_right": Vector2i(3, 4), "back_right": Vector2i(4, 4), "front_left": Vector2i(5, 4)},
	"steppe": {"top": Vector2i(0, 7), "back_left": Vector2i(2, 4), "front_right": Vector2i(3, 4), "back_right": Vector2i(4, 4), "front_left": Vector2i(5, 4)},
	"savanna": {"top": Vector2i(0, 8), "back_left": Vector2i(2, 4), "front_right": Vector2i(3, 4), "back_right": Vector2i(4, 4), "front_left": Vector2i(5, 4)},
	"forest": {"top": Vector2i(0, 9), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"dense forest": {"top": Vector2i(0, 10), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"pine forest": {"top": Vector2i(0, 11), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"jungle": {"top": Vector2i(0, 12), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"mountain": {"top": Vector2i(0, 13), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"ridge": {"top": Vector2i(0, 14), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"peak": {"top": Vector2i(0, 15), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"volcano": {"top": Vector2i(0, 16), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"precipice": {"top": Vector2i(0, 17), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"zenith": {"top": Vector2i(0, 18), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"plateau": {"top": Vector2i(0, 19), "back_left": Vector2i(2, 6), "front_right": Vector2i(3, 6), "back_right": Vector2i(4, 6), "front_left": Vector2i(5, 6)},
	"snow": {"top": Vector2i(1, 0), "back_left": Vector2i(2, 8), "front_right": Vector2i(3, 8), "back_right": Vector2i(4, 8), "front_left": Vector2i(5, 8)},
	"ice field": {"top": Vector2i(1, 1), "back_left": Vector2i(2, 8), "front_right": Vector2i(3, 8), "back_right": Vector2i(4, 8), "front_left": Vector2i(5, 8)},
	"glacier": {"top": Vector2i(1, 2), "back_left": Vector2i(2, 8), "front_right": Vector2i(3, 8), "back_right": Vector2i(4, 8), "front_left": Vector2i(5, 8)},
	"ravine": {"top": Vector2i(1, 3), "back_left": Vector2i(2, 14), "front_right": Vector2i(3, 14), "back_right": Vector2i(4, 14), "front_left": Vector2i(5, 14)},
	"canyon": {"top": Vector2i(1, 4), "back_left": Vector2i(2, 14), "front_right": Vector2i(3, 14), "back_right": Vector2i(4, 14), "front_left": Vector2i(5, 14)},
	"valley": {"top": Vector2i(1, 5), "back_left": Vector2i(2, 14), "front_right": Vector2i(3, 14), "back_right": Vector2i(4, 14), "front_left": Vector2i(5, 14)},
	"desert": {"top": Vector2i(1, 6), "back_left": Vector2i(2, 10), "front_right": Vector2i(3, 10), "back_right": Vector2i(4, 10), "front_left": Vector2i(5, 10)},
	"dunes": {"top": Vector2i(1, 7), "back_left": Vector2i(2, 10), "front_right": Vector2i(3, 10), "back_right": Vector2i(4, 10), "front_left": Vector2i(5, 10)},
	"badlands": {"top": Vector2i(1, 8), "back_left": Vector2i(2, 10), "front_right": Vector2i(3, 10), "back_right": Vector2i(4, 10), "front_left": Vector2i(5, 10)},
	"tundra": {"top": Vector2i(1, 9), "back_left": Vector2i(2, 12), "front_right": Vector2i(3, 12), "back_right": Vector2i(4, 12), "front_left": Vector2i(5, 12)},
	"frozen plains": {"top": Vector2i(1, 10), "back_left": Vector2i(2, 12), "front_right": Vector2i(3, 12), "back_right": Vector2i(4, 12), "front_left": Vector2i(5, 12)},
	"permafrost": {"top": Vector2i(1, 11), "back_left": Vector2i(2, 12), "front_right": Vector2i(3, 12), "back_right": Vector2i(4, 12), "front_left": Vector2i(5, 12)},
	"dry lake": {"top": Vector2i(1, 12), "back_left": Vector2i(2, 14), "front_right": Vector2i(3, 14), "back_right": Vector2i(4, 14), "front_left": Vector2i(5, 14)},
	"salt flat": {"top": Vector2i(1, 13), "back_left": Vector2i(2, 14), "front_right": Vector2i(3, 14), "back_right": Vector2i(4, 14), "front_left": Vector2i(5, 14)},
	"basin": {"top": Vector2i(1, 14), "back_left": Vector2i(2, 14), "front_right": Vector2i(3, 14), "back_right": Vector2i(4, 14), "front_left": Vector2i(5, 14)},
	"river": {"top": Vector2i(1, 15), "back_left": Vector2i(2, 16), "front_right": Vector2i(3, 16), "back_right": Vector2i(4, 16), "front_left": Vector2i(5, 16)}
}

func _init(p_cx: int, p_cy: int, p_world: InfiniteNoiseWorld):
	cx = p_cx
	cy = p_cy
	world = p_world
	
func clear_chunk_tiles():
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			var current_cell = Vector2i(x, y)
			if is_instance_valid(wall_layer): 
				wall_layer.erase_cell(current_cell)
			var neighbors = [front_left_offset, front_right_offset]
			for offset in neighbors:
				var neighbor_cell = current_cell + offset
				if is_instance_valid(wall_layer):
					wall_layer.erase_cell(neighbor_cell)

func update_perspective_offsets(angle_index: int):
	match angle_index:
		0: 
			front_left_offset = Vector2i(0, 1)
			front_right_offset = Vector2i(1, 0)
			left_wall_key = "back_left"
			right_wall_key = "front_right"
		1: 
			front_left_offset = Vector2i(1, 1)
			front_right_offset = Vector2i(1, -1)
			left_wall_key = "back_right"
			right_wall_key = "front_right"
		2: 
			front_left_offset = Vector2i(0, 1)
			front_right_offset = Vector2i(1, 0)
			left_wall_key = "front_left"
			right_wall_key = "back_right"
		3: 
			front_left_offset = Vector2i(-1, -1)
			front_right_offset = Vector2i(1, -1)
			left_wall_key = "front_right"
			right_wall_key = "back_right"
		4: 
			front_left_offset = Vector2i(0, -1)
			front_right_offset = Vector2i(-1, 0)
			left_wall_key = "back_right"
			right_wall_key = "front_right"
		5: 
			front_left_offset = Vector2i(-1, -1)
			front_right_offset = Vector2i(-1, 1)
			left_wall_key = "back_left"
			right_wall_key = "front_left"
		6: 
			front_left_offset = Vector2i(-1, 0)
			front_right_offset = Vector2i(0, 1)
			left_wall_key = "back_left"
			right_wall_key = "front_left"
		7: 
			front_left_offset = Vector2i(-1, 1)
			front_right_offset = Vector2i(1, 1)
			left_wall_key = "back_left"
			right_wall_key = "front_left"

func get_angle_index():
	return {"left_offset": front_left_offset, 
	"right_offset": front_right_offset, 
	"left_key": left_wall_key, 
	"right_key": right_wall_key
	}

var height_grid_cache: Dictionary = {}
var layers_initialized: bool = false

func initialize_layers(p_tile_set: TileSet):
	if layers_initialized: return
	
	main_layer = TileMapLayer.new()
	main_layer.tile_set = p_tile_set
	main_layer.z_index = 0
	add_child(main_layer)
	
	wall_layer = TileMapLayer.new()
	wall_layer.tile_set = p_tile_set
	wall_layer.z_index = 1          # Walls above ground
	add_child(wall_layer)
	
	setup_shader()
	
	layers_initialized = true

func generate(p_tile_set: TileSet):
	initialize_layers(p_tile_set)
	main_layer.clear()
	clear_only_walls()
	update_perspective_offsets(current_angle_index)
	height_grid_cache.clear()
	
	drift_map.clear()

	# 1. Populate the cache using unified coordinate logic
	for y in range(-1, CHUNK_SIZE_y + 1):
		for x in range(-1, CHUNK_SIZE_x + 1):
			var wx = float(cx * CHUNK_SIZE_x + x)
			var wy = float(cy * CHUNK_SIZE_y + y)
			var biome_data = world.get_biome(wx + 0.5, wy + 0.5)
			if biome_data:
				height_grid_cache[Vector2i(x, y)] = {
					"height": int(biome_data.get("render_height", 0)),
					"name": biome_data.get("name", "").to_lower()
				}

	# 2. Draw the Main Layer (Ground) using the same cache
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			var current_cell = Vector2i(x, y)
			if not height_grid_cache.has(current_cell): continue
			
			var registry_entry = tile_registry[height_grid_cache[current_cell]["name"]]
			# Ensure this cell coordinate matches exactly what the wall layer will use
			main_layer.set_cell(current_cell, 6, registry_entry["top"], 0)

	# 3. Draw the walls relative to the ground tiles
	rebuild_walls_only(6)
	check_all_walls()

func rebuild_walls_only(source_id: int):
	if not is_instance_valid(wall_layer): return
	wall_layer.clear()
	
	update_perspective_offsets(current_angle_index)
	
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			var current_cell = Vector2i(x, y)
			if not height_grid_cache.has(current_cell): continue
			
			var tile_data = height_grid_cache[current_cell]
			var current_h = tile_data["height"]
			var registry_entry = tile_registry.get(tile_data["name"])
			if not registry_entry: continue
			
			# Only draw walls on the "front" sides (north relative to current view)
			var active_faces = [
				{"offset": front_left_offset, "key": left_wall_key},
				{"offset": front_right_offset, "key": right_wall_key},
			]
			
			for face in active_faces:
				var neighbor_cell = current_cell + face["offset"]
				var neighbor_data = height_grid_cache.get(neighbor_cell)
				
				# If current tile is HIGHER than the tile in front → draw wall
				if neighbor_data and current_h > neighbor_data["height"]:
					var wall_atlas = registry_entry.get(face["key"])
					if wall_atlas is Vector2i:
						wall_layer.set_cell(neighbor_cell, source_id, wall_atlas)
				
				var n_ledge_cell = current_cell + face["offset"] # Go opposite of wall direction
				var n_ledge_data = height_grid_cache.get(n_ledge_cell)
				if n_ledge_data and current_h < n_ledge_data["height"]:
					var n_tile_data = height_grid_cache[n_ledge_cell]
					var n_registry_entry = tile_registry.get(n_tile_data["name"])
					var ledge_atlas = n_registry_entry.get("top")
					if ledge_atlas is Vector2i:
						wall_layer.set_cell(n_ledge_cell, source_id, ledge_atlas, 0)
				
func change_view_angle(new_angle_index: int, source_id: int = 6):
	current_angle_index = new_angle_index
	update_perspective_offsets(current_angle_index)
	clear_only_walls()
	rebuild_walls_only(source_id)

func clear_only_walls():
	if is_instance_valid(wall_layer):
		wall_layer.clear()
		
func get_neighbor_tile_type(cell_pos: Vector2i, current_h: int) -> bool:
	var neighbors = [front_left_offset, front_right_offset]
	
	for offset in neighbors:
		var neighbor_pos = cell_pos + offset
		
		# Look up the neighbor in the cache
		var neighbor_data = height_grid_cache.get(neighbor_pos)
		
		# If the neighbor is higher than the current cell, it is "in front" 
		# and should potentially clip the wall
		if neighbor_data and neighbor_data["height"] > current_h:
			return true
			
	return false

var mask_viewport: SubViewport = null

func check_all_walls():
	if not is_instance_valid(mask_viewport):
		print("DEBUG: mask_viewport is null!")
		return
			
	var tex = mask_viewport.get_texture()
	wall_layer.material.set_shader_parameter("ground_mask", tex)

	var clippable = get_clippable_wall_cells()
	wall_layer.material.set_shader_parameter("clippable", clippable)
		
func setup_shader():
	if not is_instance_valid(wall_layer): return
	
	var shader = load("res://shaders/wall_mask.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader
	
	# FORCE the material onto the layer
	wall_layer.material = mat 
	
	# ADD THIS: Force the shader to be processed by the rendering server
	wall_layer.use_parent_material = false 

func _process(_delta):
	if is_instance_valid(wall_layer) and wall_layer.material is ShaderMaterial:
		var mat = wall_layer.material
		var vp = mask_viewport
		if vp:
			var tex = vp.get_texture()
	# This prints once every frame; if the RID changes rapidly, 
	# it means the viewport is re-initializing constantly.
			mat.set_shader_parameter("ground_mask", tex)
			if tex == null:
				print("ERROR: Shader material has NO ground_mask texture!")
				
# Returns wall cells that should be clipped (only checking the right neighbor)
func get_clippable_wall_cells() -> Array[Vector2i]:
	var clippable: Array[Vector2i] = []
	
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			var current_cell = Vector2i(x, y)
			if not height_grid_cache.has(current_cell): continue
			
			var current_h = height_grid_cache[current_cell]["height"]
			
			# Only check the RIGHT neighbor
			var right_neighbor = current_cell + front_right_offset
			
			var neighbor_data = height_grid_cache.get(right_neighbor)
			
			if neighbor_data and current_h > neighbor_data["height"]:
				clippable.append(right_neighbor)  # This wall cell should be clipped
	
	return clippable
