class_name Player
extends Node3D

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
var player_material: StandardMaterial3D

@export var move_speed := 160.0

var voxel_position := Vector3(0.0, 0.0, 0.0)
var vertical_velocity: float = 0.0

const GRAVITY := 200.0
const JUMP_FORCE := 70.0
const MAX_STEP_UP_WALK := 0
const MAX_STEP_UP_JUMP := 5

const PLAYER_HEIGHT := 0.8
const PLAYER_RADIUS := 0.4

var sprite_scale_modifier := Vector2.ONE
var current_skew := 0.0

enum State { IDLE, RUNNING, JUMPING, FALLING }
var current_state := State.IDLE
var landing_timer: float = 0.0

var is_input_locked: bool = false
var locked_rotation: int = 0

var camera: Camera3D

var world_ready := false

func _enter_tree():
	add_to_group("player")

func _ready():

	world = get_tree().get_first_node_in_group("world")
	camera = get_tree().get_first_node_in_group("camera")
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		await get_tree().process_frame
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")


	while not chunk_manager.spawn_area_ready(0, 0):
		await get_tree().process_frame

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
	player_mesh.position.y = PLAYER_HEIGHT / 2.0

	var spawn_x := 0.5
	var spawn_z := 0.5
	var surf := 0.0
	if chunk_manager != null and chunk_manager.world != null:
		surf = chunk_manager.world.get_surface_height(spawn_x, spawn_z)
	voxel_position = Vector3(spawn_x, surf + 1.0, spawn_z)
	while is_colliding_at(voxel_position) and voxel_position.y < surf + 5.0:
		voxel_position.y += 0.1
	
	update_visual_position()
	world_ready = true

func _process(delta):
	if not world_ready:
		return
	if current_state != State.FALLING:
		sprite_scale_modifier = sprite_scale_modifier.lerp(Vector2.ONE, 10.0 * delta)
		current_skew = lerp(current_skew, 0.0, 10.0 * delta)

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

	if input_dir != Vector2.ZERO:
		var move_vec = rotate_input_to_world(input_dir, locked_rotation)
		var move_delta = move_vec * move_speed * delta

		var target_pos_x = voxel_position + Vector3(move_delta.x, 0, 0)
		if not is_colliding_at(target_pos_x) or _is_small_step_up(target_pos_x):
			voxel_position.x = target_pos_x.x
			_try_step_up()
			
		var target_pos_z = voxel_position + Vector3(0, 0, move_delta.y)
		if not is_colliding_at(target_pos_z) or _is_small_step_up(target_pos_z):
			voxel_position.z = target_pos_z.z
			_try_step_up()

		if current_state == State.IDLE:
			change_state(State.RUNNING)
	else:
		if current_state == State.RUNNING:
			change_state(State.IDLE)

	match current_state:
		State.JUMPING:
			vertical_velocity -= GRAVITY * delta
			var next_pos = voxel_position + Vector3(0, vertical_velocity * delta, 0)
			
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
				if chunk_manager != null and chunk_manager.world != null:
					voxel_position.y = _walkable_height_at(voxel_position.x, voxel_position.z)
				else:
					voxel_position.y = ceil(next_pos.y)
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
	global_position = Vector3(
		voxel_position.x,
		voxel_position.y,
		voxel_position.z
	)

	player_mesh.scale = Vector3(sprite_scale_modifier.x, sprite_scale_modifier.y, 1.0)
	player_mesh.rotation.y = current_skew

func is_colliding_at(pos: Vector3) -> bool:
	if chunk_manager == null or chunk_manager.world == null:
		return false

	var world = chunk_manager.world

	var player_min = pos - Vector3(PLAYER_RADIUS, 0, PLAYER_RADIUS)
	var player_max = pos + Vector3(PLAYER_RADIUS, PLAYER_HEIGHT, PLAYER_RADIUS)
	
	var head_y := pos.y + PLAYER_HEIGHT

	for x_world in range(floori(player_min.x), floori(player_max.x) + 1):
		for z_world in range(floori(player_min.z), floori(player_max.z) + 1):
			var slab_top := _walkable_height_at(float(x_world), float(z_world))
			if pos.y < slab_top:
				return true

			if world.has_method("get_solid"):
				var check_y := floori(head_y)
				if world.get_solid(float(x_world), float(check_y), float(z_world)) or \
				   world.get_solid(float(x_world), float(check_y + 1), float(z_world)):
					return true

	return false

func _try_step_up():
	if chunk_manager == null or chunk_manager.world == null:
		return
	var target_feet := _walkable_height_at(voxel_position.x, voxel_position.z)
	var diff := target_feet - voxel_position.y
	if diff > 0.01 and diff <= 2.0:
		voxel_position.y = target_feet

func _is_small_step_up(proposed: Vector3) -> bool:
	if chunk_manager == null or chunk_manager.world == null:
		return false
	var w = chunk_manager.world
	var cur_s := int(w.get_surface_height(voxel_position.x, voxel_position.z))
	var new_s := int(w.get_surface_height(proposed.x, proposed.z))
	var rise := new_s - cur_s
	return rise > 0 and rise <= 2

func _walkable_height_at(wx: float, wz: float) -> float:
	if crystal_manager and crystal_manager.has_method("get_walkable_height"):
		return crystal_manager.get_walkable_height(wx, wz)
	if chunk_manager and chunk_manager.world:
		return chunk_manager.world.get_surface_height(wx, wz) + 1.0
	return 1.0


func change_state(new_state):
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state
	
	if new_state == State.JUMPING:
		vertical_velocity = JUMP_FORCE
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2
