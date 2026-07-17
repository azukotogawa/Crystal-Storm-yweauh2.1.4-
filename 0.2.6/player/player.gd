class_name Player
extends CharacterBody3D

const _Inventory = preload("res://inventory/inventory.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _StatComponent = preload("res://stats/stat_component.gd")
const _RelicManager = preload("res://relics/relic_manager.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

var stat_component: _StatComponent
var relic_manager: _RelicManager

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
var inventory
@onready var player_mesh: MeshInstance3D = $MeshInstance3D
var player_material: StandardMaterial3D
var _body_collision: CollisionShape3D

@export var move_speed := 16.0
@export var max_health := 100.0

signal died

var health := 100.0

## Logical column coordinates for X/Z; Y is world height in layer units.
var voxel_position := Vector3(0.0, 0.0, 0.0)

var sprite_scale_modifier := Vector2.ONE
var current_skew := 0.0

enum State { IDLE, RUNNING, JUMPING, FALLING }
var current_state := State.IDLE
var landing_timer: float = 0.0

var is_input_locked: bool = false
var locked_rotation: int = 0

var camera: Camera3D
var world_ready := false

var _floor_probe: _VoxelFloorProbe


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
	return 200.0 * _ws().voxel_scale * _ws().player_gravity_scale


func _jump_force() -> float:
	return 70.0 * sqrt(_ws().voxel_scale) * _ws().player_jump_scale


func _enter_tree():
	add_to_group("player")


func _ready():
	motion_mode = MOTION_MODE_FLOATING
	floor_max_angle = deg_to_rad(_ws().player_slope_limit_degrees)
	up_direction = Vector3.UP
	floor_snap_length = _ws().player_safe_margin

	stat_component = _StatComponent.new()
	stat_component.name = "StatComponent"
	add_child(stat_component)
	stat_component.load_bases_from_exports(max_health, move_speed)
	stat_component.stat_changed.connect(_on_stat_changed)

	relic_manager = _RelicManager.new()
	relic_manager.name = "RelicManager"
	add_child(relic_manager)
	# Vertical-slice starter relic: measurable crystal flow dampening.
	if relic_manager.has_method("equip"):
		relic_manager.equip(&"crystal_ward")

	inventory = _Inventory.new()
	_give_starting_loadout()

	var weapon := _WeaponController.new()
	weapon.name = "WeaponController"
	add_child(weapon)

	var highlight := preload("res://player/target_highlight.gd").new()
	highlight.name = "TargetHighlight"
	add_child(highlight)

	world = get_tree().get_first_node_in_group("world")
	camera = get_tree().get_first_node_in_group("camera")
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		await get_tree().process_frame
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")

	_floor_probe = _VoxelFloorProbe.new()
	_floor_probe.configure(world, chunk_manager, crystal_manager)

	_setup_body_collision()

	if crystal_manager:
		await crystal_manager.ensure_ready()

	var spawn_col := _resolve_spawn_column()
	_ensure_spawn_chunks_loaded(spawn_col)
	for _warmup in 180:
		if chunk_manager.spawn_area_ready(spawn_col.x, spawn_col.y):
			break
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

	var spawn_x := float(spawn_col.x) + 0.5
	var spawn_z := float(spawn_col.y) + 0.5
	_floor_probe.feet_height_hint = _ws().layer_height()
	var surf := _sample_walkable_feet(spawn_x, spawn_z)
	max_health = stat_component.get_stat(_StatIds.MAX_HEALTH)
	health = max_health
	voxel_position = Vector3(spawn_x, surf, spawn_z)
	while is_colliding_at(voxel_position) and voxel_position.y < surf + _ws().layer_height() * 3.0:
		voxel_position.y += _ws().half_layer() * 0.1

	_sync_global_from_voxel()
	world_ready = true
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(1)


func _setup_body_collision() -> void:
	if not _ws().player_use_character_body:
		return
	var ph := _player_height()
	var pr := _player_radius()
	var capsule := CapsuleShape3D.new()
	capsule.radius = pr
	capsule.height = maxf(ph, pr * 2.0)
	_body_collision = CollisionShape3D.new()
	_body_collision.name = "BodyCollision"
	_body_collision.shape = capsule
	_body_collision.position.y = ph * 0.5
	add_child(_body_collision)


func _physics_process(delta: float) -> void:
	if not world_ready:
		return

	_floor_probe.feet_height_hint = voxel_position.y

	if current_state != State.FALLING:
		sprite_scale_modifier = sprite_scale_modifier.lerp(Vector2.ONE, 10.0 * delta)
		current_skew = lerp(current_skew, 0.0, 10.0 * delta)

	var input_dir := Vector2.ZERO
	if not _GameplayInput.blocks_actions():
		if Input.is_action_pressed("ui_right"):
			input_dir.x += 1
		if Input.is_action_pressed("ui_left"):
			input_dir.x -= 1
		if Input.is_action_pressed("ui_down"):
			input_dir.y += 1
		if Input.is_action_pressed("ui_up"):
			input_dir.y -= 1
		input_dir = input_dir.normalized()

	var moving := input_dir != Vector2.ZERO
	if not _GameplayInput.blocks_actions() \
			and current_state in [State.IDLE, State.RUNNING] \
			and Input.is_action_just_pressed("jump"):
		if _can_initiate_jump(moving):
			change_state(State.JUMPING)

	if input_dir != Vector2.ZERO:
		if not is_input_locked:
			locked_rotation = camera.orbit_rotation if camera else 0
			is_input_locked = true
	else:
		is_input_locked = false

	var speed := stat_component.get_stat(_StatIds.MOVE_SPEED) if stat_component else move_speed
	speed *= _slope_speed_multiplier()

	var airborne := current_state in [State.JUMPING, State.FALLING]
	if input_dir != Vector2.ZERO:
		var move_vec := rotate_input_to_world(input_dir, locked_rotation)
		var move_delta := move_vec * speed * delta

		var target_pos_x := voxel_position + Vector3(move_delta.x, 0.0, 0.0)
		if _can_move_to(target_pos_x, airborne):
			voxel_position.x = target_pos_x.x
			if not airborne:
				_snap_to_ground()

		var target_pos_z := voxel_position + Vector3(0.0, 0.0, move_delta.y)
		if _can_move_to(target_pos_z, airborne):
			voxel_position.z = target_pos_z.z
			if not airborne:
				_snap_to_ground()

		if not airborne and current_state == State.IDLE:
			change_state(State.RUNNING)
	elif not airborne and current_state == State.RUNNING:
		change_state(State.IDLE)

	match current_state:
		State.JUMPING:
			velocity.y -= _gravity() * delta
			var next_pos := voxel_position + Vector3(0.0, velocity.y * delta, 0.0)
			if velocity.y > 0.0 and is_colliding_at(next_pos):
				velocity.y = 0.0
				current_state = State.FALLING
			else:
				voxel_position.y = next_pos.y
			if velocity.y < 0.0:
				current_state = State.FALLING

		State.FALLING:
			velocity.y -= _gravity() * delta
			var next_pos := voxel_position + Vector3(0.0, velocity.y * delta, 0.0)
			if is_colliding_at(next_pos):
				voxel_position.y = _sample_walkable_feet(voxel_position.x, voxel_position.z)
				velocity.y = 0.0
				sprite_scale_modifier = Vector2(1.6, 0.5)
				current_skew = -0.1
				landing_timer += delta
				if landing_timer > 0.2:
					landing_timer = 0.0
					change_state(State.RUNNING if moving else State.IDLE)
			else:
				voxel_position.y = next_pos.y

		State.IDLE, State.RUNNING:
			_snap_to_ground()
			if not _is_grounded(moving):
				change_state(State.FALLING)
				velocity.y = 0.0

	_sync_global_from_voxel()
	player_mesh.scale = Vector3(sprite_scale_modifier.x, sprite_scale_modifier.y, 1.0)
	player_mesh.rotation.y = current_skew


func _slope_speed_multiplier() -> float:
	var excess: float = _floor_probe.slope_excess_at(voxel_position.x, voxel_position.z)
	var layer: float = _ws().layer_height()
	var radius: float = _ws().player_floor_probe_radius
	var slope_limit: float = tan(deg_to_rad(_ws().player_slope_limit_degrees)) * radius
	if excess <= slope_limit:
		return 1.0
	return clampf(1.0 - (excess - slope_limit) / layer, 0.35, 1.0)


func rotate_input_to_world(input: Vector2, rot: int) -> Vector2:
	var angle := rot * 90.0 + 45.0
	var rad := deg_to_rad(angle)
	var ca := cos(rad)
	var sa := sin(rad)
	return Vector2(
		input.x * ca + input.y * sa,
		input.y * ca - input.x * sa
	)


func _sync_global_from_voxel() -> void:
	var ws: WorldSettings = _ws()
	global_position = Vector3(
		ws.column_to_world(voxel_position.x),
		voxel_position.y,
		ws.column_to_world(voxel_position.z)
	)


func is_colliding_at(pos: Vector3) -> bool:
	_floor_probe.feet_height_hint = pos.y
	return _floor_probe.is_blocked_at(pos, _player_height(), _player_radius())


func _can_move_to(proposed: Vector3, airborne: bool = false) -> bool:
	if not airborne:
		airborne = current_state == State.JUMPING or current_state == State.FALLING
	var max_step: float = _ws().max_step_up_walk()
	if airborne:
		max_step = _ws().max_step_up_jump()
	return _floor_probe.can_step_to(
		voxel_position,
		proposed,
		_player_height(),
		_player_radius(),
		max_step,
		airborne
	)


func _snap_to_ground() -> void:
	if chunk_manager == null or chunk_manager.world == null:
		return
	voxel_position = _floor_probe.snap_position_y(voxel_position)


func _sample_walkable_feet(wx: float, wz: float) -> float:
	return _floor_probe.sample_walkable_feet(wx, wz)


func _ground_snap_distance(moving: bool) -> float:
	var snap: float = _ws().floor_snap_distance()
	if moving:
		# Match probe min/max band while stepping between columns (avoids spurious FALLING).
		snap += _ws().layer_height() * 0.45
	return snap


func _is_grounded(moving: bool = false) -> bool:
	return _floor_probe.is_grounded_at(voxel_position, _ground_snap_distance(moving))


func _can_initiate_jump(moving: bool) -> bool:
	return _is_grounded(moving)


func _give_starting_loadout() -> void:
	inventory.set_slot(0, "wooden_sword", 1)
	inventory.set_slot(1, "stone_pick", 1)
	inventory.set_slot(2, "shortbow", 1)
	inventory.set_slot(3, "wood", 16)
	inventory.set_slot(4, "stone", 8)
	inventory.set_slot(5, "herb", 4)


func _ensure_spawn_chunks_loaded(spawn_col: Vector2i) -> void:
	if chunk_manager == null or not chunk_manager.has_method("request_chunk"):
		return
	var cols: Array[Vector2i] = [spawn_col]
	if crystal_manager:
		for spawn in crystal_manager.get_active_spawns():
			cols.append(spawn.world_pos)
	for col in cols:
		var coord := Vector2i(
			floori(float(col.x) / float(_ChunkData.SIZE)),
			floori(float(col.y) / float(_ChunkData.SIZE))
		)
		chunk_manager.request_chunk(coord, true)


func _resolve_spawn_column() -> Vector2i:
	var col := Vector2i(0, 0)
	if crystal_manager == null:
		return col
	var source: Vector2i = Vector2i.ZERO
	for spawn in crystal_manager.get_active_spawns():
		if spawn.is_boss:
			source = spawn.world_pos
			break
	if source == Vector2i.ZERO:
		var spawns: Array = crystal_manager.get_active_spawns()
		if not spawns.is_empty():
			source = spawns[0].world_pos
	# Stand uphill from the origin boss so crystal fluid flows toward the player.
	for offset in [Vector2i(4, -4), Vector2i(3, -5), Vector2i(5, -3), Vector2i(2, -6), Vector2i(6, -2)]:
		var candidate: Vector2i = source + offset
		if world and not _CrystalTypes.is_water_tile(world.get_tile_type(float(candidate.x), float(candidate.y))):
			return candidate
	return source + Vector2i(4, -4)


func get_stat(stat_id: StringName) -> float:
	return stat_component.get_stat(stat_id) if stat_component else 0.0


func get_voxel_position() -> Vector3:
	return voxel_position


func _on_stat_changed(stat_id: StringName, _value: float) -> void:
	if stat_id == _StatIds.MAX_HEALTH:
		var ratio := health / maxf(max_health, 1.0)
		max_health = stat_component.get_stat(_StatIds.MAX_HEALTH)
		health = clampf(health, 0.0, max_health)
		if health <= 0.0 and ratio > 0.0:
			health = maxf(1.0, max_health * ratio)


func export_save_state() -> Dictionary:
	var hotbar_index := 0
	var weapon := get_node_or_null("WeaponController")
	if weapon and weapon.has_method("get_active_hotbar_index"):
		hotbar_index = weapon.get_active_hotbar_index()
	return {
		"voxel_position": [voxel_position.x, voxel_position.y, voxel_position.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"movement_state": current_state,
		"health": health,
		"stat_bases": stat_component.export_bases() if stat_component else {},
		"inventory": inventory.to_dict() if inventory else {},
		"relics": relic_manager.export_equipped() if relic_manager else [],
		"hotbar_index": hotbar_index,
	}


func apply_save_state(data: Dictionary) -> void:
	var pos: Array = data.get("voxel_position", [0.0, 1.0, 0.0])
	voxel_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	if data.has("velocity"):
		var vel: Array = data.velocity
		velocity = Vector3(float(vel[0]), float(vel[1]), float(vel[2]))
	if data.has("movement_state"):
		current_state = int(data.movement_state) as State
	health = float(data.get("health", health))
	if stat_component:
		stat_component.load_bases(data.get("stat_bases", {}))
	if inventory and data.has("inventory"):
		inventory.load_from_dict(data.inventory)
	if relic_manager and data.has("relics"):
		relic_manager.load_equipped(data.relics)
	var weapon := get_node_or_null("WeaponController")
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(int(data.get("hotbar_index", 0)))
	if _floor_probe:
		_floor_probe.feet_height_hint = voxel_position.y
	_sync_global_from_voxel()


func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	var defense := get_stat(_StatIds.DEFENSE)
	amount *= (1.0 - clampf(defense, 0.0, 0.9))
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		died.emit()


func change_state(new_state: State) -> void:
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state

	if new_state == State.JUMPING:
		velocity.y = _jump_force()
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2
