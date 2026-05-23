extends Node2D

var current_seed: int = 12349
var world: InfiniteNoiseWorld

@onready var chunk_manager = $ChunkManager
@onready var player = $Player
@onready var camera = $Camera2D

# SOURCE OF TRUTH: Flat, un-elevated world tile coordinates.
var raw_world_tile_pos: Vector2 = Vector2.ZERO
var view_angle: int = 0 # Tracks 0 through 7 (8 total perspective angles)

@export var movement_speed: float = 24.0 
@export var auto_jump_enabled: bool = true

# Dynamic Kinematics Configuration - Amplified for high-impact physics
@export var base_gravity: float = 1400.0       # Much heavier upward resistance
@export var fall_gravity: float = 3600.0       # Heavy downward snap for fast falling
@export var jump_force: float = -380.0        # Punchy, distinct upward explosion
@export var jump_cut_velocity: float = -100.0  
@export var terminal_velocity: float = 800.0

var current_ground_h: float = 0.0

func _ready():
	world = InfiniteNoiseWorld.new(current_seed)
	chunk_manager.world = world
	chunk_manager.tile_set = $WorldContainer/WorldTileMap.tile_set
	chunk_manager.camera = camera 
	
	if FileAccess.file_exists("user://save.json"):
		load_game()
	else:
		raw_world_tile_pos = Vector2.ZERO
		
	chunk_manager._load_chunk(0, 0)
	camera.make_current()
	
	var p_grid_x = int(floor(raw_world_tile_pos.x))
	var p_grid_y = int(floor(raw_world_tile_pos.y))
	current_ground_h = world.get_biome(p_grid_x + 0.5, p_grid_y + 0.5).get("render_height", 0)
	
	_update_player_screen_position()

func _unhandled_input(event):
	if event is InputEventKey:
		if event.keycode == KEY_SPACE and event.pressed:
			if player and not player.is_jumping:
				_trigger_manual_jump()
				
		if event.keycode == KEY_SPACE and not event.pressed:
			if player and player.is_jumping and player.z_velocity < jump_cut_velocity:
				player.z_velocity = jump_cut_velocity

		if event.pressed:
			if event.keycode == KEY_E:
				view_angle = (view_angle + 1) % 8
				_refresh_world()
			if event.keycode == KEY_Q:
				view_angle = (view_angle - 1 + 8) % 8
				_refresh_world()
			if event.keycode == KEY_3:
				camera.rotation -= deg_to_rad(5)
			if event.keycode == KEY_1:
				camera.rotation += deg_to_rad(5)

func _refresh_world():
	if camera:
		camera.rotation = view_angle * -(PI / 4.0)
	
	chunk_manager.current_angle_index = view_angle
	
	# Clear out old visual chunk pipelines and wipe the async queues
	chunk_manager.loading_queue.clear()
	
	var active_chunks = []
	if "chunks" in chunk_manager:
		active_chunks = chunk_manager.chunks.values()
	else:
		active_chunks = chunk_manager.get_children()

	for chunk in active_chunks:
		if is_instance_valid(chunk) and chunk.has_method("change_view_angle"):
			chunk.change_view_angle(view_angle, 6)
			
	_update_player_screen_position()

func _process(delta):
	_handle_player_movement(delta)
	_update_jump_and_fall_physics(delta)
	_update_player_screen_position()

func _handle_player_movement(delta: float):
	if not player or not world: return
	
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		
		var camera_rotation = view_angle * -(PI / 4.0)
		var rotated_input = input_dir.rotated(camera_rotation)
		
		var isometric_movement = Vector2(
			(rotated_input.x / 32.0) + (rotated_input.y / 16.0),
			(-rotated_input.x / 32.0) + (rotated_input.y / 16.0)
		).normalized()
		
		var target_tile_pos = raw_world_tile_pos + isometric_movement * movement_speed * delta
		
		if _can_move_to(target_tile_pos):
			raw_world_tile_pos = target_tile_pos
			
			var p_grid_x = int(floor(raw_world_tile_pos.x))
			var p_grid_y = int(floor(raw_world_tile_pos.y))
			var target_h = world.get_biome(p_grid_x + 0.5, p_grid_y + 0.5).get("render_height", 0)
			
			if target_h < current_ground_h:
				# FORCE EVERY STEP DOWN TO FREEFALL:
				# Leave current_ground_h anchored high so physics handles the downward drop.
				if not player.is_jumping:
					player.is_jumping = true
					player.z_velocity = 120.0 # Clear over the ledge forcefully
			else:
				# Only step up or walk flat if we aren't in the middle of a fall arc
				if not player.is_jumping:
					current_ground_h = target_h

func _can_move_to(target_pos: Vector2) -> bool:
	# 1. Map target tile pos directly to target chunk index structures using flat tile scales
	if chunk_manager:
		# Access your constant tile boundaries directly from your current manager definition
		var c_size_x = chunk_manager.CHUNK_SIZE_x
		var c_size_y = chunk_manager.CHUNK_SIZE_y
		
		var target_cx = int(floor(target_pos.x / c_size_x))
		var target_cy = int(floor(target_pos.y / c_size_y))
		
		# FIX: Use 'in' operator to check if property exists on the ChunkManager instance
		if "MAX_CHUNK_RADIUS" in chunk_manager:
			if abs(target_cx) > chunk_manager.MAX_CHUNK_RADIUS or abs(target_cy) > chunk_manager.MAX_CHUNK_RADIUS:
				return false
		elif abs(target_cx) > 15 or abs(target_cy) > 15: # Fallback boundary guard limit
			return false
			
	# 2. Terrain height differential parsing (Stays unchanged) [cite: 8]
	var check_current_h = world.get_biome(int(floor(raw_world_tile_pos.x)) + 0.5, int(floor(raw_world_tile_pos.y)) + 0.5).get("render_height", 0)
	var target_h = world.get_biome(int(floor(target_pos.x)) + 0.5, int(floor(target_pos.y)) + 0.5).get("render_height", 0)
	
	var height_difference = target_h - check_current_h
	if height_difference <= 0: return true
		
	if height_difference <= 1:
		if auto_jump_enabled: return true
		else:
			var visual_step_height_px = height_difference * 8.0
			return player.is_jumping and ((-player.z_height) > visual_step_height_px)
			
	return false

func _trigger_manual_jump():
	player.is_jumping = true
	var current_tile_h = world.get_biome(int(floor(raw_world_tile_pos.x)) + 0.5, int(floor(raw_world_tile_pos.y)) + 0.5).get("render_height", 0)
	player.z_height = (current_tile_h - current_ground_h) * -8.0
	player.z_velocity = jump_force

func _update_jump_and_fall_physics(delta: float):
	var current_tile_h = world.get_biome(int(floor(raw_world_tile_pos.x)) + 0.5, int(floor(raw_world_tile_pos.y)) + 0.5).get("render_height", 0)
	var target_z_px = (current_tile_h - current_ground_h) * -8.0
	
	if player.is_jumping:
		var active_gravity = base_gravity
		if player.z_velocity > 0.0:
			active_gravity = fall_gravity
			
		player.z_velocity = min(player.z_velocity + active_gravity * delta, terminal_velocity)
		player.z_height += player.z_velocity * delta
		
		# LANDING CONDITIONAL check:
		# Only land when moving downwards and intersecting or passing beneath the local ground line
		if player.z_velocity >= 0.0 and player.z_height >= target_z_px:
			player.z_height = target_z_px
			player.is_jumping = false
			player.z_velocity = 0.0
			current_ground_h = current_tile_h
	else:
		# If walking normally, keep height pinned perfectly to the ground profile
		player.z_height = target_z_px
		current_ground_h = current_tile_h

func _update_player_screen_position():
	if not player or not world: return
	
	# 1. Project directly into standard unrotated isometric coordinates
	var screen_x = (raw_world_tile_pos.x - raw_world_tile_pos.y) * 32.0
	var screen_y = (raw_world_tile_pos.x + raw_world_tile_pos.y) * 16.0
	
	var p_grid_x = int(floor(raw_world_tile_pos.x))
	var p_grid_y = int(floor(raw_world_tile_pos.y))
	
	var current_biome = world.get_biome(raw_world_tile_pos.x + 0.5, raw_world_tile_pos.y + 0.5)
	current_ground_h = current_biome.get("render_height", 0)
	var height_displacement_y = current_ground_h * -8.0
	
	# 2. View Occlusion Scanning Vectors
	var front_offsets: Array[Vector2i] = []
	match view_angle:
		0: front_offsets = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
		1: front_offsets = [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
		2: front_offsets = [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
		3: front_offsets = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]
		4: front_offsets = [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
		5: front_offsets = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]
		6: front_offsets = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
		7: front_offsets = [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]

	var is_occluded: bool = false
	var highest_block_screen_y: float = -999999.0
	
	var player_base_pos = Vector2(screen_x, screen_y + height_displacement_y)
	
	# Rotate the visual gravity tracking offset to align with camera rotation
	var cam_rotation = view_angle * (PI / 4.0)
	var gravity_visual_offset = Vector2(0, player.z_height).rotated(cam_rotation)
	
	var player_final_pos = player_base_pos + gravity_visual_offset

	# Scan for blocking foreground walls
	for offset in front_offsets:
		var check_wx = p_grid_x + offset.x
		var check_wy = p_grid_y + offset.y
		var front_biome = world.get_biome(check_wx + 0.5, check_wy + 0.5)
		var front_h = front_biome.get("render_height", 0)
		
		if front_h > current_ground_h:
			var front_screen_x = (check_wx - check_wy) * 32.0
			var front_screen_y = (check_wx + check_wy) * 16.0
			var front_peak_y = front_screen_y + (front_h * -8.0)
			
			is_occluded = true
			if front_peak_y > highest_block_screen_y:
				highest_block_screen_y = front_peak_y
					
	# 4. Handle Player Sprite Node Counter-Rotation & Shader Calculations
	var player_sprite = player if not player.has_node("Sprite2D") else player.get_node("Sprite2D")
	if player_sprite:
		# Counter-rotate the sprite so it stays perfectly vertical on your monitor screen
		player_sprite.rotation = -cam_rotation
		
		if player_sprite.material is ShaderMaterial:
			player_sprite.material.set_shader_parameter("is_clipped", is_occluded)
			
			if is_occluded and player_sprite.texture:
				var tex_height = player_sprite.texture.get_height()
				
				# Find how far down from the top of the sprite the clipping plane sits along global screen-space Y
				var local_clip_y = highest_block_screen_y - (player_final_pos.y - (tex_height / 2.0))
				
				# Pass absolute screen pixels down to match the SCREEN_UV shader framework
				var screen_pixel_cutoff = (player_sprite.global_position.y - (tex_height / 2.0)) + local_clip_y
				player_sprite.material.set_shader_parameter("clip_threshold_y", screen_pixel_cutoff)

	# 5. Position and Sorting Updates
	player.position = player_final_pos
	player.z_index = int(screen_y) + (int(current_ground_h) * 8) + 4
	
	if player.has_node("ShadowSprite"):
		player.get_node("ShadowSprite").position = -gravity_visual_offset
		player.get_node("ShadowSprite").rotation = -cam_rotation
	
	if camera:
		camera.position = player.position
		
	chunk_manager.update(raw_world_tile_pos)
	
# --- SAVE, LOAD & SEED CONFIGURATION ---
func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.zoom *= 1.1
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.zoom *= 0.9
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F2: show_seed_input()
			KEY_F4: change_seed(randi_range(10000, 999999))
	
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST: save_game()

func save_game():
	var save_data = {"seed": current_seed, "tile_pos_x": raw_world_tile_pos.x, "tile_pos_y": raw_world_tile_pos.y}
	var file = FileAccess.open("user://save.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		print("Game autosaved!")

func load_game():
	if FileAccess.file_exists("user://save.json"):
		var file = FileAccess.open("user://save.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		if data:
			current_seed = data.get("seed", 12349)
			world = InfiniteNoiseWorld.new(current_seed)
			chunk_manager.world = world
			if data.has("tile_pos_x"):
				raw_world_tile_pos = Vector2(data.tile_pos_x, data.tile_pos_y)
			print("Save loaded!")

func show_seed_input():
	var dialog = AcceptDialog.new()
	dialog.title = "Change World Seed"
	dialog.dialog_text = "Enter new seed number:"
	var line_edit = LineEdit.new()
	line_edit.text = str(current_seed)
	dialog.add_child(line_edit)
	line_edit.position = Vector2(30, 60)
	dialog.confirmed.connect(func():
		var new_seed = line_edit.text.to_int()
		if new_seed > 0: change_seed(new_seed)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2(400, 180))

func change_seed(new_seed: int):
	current_seed = new_seed
	world = InfiniteNoiseWorld.new(new_seed)
	chunk_manager.world = world
	chunk_manager.clear_all_active_chunks()
	raw_world_tile_pos = Vector2.ZERO
	chunk_manager._load_chunk(0, 0)
	_update_player_screen_position()
	save_game()
	print("World changed to seed:", new_seed)
