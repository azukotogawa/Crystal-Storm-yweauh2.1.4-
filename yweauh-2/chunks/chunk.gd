# chunk.gd
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
var wall_layer: TileMapLayer

var front_left_offset: Vector2i = Vector2i(-1, 0)
var front_right_offset: Vector2i = Vector2i(0, -1)
var left_wall_key: String = "front_left"
var right_wall_key: String = "front_right"

var tile_registry = {
	"deep ocean": {"top": {"atlas": Vector2i(1, 0), "id": 0},"back_left": {"atlas": Vector2i(2, 0), "id": 0},"front_right": {"atlas": Vector2i(4, 0), "id": 0},"back_right": {"atlas": Vector2i(2, 0), "id": 1},"front_left": {"atlas": Vector2i(4, 0), "id": 1},},
	"ocean": {"top": {"atlas": Vector2i(1, 1), "id": 0},"back_left": {"atlas": Vector2i(2, 2), "id": 0},"front_right": {"atlas": Vector2i(4, 2), "id": 0},"back_right": {"atlas": Vector2i(2, 2), "id": 1},"front_left": {"atlas": Vector2i(4, 2), "id": 1},},
	"shallow sea": {"top": {"atlas": Vector2i(1, 2), "id": 0},"back_left": {"atlas": Vector2i(2, 4), "id": 0},"front_right": {"atlas": Vector2i(4, 4), "id": 0},"back_right": {"atlas": Vector2i(2, 4), "id": 1},"front_left": {"atlas": Vector2i(4, 4), "id": 1},},
	"beach": {"top": {"atlas": Vector2i(1, 3), "id": 0},"back_left": {"atlas": Vector2i(2, 6), "id": 0},"front_right": {"atlas": Vector2i(4, 6), "id": 0},"back_right": {"atlas": Vector2i(2, 6), "id": 1},"front_left": {"atlas": Vector2i(4, 6), "id": 1},},
	"sandy beach": {"top": {"atlas": Vector2i(1, 4), "id": 0},"back_left": {"atlas": Vector2i(2, 8), "id": 0},"front_right": {"atlas": Vector2i(4, 8), "id": 0},"back_right": {"atlas": Vector2i(2, 8), "id": 1},"front_left": {"atlas": Vector2i(4, 8), "id": 1},},
	"coral reef": {"top": {"atlas": Vector2i(1, 5), "id": 0},"back_left": {"atlas": Vector2i(2, 10), "id": 0},"front_right": {"atlas": Vector2i(4, 10), "id": 0},"back_right": {"atlas": Vector2i(2, 10), "id": 1},"front_left": {"atlas": Vector2i(4, 10), "id": 1},},
	"grass": {"top": {"atlas": Vector2i(1, 6), "id": 0},"back_left": {"atlas": Vector2i(2, 12), "id": 0},"front_right": {"atlas": Vector2i(4, 12), "id": 0},"back_right": {"atlas": Vector2i(2, 12), "id": 1},"front_left": {"atlas": Vector2i(4, 12), "id": 1},},
	"meadow": {"top": {"atlas": Vector2i(1, 7), "id": 0},"back_left": {"atlas": Vector2i(2, 14), "id": 0},"front_right": {"atlas": Vector2i(4, 14), "id": 0},"back_right": {"atlas": Vector2i(2, 14), "id": 1},"front_left": {"atlas": Vector2i(4, 14), "id": 1},},
	"plains": {"top": {"atlas": Vector2i(1, 8), "id": 0},"back_left": {"atlas": Vector2i(2, 16), "id": 0},"front_right": {"atlas": Vector2i(4, 16), "id": 0},"back_right": {"atlas": Vector2i(2, 16), "id": 1},"front_left": {"atlas": Vector2i(4, 16), "id": 1},},
	"steppe": {"top": {"atlas": Vector2i(1, 9), "id": 0},"back_left": {"atlas": Vector2i(2, 18), "id": 0},"front_right": {"atlas": Vector2i(4, 18), "id": 0},"back_right": {"atlas": Vector2i(2, 18), "id": 1},"front_left": {"atlas": Vector2i(4, 18), "id": 1},},
	"savanna":{"top": {"atlas": Vector2i(1, 10), "id": 0},"back_left": {"atlas": Vector2i(2, 20), "id": 0},"front_right": {"atlas": Vector2i(4, 20), "id": 0},"back_right": {"atlas": Vector2i(2, 20), "id": 1},"front_left": {"atlas": Vector2i(2, 20), "id": 1},},
	"forest": {"top": {"atlas": Vector2i(1, 11), "id": 0},"back_left": {"atlas": Vector2i(2, 22), "id": 0},"front_right": {"atlas": Vector2i(4, 22), "id": 0},"back_right": {"atlas": Vector2i(2, 22), "id": 1},"front_left": {"atlas": Vector2i(4, 22), "id": 1},},
	"dense forest": {"top": {"atlas": Vector2i(1, 12), "id": 0},"back_left": {"atlas": Vector2i(2, 24), "id": 0},"front_right": {"atlas": Vector2i(4, 24), "id": 0},"back_right": {"atlas": Vector2i(2, 24), "id": 1},"front_left": {"atlas": Vector2i(4, 24), "id": 1},},
	"pine forest": {"top": {"atlas": Vector2i(1, 13), "id": 0},"back_left": {"atlas": Vector2i(2, 26), "id": 0},"front_right": {"atlas": Vector2i(4, 26), "id": 0},"back_right": {"atlas": Vector2i(2, 26), "id": 1},"front_left": {"atlas": Vector2i(4, 26), "id": 1},},
	"jungle": {"top": {"atlas": Vector2i(1, 14), "id": 0},"back_left": {"atlas": Vector2i(2, 28), "id": 0},"front_right": {"atlas": Vector2i(4, 28), "id": 0},"back_right": {"atlas": Vector2i(2, 28), "id": 1},"front_left": {"atlas": Vector2i(4, 28), "id": 1},},
	"mountain": {"top": {"atlas": Vector2i(1, 15), "id": 0},"back_left": {"atlas": Vector2i(2, 30), "id": 0},"front_right": {"atlas": Vector2i(4, 30), "id": 0},"back_right": {"atlas": Vector2i(2, 30), "id": 1},"front_left": {"atlas": Vector2i(4, 30), "id": 1},},
	"ridge": {"top": {"atlas": Vector2i(1, 16), "id": 0},"back_left": {"atlas": Vector2i(2, 32), "id": 0},"front_right": {"atlas": Vector2i(4, 32), "id": 0},"back_right": {"atlas": Vector2i(2, 32), "id": 1},"front_left": {"atlas": Vector2i(4, 32), "id": 1},},
	"peak": {"top": {"atlas": Vector2i(1, 17), "id": 0},"back_left": {"atlas": Vector2i(2, 34), "id": 0},"front_right": {"atlas": Vector2i(4, 34), "id": 0},"back_right": {"atlas": Vector2i(2, 34), "id": 1},"front_left": {"atlas": Vector2i(4, 34), "id": 1},},
	"volcano": {"top": {"atlas": Vector2i(1, 18), "id": 0},"back_left": {"atlas": Vector2i(2, 36), "id": 0},"front_right": {"atlas": Vector2i(4, 36), "id": 0},"back_right": {"atlas": Vector2i(2, 36), "id": 1},"front_left": {"atlas": Vector2i(4, 36), "id": 1},},
	"precipice": {"top": {"atlas": Vector2i(1, 19), "id": 0},"back_left": {"atlas": Vector2i(3, 0), "id": 0},"front_right": {"atlas": Vector2i(5, 0), "id": 0},"back_right": {"atlas": Vector2i(3, 0), "id": 1},"front_left": {"atlas": Vector2i(5, 0), "id": 1},},
	"zenith": {"top": {"atlas": Vector2i(1, 20), "id": 0},"back_left": {"atlas": Vector2i(3, 2), "id": 0},"front_right": {"atlas": Vector2i(5, 2), "id": 0},"back_right": {"atlas": Vector2i(3, 2), "id": 1},"front_left": {"atlas": Vector2i(5, 2), "id": 1},},
	"plateau": {"top": {"atlas": Vector2i(1, 21), "id": 0},"back_left": {"atlas": Vector2i(3, 4), "id": 0},"front_right": {"atlas": Vector2i(5, 4), "id": 0},"back_right": {"atlas": Vector2i(3, 4), "id": 1},"front_left": {"atlas": Vector2i(5, 4), "id": 1},},
	"snow": {"top": {"atlas": Vector2i(1, 22), "id": 0},"back_left": {"atlas": Vector2i(3, 6), "id": 0},"front_right": {"atlas": Vector2i(5, 6), "id": 0},"back_right": {"atlas": Vector2i(3, 6), "id": 1},"front_left": {"atlas": Vector2i(5, 6), "id": 1},},
	"ice field": {"top": {"atlas": Vector2i(1, 23), "id": 0},"back_left": {"atlas": Vector2i(3, 8), "id": 0},"front_right": {"atlas": Vector2i(5, 8), "id": 0},"back_right": {"atlas": Vector2i(3, 8), "id": 1},"front_left": {"atlas": Vector2i(5, 8), "id": 1},},
	"glacier": {"top": {"atlas": Vector2i(1, 24), "id": 0},"back_left": {"atlas": Vector2i(3, 10), "id": 0},"front_right": {"atlas": Vector2i(5, 10), "id": 0},"back_right": {"atlas": Vector2i(3, 10), "id": 1},"front_left": {"atlas": Vector2i(3, 10), "id": 1},},
	"ravine": {"top": {"atlas": Vector2i(1, 25), "id": 0},"back_left": {"atlas": Vector2i(3, 12), "id": 0},"front_right": {"atlas": Vector2i(5, 12), "id": 0},"back_right": {"atlas": Vector2i(3, 12), "id": 1},"front_left": {"atlas": Vector2i(5, 12), "id": 1},},
	"canyon": {"top": {"atlas": Vector2i(1, 26), "id": 0},"back_left": {"atlas": Vector2i(3, 14), "id": 0},"front_right": {"atlas": Vector2i(5, 14), "id": 0},"back_right": {"atlas": Vector2i(3, 14), "id": 1},"front_left": {"atlas": Vector2i(5, 14), "id": 1},},
	"valley": {"top": {"atlas": Vector2i(1, 27), "id": 0},"back_left": {"atlas": Vector2i(3, 16), "id": 0},"front_right": {"atlas": Vector2i(5, 16), "id": 0},"back_right": {"atlas": Vector2i(3, 16), "id": 1},"front_left": {"atlas": Vector2i(5, 16), "id": 1},},
	"desert": {"top": {"atlas": Vector2i(1, 28), "id": 0},"back_left": {"atlas": Vector2i(3, 18), "id": 0},"front_right": {"atlas": Vector2i(5, 18), "id": 0},"back_right": {"atlas": Vector2i(3, 18), "id": 1},"front_left": {"atlas": Vector2i(5, 18), "id": 1},},
	"dunes": {"top": {"atlas": Vector2i(1, 29), "id": 0},"back_left": {"atlas": Vector2i(3, 20), "id": 0},"front_right": {"atlas": Vector2i(5, 20), "id": 0},"back_right": {"atlas": Vector2i(3, 20), "id": 1},"front_left": {"atlas": Vector2i(5, 20), "id": 1},},
	"badlands": {"top": {"atlas": Vector2i(1, 30), "id": 0},"back_left": {"atlas": Vector2i(3, 22), "id": 0},"front_right": {"atlas": Vector2i(5, 22), "id": 0},"back_right": {"atlas": Vector2i(3, 22), "id": 1},"front_left": {"atlas": Vector2i(5, 22), "id": 1},},
	"tundra": {"top": {"atlas": Vector2i(1, 31), "id": 0},"back_left": {"atlas": Vector2i(3, 24), "id": 0},"front_right": {"atlas": Vector2i(5, 24), "id": 0},"back_right": {"atlas": Vector2i(3, 24), "id": 1},"front_left": {"atlas": Vector2i(5, 24), "id": 1},},
	"frozen plains": {"top": {"atlas": Vector2i(1, 32), "id": 0},"back_left": {"atlas": Vector2i(3, 26), "id": 0},"front_right": {"atlas": Vector2i(5, 26), "id": 0},"back_right": {"atlas": Vector2i(3, 26), "id": 1},"front_left": {"atlas": Vector2i(5, 26), "id": 1},},
	"permafrost": {"top": {"atlas": Vector2i(1, 33), "id": 0},"back_left": {"atlas": Vector2i(3, 28), "id": 0},"front_right": {"atlas": Vector2i(5, 28), "id": 0},"back_right": {"atlas": Vector2i(3, 28), "id": 1},"front_left": {"atlas": Vector2i(5, 28), "id": 1},},
	"dry lake": {"top": {"atlas": Vector2i(1, 34), "id": 0},"back_left": {"atlas": Vector2i(3, 30), "id": 0},"front_right": {"atlas": Vector2i(5, 30), "id": 0},"back_right": {"atlas": Vector2i(3, 30), "id": 1},"front_left": {"atlas": Vector2i(5, 30), "id": 1},},
	"salt flat": {"top": {"atlas": Vector2i(1, 35), "id": 0},"back_left": {"atlas": Vector2i(3, 32), "id": 0},"front_right": {"atlas": Vector2i(5, 32), "id": 0},"back_right": {"atlas": Vector2i(3, 32), "id": 1},"front_left": {"atlas": Vector2i(5, 32), "id": 1},},
	"basin": {"top": {"atlas": Vector2i(1, 36), "id": 0},"back_left": {"atlas": Vector2i(3, 34), "id": 0},"front_right": {"atlas": Vector2i(5, 34), "id": 0},"back_right": {"atlas": Vector2i(3, 34), "id": 1},"front_left": {"atlas": Vector2i(5, 34), "id": 1},},
	"river": {"top": {"atlas": Vector2i(1, 37), "id": 0},"back_left": {"atlas": Vector2i(3, 36), "id": 0},"front_right": {"atlas": Vector2i(5, 36), "id": 0},"back_right": {"atlas": Vector2i(3, 36), "id": 1},"front_left": {"atlas": Vector2i(5, 36), "id": 1},},
}

func _init(p_cx: int, p_cy: int, p_world: InfiniteNoiseWorld):
	cx = p_cx
	cy = p_cy
	world = p_world
	
func clear_chunk_tiles():
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			# Calculate the raw tile coordinate 
			var current_cell = Vector2i(x, y)
			
			# 1. Clear the walls from the wall layer
			if is_instance_valid(wall_layer): 
				wall_layer.erase_cell(current_cell)
				
			# 2. Clear any walls drawn on neighbors outside this immediate 16x16 chunk
			var neighbors = [
				front_left_offset,
				front_right_offset
			]
			for offset in neighbors:
				var neighbor_cell = current_cell + offset
				if is_instance_valid(wall_layer):
					wall_layer.erase_cell(neighbor_cell)

func update_perspective_offsets(angle_index: int):
	match angle_index:
		0: 
			front_left_offset = Vector2i(1, 0)
			front_right_offset = Vector2i(0, 1)
			left_wall_key = "back_left"
			right_wall_key = "front_right"
		1: 
			front_left_offset = Vector2i(1, -1)
			front_right_offset = Vector2i(1, 1)
			left_wall_key = "back_left"
			right_wall_key = "front_right"
		2: 
			front_left_offset = Vector2i(0, -1)
			front_right_offset = Vector2i(1, 0)
			left_wall_key = "front_left"
			right_wall_key = "back_right"
		3: 
			front_left_offset = Vector2i(-1, -1)
			front_right_offset = Vector2i(1, -1)
			left_wall_key = "front_left"
			right_wall_key = "back_right"
		4: 
			front_left_offset = Vector2i(-1, 0)
			front_right_offset = Vector2i(0, -1)
			left_wall_key = "back_right"
			right_wall_key = "front_right"
		5: 
			front_left_offset = Vector2i(-1, 1)
			front_right_offset = Vector2i(-1, -1)
			left_wall_key = "back_right"
			right_wall_key = "front_left"
		6: 
			front_left_offset = Vector2i(0, 1)
			front_right_offset = Vector2i(-1, 0)
			left_wall_key = "back_right"
			right_wall_key = "front_left"
		7: 
			front_left_offset = Vector2i(1, 1)
			front_right_offset = Vector2i(-1, 1)
			left_wall_key = "back_left"
			right_wall_key = "front_right"

var height_grid_cache: Dictionary = {}
var layers_initialized: bool = false

func initialize_layers(p_tile_set: TileSet):
	if layers_initialized: return
	
	main_layer = TileMapLayer.new()
	main_layer.tile_set = p_tile_set
	main_layer.y_sort_enabled = true
	main_layer.z_index = 0
	add_child(main_layer)
	
	wall_layer = TileMapLayer.new()
	wall_layer.tile_set = p_tile_set
	wall_layer.y_sort_enabled = true
	wall_layer.z_index = 0
	add_child(wall_layer)
	
	layers_initialized = true

# Called ONLY when discovering a new chunk or completely rebuilding data
# Called ONLY when discovering a new chunk or completely rebuilding data
func generate(p_tile_set: TileSet):
	initialize_layers(p_tile_set)
	
	# Clear previous contents safely
	main_layer.clear()
	clear_only_walls()
	
	update_perspective_offsets(current_angle_index)
	
	# 1. Populating data grid cache USING A PURE UNROTATED GRID AXIS
	height_grid_cache.clear()
	for y in range(-1, CHUNK_SIZE_y + 1):
		for x in range(-1, CHUNK_SIZE_x + 1):
			# KEEP THIS PURE, FLAT, AND UNROTATED!
			# The noise engine must always read identical world coordinates
			var wx = float(cx * CHUNK_SIZE_x + x)
			var wy = float(cy * CHUNK_SIZE_y + y)
			
			var biome_data: Dictionary
			if manager and manager.has_method("get_cached_biome_data"):
				biome_data = manager.get_cached_biome_data(int(round(wx)), int(round(wy)))
			else:
				biome_data = world.get_biome(wx + 0.5, wy + 0.5)
				
			if biome_data and biome_data.has("name"):
				height_grid_cache[Vector2i(x, y)] = {
					"height": int(biome_data.get("render_height", 0)),
					"p_level": int(biome_data.get("p_level", 0)), # Track fluid levels/depth variables
					"name": biome_data.get("name").to_lower()
				}
				
	# 2. Render ONLY the ground once
	var source_id: int = 6
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			var current_cell = Vector2i(x, y)
			if not height_grid_cache.has(current_cell): continue
			var registry_entry = tile_registry[height_grid_cache[current_cell]["name"]]
			main_layer.set_cell(current_cell, source_id, registry_entry["top"]["atlas"], 0)
			
	# 3. Draw initial walls
	rebuild_walls_only(source_id)

# Call this from main.gd's _refresh_world hook!
func change_view_angle(new_angle_index: int, source_id: int = 6):
	current_angle_index = new_angle_index
	update_perspective_offsets(current_angle_index)
	clear_only_walls()
	rebuild_walls_only(source_id)

func rebuild_walls_only(source_id: int):
	var active_neighbors = [
		{"offset": front_left_offset, "key": left_wall_key},
		{"offset": front_right_offset, "key": right_wall_key}
	]
	
	for y in range(CHUNK_SIZE_y):
		for x in range(CHUNK_SIZE_x):
			var current_cell = Vector2i(x, y)
			if not height_grid_cache.has(current_cell): continue
			
			var tile_data = height_grid_cache[current_cell]
			var tile_name = tile_data["name"]
			if not tile_registry.has(tile_name): continue
			
			var registry_entry = tile_registry[tile_name]
			
			# Effective height calculation rules
			var current_effective_h = tile_data["height"]
			if tile_name.contains("lake") or tile_name.contains("ocean"):
				current_effective_h += tile_data["p_level"]
				
			for n in active_neighbors:
				var neighbor_cell = current_cell + n["offset"]
				var neighbor_data = height_grid_cache.get(neighbor_cell, {"height": 0, "p_level": 0, "name": ""})
				
				var neighbor_effective_h = neighbor_data["height"]
				if neighbor_data["name"].contains("lake") or neighbor_data["name"].contains("ocean"):
					neighbor_effective_h += neighbor_data["p_level"]
					
				# If height dropped, project the wall downwards onto neighbor cell coordinates
				if current_effective_h > neighbor_effective_h:
					var wall_data = registry_entry.get(n["key"])
					if wall_data and is_instance_valid(wall_layer):
						wall_layer.set_cell(neighbor_cell, source_id, wall_data["atlas"], wall_data["id"])

func clear_only_walls():
	if is_instance_valid(wall_layer):
		wall_layer.clear()
