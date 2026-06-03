class_name Player
extends Node3D

var world: InfiniteNoiseWorld

@export var move_speed := 16.0

var voxel_position := Vector3(0, 0, 0)
var vertical_velocity: float = 0.0

const GRAVITY := 200.0
const JUMP_FORCE := 70.0
const MAX_STEP_UP_WALK := 0
const MAX_STEP_UP_JUMP := 3

var sprite_scale_modifier := Vector2.ONE
var current_skew := 0.0

enum State { IDLE, RUNNING, JUMPING, FALLING }
var current_state := State.IDLE
var landing_timer: float = 0.0

var is_input_locked: bool = false
var locked_iso_rotation: int = 0
var locked_camera_angle: float = 0.0



func _ready():
	add_to_group("player")

	world = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("Player: World not found!")
		return

	var ground := get_ground_height(0, 0)
	voxel_position = Vector3(0, 0, ground)

	# === THE RENDER LAYER FORCE ===
	if has_node("Sprite3D"):
			var sprite_node = $Sprite3D
			
			var mat = StandardMaterial3D.new()
			
			# FIXED: 'no_depth_test = true' is the ultimate master override. 
			# This cleanly forces the GPU to ignore the hardware 3D depth buffer 
			# for this sprite, rendering 'DEPTH_DRAW_NEVER' completely unnecessary!
			mat.no_depth_test = true 
			
			mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			
			# Bind the clean, unshaded material override to your sprite node container
			sprite_node.material_override = mat

	update_visual_position()

func _process(delta):
	if current_state != State.FALLING:
		sprite_scale_modifier = sprite_scale_modifier.lerp(Vector2.ONE, 10.0 * delta)
		current_skew = lerp(current_skew, 0.0, 10.0 * delta)

	# Input
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right"): input_dir.x += 1
	if Input.is_action_pressed("ui_left"): input_dir.x -= 1
	if Input.is_action_pressed("ui_down"): input_dir.y += 1
	if Input.is_action_pressed("ui_up"): input_dir.y -= 1
	input_dir = input_dir.normalized()
	
	# === INTERIA STATE LOCK ===
	if input_dir != Vector2.ZERO:
		if not is_input_locked:
			# First frame of movement: snapshot the CURRENT world orientation
			locked_iso_rotation = IsoMath.rotation
			locked_camera_angle = IsoMath.rotation * 90.0
			is_input_locked = true
	else:
		# Player stopped moving: completely release lock and catch up to current camera view
		is_input_locked = false
		locked_iso_rotation = IsoMath.rotation
		locked_camera_angle = IsoMath.rotation * 90.0

	# === 1. PROCESS MOVEMENT FIRST ===
	if input_dir != Vector2.ZERO:
		# 1. Counteract the camera spin by calculating input relative to the locked perspective
		var current_camera_angle = IsoMath.rotation * 90.0
		var angle_delta = current_camera_angle - locked_camera_angle
		var counter_rotated_input = input_dir.rotated(deg_to_rad(-angle_delta))
		
		# 2. Map to isometric axes using the locked rotation matrix snapshot
		var angle = locked_iso_rotation * 90.0
		var rotated = counter_rotated_input.rotated(deg_to_rad(angle))
		if locked_iso_rotation % 2 != 0:
			rotated = Vector2(-rotated.x, -rotated.y)
		
		var iso_move = Vector2(
			rotated.x + rotated.y,
			rotated.y - rotated.x
		).normalized()

		var move_delta = iso_move * move_speed * delta
		var new_pos = voxel_position + Vector3(move_delta.x, move_delta.y, 0)

		if can_move_to(new_pos.x, voxel_position.y):
			voxel_position.x = new_pos.x
		if can_move_to(voxel_position.x, new_pos.y):
			voxel_position.y = new_pos.y

		if current_state != State.JUMPING and current_state != State.FALLING:
			var target_h = get_ground_height(roundi(voxel_position.x), roundi(voxel_position.y))
			if float(target_h) > voxel_position.z:
				voxel_position.z = float(target_h)

		if current_state == State.IDLE:
			change_state(State.RUNNING)
	else:
		if current_state == State.RUNNING:
			change_state(State.IDLE)

	# === 2. FIXED SAMPLE LOCATION ===
	# This must run AFTER movement updates to prevent height-mismatch state cancellations!
	var current_ground = get_ground_height(roundi(voxel_position.x), roundi(voxel_position.y))

	# === 3. STATE MACHINE EVALUATION ===
	match current_state:
		State.JUMPING:
			vertical_velocity -= GRAVITY * delta
			voxel_position.z += vertical_velocity * delta
			if vertical_velocity < 0:
				current_state = State.FALLING

		State.FALLING:
			vertical_velocity -= GRAVITY * delta
			voxel_position.z += vertical_velocity * delta
			if is_grounded():
				voxel_position.z = float(current_ground)
				vertical_velocity = 0
				sprite_scale_modifier = Vector2(1.6, 0.5)
				current_skew = -0.1
				landing_timer += delta
				if landing_timer > 0.2:
					landing_timer = 0.0
					change_state(State.IDLE)

		State.IDLE, State.RUNNING:
			if Input.is_action_just_pressed("jump"):
				change_state(State.JUMPING)
			elif voxel_position.z > float(current_ground) + 0.6:
				change_state(State.FALLING)
				vertical_velocity = 0.0 

	update_visual_position()

func can_move_to(new_x: float, new_y: float) -> bool:
	var tx = roundi(new_x)
	var ty = roundi(new_y)
	var cx = roundi(voxel_position.x)
	var cy = roundi(voxel_position.y)
	
	if tx == cx and ty == cy:
		return true
		
	var current_h = get_ground_height(cx, cy)
	var target_h = get_ground_height(tx, ty)
	var max_step = MAX_STEP_UP_WALK if current_state == State.IDLE or current_state == State.RUNNING else MAX_STEP_UP_JUMP

	return target_h <= current_h + max_step

func update_visual_position():
	# 1. Calculate the smooth, absolute screen positions for your player tracking
	var screen_pos = IsoMath.voxel_to_screen(voxel_position.x, voxel_position.y, voxel_position.z)
	
	# 2. SET THE GLOBAL PHYSICAL POSITION FIRST
	# We map X and Y flatly to screenspace pixels divided by 64.0.
	# We lock the root Node3D container flatly onto the 0.0 plane.
	global_position = Vector3(
		screen_pos.x / 64.0, 
		-screen_pos.y / 64.0,  
		0.0 
	)

	# 3. === THE UNIFIED DEPTH MATRIX SYNCHRONIZER ===
	# Instead of guessing the tile's screen row with roundi(), we read our active global_position.y vector!
	# Because we inverted the screen scale earlier (-screen_pos.y / 64.0), we multiply by -64.0 to turn 
	# it right-side up, and add voxel_position.z * 2.0 to perfectly replicate your chunk's depth_key math!
	var true_screen_y = -global_position.y * 64.0
	var matching_depth_key = int(true_screen_y + (voxel_position.z * 2.0))

	# 4. ASSIGN THE EXPLICIT OVERLAY LAYER SORT
	# We pass the calculated key straight to your child Sprite3D component.
	# The +1.0 integer priority modifier ensures your character draws beautifully on top 
	# of their active floor row, while staying safely behind foreground blocks lower down the screen!
	if has_node("Sprite3D"):
		var sprite_node = $Sprite3D
		sprite_node.sorting_offset = float(matching_depth_key) + 1.0
		
		# Keep your running squash, stretch, and skew animations functional
		sprite_node.scale = Vector3(sprite_scale_modifier.x, sprite_scale_modifier.y, 1.0)
		sprite_node.rotation.z = current_skew

func get_ground_height(x: int, y: int) -> int:
	if world == null: return 0
	return world.get_biome(x, y)["render_height"]

func is_grounded() -> bool:
	var ground := get_ground_height(roundi(voxel_position.x), roundi(voxel_position.y))
	return voxel_position.z <= float(ground) + 0.1 and vertical_velocity <= 0

func change_state(new_state):
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state
	
	if new_state == State.JUMPING:
		vertical_velocity = JUMP_FORCE
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2
