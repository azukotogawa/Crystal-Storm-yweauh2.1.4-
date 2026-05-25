# world_viewer.gd
extends Node2D

@export var seed_value: int = 12349

var world: InfiniteNoiseWorld
var tilemap: TileMapLayer
var camera: Camera2D

var current_zoom: float = 1.0

# Tracks cells we've already rendered to prevent recalculating math on every frame
var rendered_cells: Dictionary = {}

func _ready():
	world = InfiniteNoiseWorld.new(seed_value)
	
	tilemap = TileMapLayer.new()
	var loaded_tileset = load("res://assets/tiles/new_tile_set.tres")
	if loaded_tileset:
		tilemap.tile_set = loaded_tileset
	else:
		push_error("CRITICAL: Missing tileset at res://assets/tiles/main_tiles.tres")
	add_child(tilemap)
	
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	
	# Start camera at an arbitrary world coordinate base
	camera.position = Vector2(0, 0)
	camera.zoom = Vector2(current_zoom, current_zoom)
	
	await get_tree().process_framea
	update_viewport_tiles()

func _process(_delta):
	# Handle continuous drag camera movement (Hold Middle Mouse Button to Pan)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		var mouse_velocity = Input.get_last_mouse_velocity()
		if mouse_velocity.length() > 0:
			camera.position -= mouse_velocity * _delta / current_zoom
			update_viewport_tiles()

func update_viewport_tiles():
	if not tilemap or not tilemap.tile_set:
		return
		
	# 1. Calculate the exact screen viewport box boundaries in global pixels
	var viewport_size = get_viewport_rect().size
	var half_view = (viewport_size / current_zoom) / 2.0
	
	var top_left_px = camera.position - half_view
	var bottom_right_px = camera.position + half_view
	
	# 2. Convert pixel boundaries to TileMap coordinates (assuming 16x16 tiles)
	# Add a 2-tile padding buffer around the edges to hide pops
	var start_x = int(floor(top_left_px.x / 16.0)) - 2
	var start_y = int(floor(top_left_px.y / 16.0)) - 2
	var end_x = int(ceil(bottom_right_px.x / 16.0)) + 2
	var end_y = int(ceil(bottom_right_px.y / 16.0)) + 2
	
	# Safety Guard: Cap max tiles generated in a single viewport frame to prevent lockups
	var total_tiles = (end_x - start_x) * (end_y - start_y)
	if total_tiles > 500000: 
		# If zoomed out incredibly far, freeze generation and wait for user to zoom back in
		return

	# 3. Only loop over and render tiles that are inside the camera window
	var local_world = world
	var local_tilemap = tilemap
	
	for y in range(start_y, end_y):
		for x in range(start_x, end_x):
			var cell_coord = Vector2i(x, y)
			
			# If this cell was drawn previously, skip running the noise math again!
			if rendered_cells.has(cell_coord):
				continue
				
			var wx = x + 0.5
			var wy = y + 0.5
			
			var biome_data = local_world.get_biome(wx, wy)
			if not biome_data or not biome_data.has("name"):
				continue
				
			var tile_name = biome_data["name"]
			var h_level = biome_data.get("h_level", 0)
			var render_height = biome_data.get("render_height", 0)
			
			var base_atlas_x = get_tile_x_from_name(tile_name)
			
			
			# Paint the tile on our infinite coordinate spectrum
			local_tilemap.set_cell(cell_coord, 0, Vector2i(base_atlas_x, 0))
			rendered_cells[cell_coord] = true

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		# Zooming In: Decreases frame box size, rendering fewer tiles, making it highly responsive
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = current_zoom * 1.15
			camera.zoom = Vector2(current_zoom, current_zoom)
			update_viewport_tiles()
		# Zooming Out: Increases frame box size, automatically loading more tiles to fill screen space
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = current_zoom * 0.85
			camera.zoom = Vector2(current_zoom, current_zoom)
			update_viewport_tiles()
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			seed_value += 1
			world = InfiniteNoiseWorld.new(seed_value)
			rendered_cells.clear()
			tilemap.clear()
			update_viewport_tiles()
			print("Regenerating dynamic map viewer to seed:", seed_value)

func get_tile_x_from_name(tile_name: String) -> int:
	match tile_name.to_lower():
		"deep_ocean", "deep ocean": return 0
		"ocean": return 1
		"shallow_sea", "shallow sea": return 2
		"beach": return 3
		"sandy_beach", "sandy beach": return 4
		"coral_reef", "coral reef": return 5
		"grass": return 6
		"meadow": return 7
		"plains": return 8
		"steppe": return 9
		"savanna": return 10
		"forest": return 11
		"dense_forest", "dense forest": return 12
		"pine_forest", "pine forest": return 13
		"jungle": return 14
		"mountain": return 15
		"ridge": return 16
		"peak": return 17
		"volcano": return 18
		"precipice": return 19
		"zenith": return 20
		"plateau": return 21
		"snow": return 22
		"ice_field", "ice field": return 23
		"glacier": return 24
		"valley": return 25
		"ravine": return 26
		"canyon": return 27
		"desert": return 28
		"dunes": return 29
		"badlands": return 30
		"tundra": return 31
		"frozen_plains", "frozen plains": return 32
		"permafrost": return 33
		"dry_lake", "dry lake": return 34
		"salt_flat", "salt flat": return 35
		"basin": return 36
		"river": return 37
		_: return 6
