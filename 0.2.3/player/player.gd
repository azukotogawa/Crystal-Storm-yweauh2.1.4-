class_name Player
extends Node3D

var world: InfiniteNoiseWorld
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
var player_material: StandardMaterial3D

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
var locked_rotation: int = 0

# Reference to camera for rotation state
var camera: Camera3D

func _ready():
	add_to_group("player")

	world = get_tree().get_first_node_in_group("world")
	camera = get_tree().get_first_node_in_group("camera")  # or find by path if needed
	
	if world == null:
		push_error("Player: World not found!")
		return

	var ground := get_ground_height(0, 0)
	voxel_position = Vector3(0, 0, ground)

	# Box mesh for 3D voxel player
	var box := BoxMesh.new()
	box.size = Vector3(0.5,0.5,0.5)
	player_mesh.mesh = box

	player_material = StandardMaterial3D.new()
	player_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	player_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	player_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	player_material.alpha_scissor_threshold = 0.5
	player_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	player_material.albedo_texture = preload("res://assets/player/player.png")
	
	player_mesh.material_override = player_material
	player_mesh.position.y = 1.0

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
	
# Lock direction to camera rotation when movement starts
	if input_dir != Vector2.ZERO:
		if not is_input_locked:
			locked_rotation = camera.orbit_rotation if camera else 0
			is_input_locked = true
	else:
		is_input_locked = false

	# === MOVEMENT ===
	if input_dir != Vector2.ZERO:
		var move_vec = rotate_input_to_world(input_dir, locked_rotation)
		var move_delta = move_vec * move_speed * delta

		var new_x = voxel_position.x + move_delta.x
		var new_y = voxel_position.y + move_delta.y

		if can_move_to(new_x, voxel_position.y):
			voxel_position.x = new_x
		if can_move_to(voxel_position.x, new_y):
			voxel_position.y = new_y

		if current_state != State.JUMPING and current_state != State.FALLING:
			var target_h = get_ground_height(roundi(voxel_position.x), roundi(voxel_position.y))
			if float(target_h) > voxel_position.z:
				voxel_position.z = float(target_h)

		if current_state == State.IDLE:
			change_state(State.RUNNING)
	else:
		if current_state == State.RUNNING:
			change_state(State.IDLE)

	# Ground check + state machine
	var current_ground = get_ground_height(roundi(voxel_position.x), roundi(voxel_position.y))

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

func rotate_input_to_world(input: Vector2, rot: int) -> Vector2:
	var angle = rot * 90.0 + 45.0
	var rad = deg_to_rad(angle)
	var ca = cos(rad)
	var sa = sin(rad)
	
	# Rotate the input vector
	return Vector2(
		input.x * ca + input.y * sa,
		input.y * ca - input.x * sa
	)

# ... (rest of the file - can_move_to, update_visual_position, etc. stay the same)
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
	global_position = Vector3(
		voxel_position.x + 1.0,
		voxel_position.z,
		voxel_position.y + 1.0
	)

	player_mesh.scale = Vector3(sprite_scale_modifier.x, sprite_scale_modifier.y, 1.0)
	player_mesh.rotation.z = current_skew

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
