class_name Player
extends Node3D

var world: InfiniteNoiseWorld
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
var player_material: StandardMaterial3D

@export var move_speed := 16.0

# Aligned System: X/Z = Flat Floor Plane, Y = Vertical Elevation
var voxel_position := Vector3(0.0, 0.0, 0.0)
var vertical_velocity: float = 0.0

const GRAVITY := 200.0
const JUMP_FORCE := 70.0
const MAX_STEP_UP_WALK := 0
const MAX_STEP_UP_JUMP := 55

const PLAYER_HEIGHT := 0.8
const PLAYER_RADIUS := 0.4

var sprite_scale_modifier := Vector2.ONE
var current_skew := 0.0

enum State { IDLE, RUNNING, JUMPING, FALLING }
var current_state := State.IDLE
var landing_timer: float = 0.0

var is_input_locked: bool = false
var locked_rotation: int = 0

# Reference to camera for rotation state
var camera: Camera3D

func _ready():
	add_to_group("player")

	world = get_tree().get_first_node_in_group("world")
	camera = get_tree().get_first_node_in_group("camera")
	
	if world == null:
		push_error("Player: World not found!")
		return

	# Set box mesh dimensions matching player radius and height
	var box := BoxMesh.new()
	box.size = Vector3(PLAYER_RADIUS * 2, PLAYER_HEIGHT, PLAYER_RADIUS * 2)
	player_mesh.mesh = box

	player_material = StandardMaterial3D.new()
	player_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	player_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	player_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	player_material.alpha_scissor_threshold = 0.5
	player_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	player_material.albedo_texture = preload("res://assets/player/player.png")
	
	player_mesh.material_override = player_material
	player_mesh.position.y = PLAYER_HEIGHT / 2.0 # Anchor sprite pivot at feet

	# Teleport player to safe spawning height (Y=45) over grid coordinate (0,0)
	voxel_position = Vector3(0.5, 257.0, 0.5) 
	while is_colliding_at(voxel_position) and voxel_position.y > 0:
		voxel_position.y -= 1.0
	
	# Place feet on top of the uppermost surface block found
	voxel_position.y += 1.0
	update_visual_position()

func _process(delta):
	if current_state != State.FALLING:
		sprite_scale_modifier = sprite_scale_modifier.lerp(Vector2.ONE, 10.0 * delta)
		current_skew = lerp(current_skew, 0.0, 10.0 * delta)

	# Input handling
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right"): input_dir.x += 1
	if Input.is_action_pressed("ui_left"): input_dir.x -= 1
	if Input.is_action_pressed("ui_down"): input_dir.y += 1
	if Input.is_action_pressed("ui_up"): input_dir.y -= 1
	input_dir = input_dir.normalized()
	
	if input_dir != Vector2.ZERO:
		if not is_input_locked:
			locked_rotation = camera.orbit_rotation if camera else 0
			is_input_locked = true
	else:
		is_input_locked = false

	# === HORIZONTAL MOVEMENT ===
	if input_dir != Vector2.ZERO:
		var move_vec = rotate_input_to_world(input_dir, locked_rotation)
		var move_delta = move_vec * move_speed * delta

		# Move and check along horizontal X axis
		var target_pos_x = voxel_position + Vector3(move_delta.x, 0, 0)
		if not is_colliding_at(target_pos_x):
			voxel_position.x = target_pos_x.x
			
		# Move and check along horizontal Z axis using move_delta.y
		var target_pos_z = voxel_position + Vector3(0, 0, move_delta.y)
		if not is_colliding_at(target_pos_z):
			voxel_position.z = target_pos_z.z

		if current_state == State.IDLE:
			change_state(State.RUNNING)
	else:
		if current_state == State.RUNNING:
			change_state(State.IDLE)

	# === VERTICAL PHSTICS STATE MACHINE ===
	match current_state:
		State.JUMPING:
			vertical_velocity -= GRAVITY * delta
			var next_pos = voxel_position + Vector3(0, vertical_velocity * delta, 0)
			
			# Ceiling collision check
			if vertical_velocity > 0 and is_colliding_at(next_pos):
				vertical_velocity = 0
				current_state = State.FALLING
			else:
				voxel_position.y = next_pos.y
				
			if vertical_velocity < 0:
				current_state = State.FALLING

		State.FALLING:
			vertical_velocity -= GRAVITY * delta
			var next_pos = voxel_position + Vector3(0, vertical_velocity * delta, 0)
			
			if is_colliding_at(next_pos):
				voxel_position.y = ceil(next_pos.y) # Clean floor alignment snap
				vertical_velocity = 0
				sprite_scale_modifier = Vector2(1.6, 0.5)
				current_skew = -0.1
				landing_timer += delta
				if landing_timer > 0.2:
					landing_timer = 0.0
					change_state(State.IDLE)
			else:
				voxel_position.y = next_pos.y

		State.IDLE, State.RUNNING:
			if Input.is_action_just_pressed("jump"):
				change_state(State.JUMPING)
			else:
				# Air check below player feet
				var test_ground_pos = voxel_position + Vector3(0, -0.1, 0)
				if not is_colliding_at(test_ground_pos):
					change_state(State.FALLING)
					vertical_velocity = 0.0 

	update_visual_position()

func rotate_input_to_world(input: Vector2, rot: int) -> Vector2:
	var angle = rot * 90.0 + 45.0
	var rad = deg_to_rad(angle)
	var ca = cos(rad)
	var sa = sin(rad)
	return Vector2(
		input.x * ca + input.y * sa,
		input.y * ca - input.x * sa
	)
	
func update_visual_position():
	# Maps data coordinates consistently onto Godot Global Space components
	global_position = Vector3(
		voxel_position.x,
		voxel_position.y,
		voxel_position.z
	)

	player_mesh.scale = Vector3(sprite_scale_modifier.x, sprite_scale_modifier.y, 1.0)
	player_mesh.rotation.y = current_skew # Apply lean along vertical rotation axis

func is_colliding_at(pos: Vector3) -> bool:
	if world == null: 
		return false
	
	var min_x = floori(pos.x - PLAYER_RADIUS)
	var max_x = floori(pos.x + PLAYER_RADIUS)
	var min_y = floori(pos.y)
	var max_y = floori(pos.y + PLAYER_HEIGHT)
	var min_z = floori(pos.z - PLAYER_RADIUS)
	var max_z = floori(pos.z + PLAYER_RADIUS)
	
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				var voxel = world.get_biome(float(x), float(y), float(z))
				if voxel.has("is_air") and not voxel["is_air"]:
					return true 
	return false

func change_state(new_state):
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state
	
	if new_state == State.JUMPING:
		vertical_velocity = JUMP_FORCE
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2
