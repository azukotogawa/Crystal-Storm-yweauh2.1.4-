class_name Player
extends Node3D

const _Inventory = preload("res://inventory/inventory.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _StatComponent = preload("res://stats/stat_component.gd")
const _RelicManager = preload("res://relics/relic_manager.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var stat_component: _StatComponent
var relic_manager: _RelicManager

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
var inventory
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
var player_material: StandardMaterial3D

@export var move_speed := 16.0
@export var max_health := 100.0

signal died

var health := 100.0

# Logical column coordinates (X/Z); Y is world height in meters/layer units.
var voxel_position := Vector3(0.0, 0.0, 0.0)
var vertical_velocity: float = 0.0

var sprite_scale_modifier := Vector2.ONE
var current_skew := 0.0

enum State { IDLE, RUNNING, JUMPING, FALLING }
var current_state := State.IDLE
var landing_timer: float = 0.0

var is_input_locked: bool = false
var locked_rotation: int = 0

var camera: Camera3D
var world_ready := false

const _FLOOR_PROBE_OFFSETS := [
	Vector2(0.0, 0.0),
	Vector2(0.22, 0.0),
	Vector2(-0.22, 0.0),
	Vector2(0.0, 0.22),
	Vector2(0.0, -0.22),
]


func _ws():
	return _WorldSettings.get_active()


static func get_player_height() -> float:
	return _WorldSettings.get_active().player_height()


static func get_player_radius() -> float:
	return _WorldSettings.get_active().player_radius()


func _player_height() -> float:
	return _ws().player_height()


func _player_radius() -> float:
	return _ws().player_radius()


func _gravity() -> float:
	return 200.0 * _ws().voxel_scale


func _jump_force() -> float:
	return 70.0 * sqrt(_ws().voxel_scale)


func _enter_tree():
	add_to_group("player")


func _ready():
	stat_component = _StatComponent.new()
	stat_component.name = "StatComponent"
	add_child(stat_component)
	stat_component.load_bases_from_exports(max_health, move_speed)
	stat_component.stat_changed.connect(_on_stat_changed)

	relic_manager = _RelicManager.new()
	relic_manager.name = "RelicManager"
	add_child(relic_manager)

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

	while not chunk_manager.spawn_area_ready(0, 0):
		await get_tree().process_frame

	var ph := _player_height()
	var pr := _player_radius()
	var box := BoxMesh.new()
	box.size = Vector3(pr * 2.0, ph, pr * 2.0)
	player_mesh.mesh = box

	player_material = StandardMaterial3D.new()
	player_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	player_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	player_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	player_material.alpha_scissor_threshold = 0.5
	player_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	player_material.albedo_texture = preload("res://assets/player/player.png")

	player_mesh.material_override = player_material
	player_mesh.position.y = ph / 2.0

	var spawn_x := 0.5
	var spawn_z := 0.5
	var surf := _sample_walkable_feet(spawn_x, spawn_z)
	max_health = stat_component.get_stat(_StatIds.MAX_HEALTH)
	health = max_health
	voxel_position = Vector3(spawn_x, surf, spawn_z)
	while is_colliding_at(voxel_position) and voxel_position.y < surf + _ws().layer_height() * 3.0:
		voxel_position.y += _ws().half_layer() * 0.1

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
		var speed := stat_component.get_stat(_StatIds.MOVE_SPEED) if stat_component else move_speed
		var move_delta = move_vec * speed * delta

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

	match current_state:
		State.JUMPING:
			vertical_velocity -= _gravity() * delta
			var next_pos = voxel_position + Vector3(0, vertical_velocity * delta, 0)
			if vertical_velocity > 0 and is_colliding_at(next_pos):
				vertical_velocity = 0
				current_state = State.FALLING
			else:
				voxel_position.y = next_pos.y
			if vertical_velocity < 0:
				current_state = State.FALLING

		State.FALLING:
			vertical_velocity -= _gravity() * delta
			var next_pos = voxel_position + Vector3(0, vertical_velocity * delta, 0)
			if is_colliding_at(next_pos):
				voxel_position.y = _sample_walkable_feet(voxel_position.x, voxel_position.z)
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
			if Input.is_action_just_pressed("jump") and _is_grounded():
				change_state(State.JUMPING)
			else:
				_snap_to_ground()
				if not _is_grounded():
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
	var ws = _ws()
	global_position = Vector3(
		ws.column_to_world(voxel_position.x),
		voxel_position.y,
		ws.column_to_world(voxel_position.z)
	)
	player_mesh.scale = Vector3(sprite_scale_modifier.x, sprite_scale_modifier.y, 1.0)
	player_mesh.rotation.y = current_skew


func is_colliding_at(pos: Vector3) -> bool:
	if chunk_manager == null or chunk_manager.world == null:
		return false

	var world_ref := chunk_manager.world
	var floor_h := _sample_walkable_feet(pos.x, pos.z)
	var layer: float = _ws().layer_height()

	if pos.y < floor_h - layer * 0.15:
		return true

	var surf := world_ref.get_surface_height(pos.x, pos.z)
	if pos.y < surf - layer * 0.75:
		if world_ref.has_method("get_cave_floor_height"):
			var cave_floor := world_ref.get_cave_floor_height(pos.x, pos.z)
			if cave_floor > 0.01 and pos.y < cave_floor - layer * 0.05:
				return true

	if world_ref.has_method("get_solid"):
		var head_y := pos.y + _player_height()
		var pr := _player_radius()
		var player_min := pos - Vector3(pr, 0, pr)
		var player_max := pos + Vector3(pr, 0, pr)
		for x_world in range(floori(player_min.x), floori(player_max.x) + 1):
			for z_world in range(floori(player_min.z), floori(player_max.z) + 1):
				var wx := float(x_world)
				var wz := float(z_world)
				var check_y := floori(head_y)
				if world_ref.get_solid(wx, float(check_y), wz) or \
						world_ref.get_solid(wx, float(check_y + 1), wz):
					return true

	return false


func _can_move_to(proposed: Vector3) -> bool:
	var target_feet := _sample_walkable_feet(proposed.x, proposed.z)
	var rise := target_feet - proposed.y
	var max_step: float = _ws().max_step_up_walk()
	if current_state == State.JUMPING or current_state == State.FALLING:
		max_step = _ws().max_step_up_jump()
	if rise > -_ws().floor_snap_distance() and rise <= max_step:
		var stepped := proposed
		stepped.y = target_feet
		return not is_colliding_at(stepped)
	if not is_colliding_at(proposed):
		return true
	return false


func _snap_to_ground() -> void:
	if chunk_manager == null or chunk_manager.world == null:
		return
	var target_feet := _sample_walkable_feet(voxel_position.x, voxel_position.z)
	var diff := target_feet - voxel_position.y
	if absf(diff) <= _ws().max_step_up_jump():
		voxel_position.y = target_feet


func _sample_walkable_feet(wx: float, wz: float) -> float:
	var best := -INF
	for offset in _FLOOR_PROBE_OFFSETS:
		best = maxf(best, _walkable_height_at(wx + offset.x, wz + offset.y))
	return best


func _is_grounded() -> bool:
	var floor_h := _sample_walkable_feet(voxel_position.x, voxel_position.z)
	return absf(voxel_position.y - floor_h) <= _ws().floor_snap_distance()


func _walkable_height_at(wx: float, wz: float) -> float:
	if chunk_manager and chunk_manager.world:
		var world_ref := chunk_manager.world
		var surf := world_ref.get_surface_height(wx, wz)
		if voxel_position.y < surf - _ws().layer_height() * 0.75 and world_ref.has_method("get_cave_floor_height"):
			var cave_floor := world_ref.get_cave_floor_height(wx, wz)
			if cave_floor > 0.01:
				return cave_floor
		var ramp_entry := _ramp_entry_at(wx, wz)
		var base := TerrainRamps.walkable_height_from_entry(world_ref, wx, wz, ramp_entry)
		if crystal_manager and crystal_manager.has_method("get_walkable_height"):
			return maxf(base, crystal_manager.get_walkable_height(wx, wz))
		return base
	if crystal_manager and crystal_manager.has_method("get_walkable_height"):
		return crystal_manager.get_walkable_height(wx, wz)
	if chunk_manager and chunk_manager.world:
		return TerrainRamps.walkable_height(chunk_manager.world, wx, wz)
	return _ws().layer_height()


func _ramp_entry_at(wx: float, wz: float) -> Dictionary:
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		return chunk_manager.get_ramp_entry_at_world(wx, wz)
	return {}


func _give_starting_loadout() -> void:
	inventory.set_slot(0, "wooden_sword", 1)
	inventory.set_slot(1, "stone_pick", 1)
	inventory.set_slot(2, "shortbow", 1)
	inventory.set_slot(3, "wood", 16)
	inventory.set_slot(4, "stone", 8)
	inventory.set_slot(5, "herb", 4)


func get_stat(stat_id: StringName) -> float:
	return stat_component.get_stat(stat_id) if stat_component else 0.0


func get_voxel_position() -> Vector3:
	return voxel_position


func _on_stat_changed(stat_id: StringName, value: float) -> void:
	if stat_id == _StatIds.MAX_HEALTH:
		var ratio := health / maxf(max_health, 1.0)
		max_health = value
		health = clampf(health, 0.0, max_health)
		if health <= 0.0 and ratio > 0.0:
			health = maxf(1.0, max_health * ratio)


func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	var defense := get_stat(_StatIds.DEFENSE)
	amount *= (1.0 - clampf(defense, 0.0, 0.9))
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		died.emit()


func change_state(new_state):
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state

	if new_state == State.JUMPING:
		vertical_velocity = _jump_force()
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2
