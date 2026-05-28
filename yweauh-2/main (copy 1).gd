extends Node2D

var current_seed: int = 12349
var world: InfiniteNoiseWorld

@onready var chunk_manager = $ChunkManager
@onready var player = $Player
@onready var camera = $Camera2D

var raw_world_tile_pos: Vector2 = Vector2.ZERO
var view_angle: int = 0 

@export var movement_speed: float = 2.0 
@export var auto_jump_enabled: bool = false

@export var base_gravity: float = 1400.0       
@export var fall_gravity: float = 2400.0       
@export var jump_force: float = -380.0        
@export var jump_cut_velocity: float = -100.0  
@export var terminal_velocity: float = 800.0   

var current_ground_h: float = 0.0
var sprite_scale_modifier: Vector2 = Vector2.ONE
var current_skew: float = 0.0
var current_tile_h: float = 0.0 # Add this line

func _ready():
	world = InfiniteNoiseWorld.new(current_seed)
	chunk_manager.world = world
	chunk_manager.tile_set = $WorldContainer/SubViewport/MainLayer.tile_set
	chunk_manager.camera = camera 
	
	if FileAccess.file_exists("user://save.json"):
		load_game()
	else:
		raw_world_tile_pos = Vector2.ZERO
		
	chunk_manager._load_chunk(0, 0)
	camera.make_current()
	
	var initial_sample = IsoMath.screen_to_grid(IsoMath.grid_to_screen(raw_world_tile_pos)) + Vector2(0.5, 0.5)
	current_ground_h = world.get_biome(initial_sample.x, initial_sample.y).get("render_height", 0)
	
	_update_player_screen_position()
	
	# Sync the viewport size to the screen size
	$WorldContainer/SubViewport.size = get_viewport().size
	
	# Connect to the window resize signal to keep them synced
	get_viewport().size_changed.connect(_on_window_size_changed)
	print("SubViewport size: ", $WorldContainer/SubViewport.size)
	print("SubViewport children: ", $WorldContainer/SubViewport.get_child_count())
	
func _on_window_size_changed():
	$WorldContainer/SubViewport.size = get_viewport().size

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

func _trigger_manual_jump():
	if player.is_jumping: return
	player.is_jumping = true
	player.z_velocity = jump_force
	player.z_height -= 6.0
	
	sprite_scale_modifier = Vector2(0.55, 1.7)
	current_skew = 0.2
	
func _process(delta):
	_handle_player_movement(delta)
	_update_jump_and_fall_physics(delta)
	
	# Animation recovery
	sprite_scale_modifier = sprite_scale_modifier.lerp(Vector2.ONE, 10.0 * delta)
	current_skew = move_toward(current_skew, 0.0, 10.0 * delta)
	
	_update_player_screen_position()
	
	var mask_texture = $WorldContainer/SubViewport.get_texture()
	for chunk in chunk_manager.chunks.values():
		if chunk.wall_layer.material is ShaderMaterial:
			chunk.wall_layer.material.set_shader_parameter("ground_mask", mask_texture)
	
		# Force mask refresh
	var sub = $WorldContainer/SubViewport
	if sub:
		var tex = sub.get_texture()
		for key in chunk_manager.chunks:
			var chunk = chunk_manager.chunks[key]
			if chunk.wall_layer and chunk.wall_layer.material is ShaderMaterial:
				chunk.wall_layer.material.set_shader_parameter("ground_mask", tex)
				
				

func _handle_player_movement(delta: float):
	if not player or not world: return
	
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
	
	if input_dir == Vector2.ZERO: return
	
	var cam_rot = view_angle * -(PI / 4.0)
	var isometric_movement = IsoMath.screen_to_grid(
		input_dir.normalized().rotated(cam_rot)
	).normalized()
	
	raw_world_tile_pos += isometric_movement * movement_speed * delta
	
	# CALCULATE TARGET POSITION
	var target_pos = raw_world_tile_pos + (isometric_movement * movement_speed * delta)
	
	if _can_move_to(target_pos):
		raw_world_tile_pos = target_pos
	else:
	# Optional: Slide along the wall by checking X and Y axes separately
		var move_x = Vector2(isometric_movement.x * movement_speed * delta, 0)
		if _can_move_to(raw_world_tile_pos + move_x):
			raw_world_tile_pos.x += move_x.x

		var move_y = Vector2(0, isometric_movement.y * movement_speed * delta)
		if _can_move_to(raw_world_tile_pos + move_y):
			raw_world_tile_pos.y += move_y.y

# Inside main.gd

func _can_move_to(target_pos: Vector2) -> bool:
	# 1. Get current tile height
	var current_grid_pos = get_tile_center(raw_world_tile_pos)
	var current_biome = world.get_biome(current_grid_pos.x, current_grid_pos.y)
	var current_h = current_biome.get("render_height", 0)
	
	# 2. Get target tile height
	var target_grid_pos = get_tile_center(target_pos)
	var target_biome = world.get_biome(target_grid_pos.x, target_grid_pos.y)
	var target_h = target_biome.get("render_height", 0)
	
	# 3. Collision Rule: If target is higher, it's a wall.
	# We use a threshold of 0 to block movement into higher ground (cliffs).
	if target_h > current_h:
		return false # Blocked by wall
		
	return true

func _update_jump_and_fall_physics(delta: float):
	# Use visual position for accurate tile detection
	var player_screen_pos = player.position
	var sample_grid = IsoMath.screen_to_grid(player_screen_pos) + Vector2(0.5, 0.5)
	
	var biome = world.get_biome(sample_grid.x, sample_grid.y)
	current_tile_h = biome.get("render_height", 0)
	
	var target_z_px = (current_tile_h - current_ground_h) * -8.0
	var height_diff = current_tile_h - current_ground_h
	
	if not player.is_jumping:
		if abs(height_diff) > 0.35:
			player.is_jumping = true
			player.z_velocity = 0.0
			
			if height_diff > 0:  # CLIMB
				player.z_velocity = -100.0
				sprite_scale_modifier = Vector2(0.6, 1.65)
				current_skew = 0.25
			else:  # FALL OFF EDGE - stronger drop
				player.z_velocity = 65.0   # stronger initial downward velocity
				sprite_scale_modifier = Vector2(1.45, 0.6)
				current_skew = -0.15
	
	# === PHYSICS WITH GRAVITY ===
	if player.is_jumping:
		player.z_velocity += base_gravity * delta
		player.z_height += player.z_velocity * delta
		
		# Land when falling down
		if player.z_velocity >= 0 and player.z_height >= target_z_px - 8:
			player.z_height = target_z_px
			player.is_jumping = false
			player.z_velocity = 0.0
			current_ground_h = current_tile_h
			
			# Landing squash
			sprite_scale_modifier = Vector2(1.6, 0.5)
	else:
		# Smooth follow when on ground
		player.z_height = lerp(player.z_height, target_z_px, 18.0 * delta)

func _update_player_screen_position():
	var screen_pos = IsoMath.grid_to_screen(raw_world_tile_pos)
	var biome_pos = IsoMath.screen_to_grid(screen_pos) + Vector2(0.5, 0.5)
	var visual_ground_h = world.get_biome(biome_pos.x, biome_pos.y).get("render_height", 0)
	
	var cam_rotation = view_angle * -(PI / 4.0)
	var gravity_visual_offset = Vector2(0, player.z_height).rotated(cam_rotation)
	
	var player_sprite = player if not player.has_node("Sprite2D") else player.get_node("Sprite2D")
	if player_sprite:
		player_sprite.rotation = -cam_rotation
		player_sprite.scale = sprite_scale_modifier
		player_sprite.skew = current_skew

	var player_final_pos = screen_pos + Vector2(0, visual_ground_h * -8.0) + gravity_visual_offset

		# === SIMPLE & RELIABLE OCCLUSION ===
	var is_occluded: bool = false
	var highest_block_screen_y: float = -999999.0

	var front_offsets = get_offsets_for_view_angle(view_angle)

	for offset in front_offsets:
		var check_wx = raw_world_tile_pos.x + offset.x + 0.5
		var check_wy = raw_world_tile_pos.y + offset.y + 0.5
		
		var front_biome = world.get_biome(check_wx, check_wy)
		var front_h = front_biome.get("render_height", 0)
		
		if front_h > visual_ground_h:
			var wall_screen_pos = IsoMath.grid_to_screen(Vector2(check_wx - 0.5, check_wy - 0.5))
			var wall_peak_y = wall_screen_pos.y + (front_h * -8.0)
			
			if player_final_pos.y < wall_peak_y:
				is_occluded = true
				if wall_peak_y > highest_block_screen_y:
					highest_block_screen_y = wall_peak_y

	# Apply to player
	if player_sprite and player_sprite.material is ShaderMaterial:
		var mat = player_sprite.material as ShaderMaterial
		mat.set_shader_parameter("is_clipped", is_occluded)
		if is_occluded:
			mat.set_shader_parameter("clip_threshold_y", highest_block_screen_y)

	player.position = player_final_pos
	
	# Shadow
	if player.has_node("ShadowSprite"):
		var shadow = player.get_node("ShadowSprite")
		shadow.position = -gravity_visual_offset
		shadow.rotation = -cam_rotation
		var progress = clamp(1.0 - (abs(player.z_height) / 200.0), 0.2, 1.0)
		shadow.scale = Vector2(progress, progress)

	if camera:
		camera.position = player_final_pos
	
	chunk_manager.update(raw_world_tile_pos)

func get_offsets_for_view_angle(angle: int) -> Array[Vector2i]:
	match angle:
		0: return [Vector2i(0, 1), Vector2i(1, 0)]
		1: return [Vector2i(1, 1), Vector2i(1, -1)]
		2: return [Vector2i(0, -1), Vector2i(1, 0)]
		3: return [Vector2i(-1, -1), Vector2i(1, -1)]
		4: return [Vector2i(0, -1), Vector2i(-1, 0)]
		5: return [Vector2i(-1, -1), Vector2i(-1, 1)]
		6: return [Vector2i(-1, 0), Vector2i(0, 1)]
		7: return [Vector2i(-1, 1), Vector2i(1, 1)]
	return []

func get_tile_center(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x + 0.5), floor(pos.y + 0.5))

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
