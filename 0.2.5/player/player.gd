class_name Player
extends Node3D

const _Inventory = preload("res://inventory/inventory.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
var inventory
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
var player_material: StandardMaterial3D

@export var move_speed := 16.0

# Aligned System: X/Z = Flat Floor Plane, Y = Vertical Elevation
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

# Reference to camera for rotation state
var camera: Camera3D

var world_ready := false

func _enter_tree():
	add_to_group("player")

func _ready():
	inventory = _Inventory.new()
	_give_starting_loadout()

	var weapon := _WeaponController.new()
	weapon.name = "WeaponController"
	add_child(weapon)

	world = get_tree().get_first_node_in_group("world")
	camera = get_tree().get_first_node_in_group("camera")
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		await get_tree().process_frame
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")


	# Wait until spawn area exists
	while not chunk_manager.spawn_area_ready(0, 0):
		await get_tree().process_frame

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

	# Place player directly on the surface for the spawn column (0.5, 0.5).
	# Use world surface directly (works even if visuals not yet loaded).
	var spawn_x := 0.5
	var spawn_z := 0.5
	var surf := 0.0
	if chunk_manager != null and chunk_manager.world != null:
		surf = TerrainRamps.walkable_height(chunk_manager.world, spawn_x, spawn_z) - 1.0
	voxel_position = Vector3(spawn_x, surf + 1.0, spawn_z)
	# Safety nudge if still inside (floating point / edge)
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

		var target_pos_x = voxel_position + Vector3(move_delta.x, 0, 0)
		if _can_move_to(target_pos_x):
			voxel_position.x = target_pos_x.x
			_snap_to_ground()

		var target_pos_z = voxel_position + Vector3(0, 0, move_delta.y)
		if _can_move_to(target_pos_z):
			voxel_position.z = target_pos_z.z
			_snap_to_ground()

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
				# Snap cleanly to the surface height of the current column.
				# get_surface_height already returns the correct playable top (after natural rivers, carving, cave breaches).
				# This keeps behavior consistent with meshing, step-up, and the original heightfield model.
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
				_snap_to_ground()
				var test_ground_pos = voxel_position + Vector3(0, -0.15, 0)
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
	if chunk_manager == null or chunk_manager.world == null:
		return false

	var world = chunk_manager.world
	var surf := world.get_surface_height(pos.x, pos.z)
	var underground := pos.y < surf - 0.75

	if underground:
		if world.has_method("get_cave_floor_height"):
			var floor_h := world.get_cave_floor_height(pos.x, pos.z)
			if floor_h > 0.01 and pos.y < floor_h - 0.02:
				return true
	else:
		var ground := _walkable_height_at(pos.x, pos.z)
		if pos.y < ground - 0.02:
			return true

	if world.has_method("get_solid"):
		var head_y := pos.y + PLAYER_HEIGHT
		var player_min := pos - Vector3(PLAYER_RADIUS, 0, PLAYER_RADIUS)
		var player_max := pos + Vector3(PLAYER_RADIUS, 0, PLAYER_RADIUS)
		for x_world in range(floori(player_min.x), floori(player_max.x) + 1):
			for z_world in range(floori(player_min.z), floori(player_max.z) + 1):
				var wx := float(x_world)
				var wz := float(z_world)
				var check_y := floori(head_y)
				if world.get_solid(wx, float(check_y), wz) or \
						world.get_solid(wx, float(check_y + 1), wz):
					return true

	return false

func _can_move_to(proposed: Vector3) -> bool:
	if not is_colliding_at(proposed):
		return true
	var target_feet := _walkable_height_at(proposed.x, proposed.z)
	var rise := target_feet - proposed.y
	return rise > -0.05 and rise <= 2.5


func _snap_to_ground() -> void:
	if chunk_manager == null or chunk_manager.world == null:
		return
	var target_feet := _walkable_height_at(voxel_position.x, voxel_position.z)
	var diff := target_feet - voxel_position.y
	if absf(diff) <= 2.5:
		voxel_position.y = target_feet

func _terrain_height_at(wx: float, wz: float) -> float:
	if chunk_manager and chunk_manager.world:
		return TerrainRamps.walkable_height(chunk_manager.world, wx, wz) - 1.0
	return 0.0


func _ramp_dir_at(wx: float, wz: float) -> Vector2i:
	if chunk_manager and chunk_manager.has_method("get_ramp_dir_at_world"):
		return chunk_manager.get_ramp_dir_at_world(wx, wz)
	return Vector2i.ZERO


func _walkable_height_at(wx: float, wz: float) -> float:
	if chunk_manager and chunk_manager.world:
		var world_ref := chunk_manager.world
		var surf := world_ref.get_surface_height(wx, wz)
		if voxel_position.y < surf - 0.75 and world_ref.has_method("get_cave_floor_height"):
			var cave_floor := world_ref.get_cave_floor_height(wx, wz)
			if cave_floor > 0.01:
				return cave_floor
		var ramp_dir := _ramp_dir_at(wx, wz)
		var base := TerrainRamps.walkable_height(world_ref, wx, wz, ramp_dir)
		if crystal_manager and crystal_manager.has_method("get_walkable_height"):
			return maxf(base, crystal_manager.get_walkable_height(wx, wz))
		return base
	if crystal_manager and crystal_manager.has_method("get_walkable_height"):
		return crystal_manager.get_walkable_height(wx, wz)
	if chunk_manager and chunk_manager.world:
		return TerrainRamps.walkable_height(chunk_manager.world, wx, wz)
	return 1.0


func _give_starting_loadout() -> void:
	inventory.set_slot(0, "wooden_sword", 1)
	inventory.set_slot(1, "stone_pick", 1)
	inventory.set_slot(2, "shortbow", 1)
	inventory.set_slot(3, "wood", 16)
	inventory.set_slot(4, "stone", 8)
	inventory.set_slot(5, "herb", 4)


func change_state(new_state):
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state
	
	if new_state == State.JUMPING:
		vertical_velocity = JUMP_FORCE
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2
