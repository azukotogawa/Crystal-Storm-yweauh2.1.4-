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
const _Juice = preload("res://systems/juice.gd")
const _ContactShadow = preload("res://helpers/contact_shadow.gd")
const _PlayerBodyMesh = preload("res://player/player_body_mesh.gd")

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
## Horizontal acceleration / friction (units per second²) — removes binary start/stop grid feel.
@export var move_accel := 95.0
@export var move_friction := 85.0
## Soft ground follow rate while walking (higher = stickier, lower = floatier).
@export var ground_follow_rate := 24.0
@export var max_health := 100.0

signal died
## current, maximum. The HUD health bar listens. Crystal ticks and heals both emit.
signal health_changed(current: float, maximum: float)

var health := 100.0
## Burst hits set this. Crystal-field damage sets it to crystal_field before take_damage.
var damage_source_hint: StringName = &"hit"
## Seconds of invulnerability after a burst hit. Crystal pressure does not use this.
var _hit_iframes: float = 0.0
const HIT_IFRAMES := 0.6
## Horizontal shove in column units. Burst hits set it. Crystal pressure does not.
var _knock_left: float = 0.0
var _knock_dir_xz: Vector2 = Vector2.ZERO
var _damage_origin: Vector3 = Vector3.ZERO
var _has_damage_origin: bool = false
const HIT_KNOCK_COLUMNS := 1.25
const HIT_KNOCK_HEAVY_COLUMNS := 2.05
## Columns per second. A normal hit lasts about a fifth of a second.
const HIT_KNOCK_SPEED := 7.0

## Logical column coordinates for X/Z; Y is world height in layer units.
var voxel_position := Vector3(0.0, 0.0, 0.0)
## Continuous horizontal velocity in column-space XZ (smooth micro-movement).
var _move_vel_xz: Vector2 = Vector2.ZERO

var sprite_scale_modifier := Vector2.ONE
var current_skew := 0.0

enum State { IDLE, RUNNING, JUMPING, FALLING }
var current_state := State.IDLE
var landing_timer: float = 0.0
var _bob_phase: float = 0.0
var _mesh_rest_y: float = 0.0
var _feet_wet: bool = false
var _wet_ready: bool = false
var _wet_cell: Vector2i = Vector2i(999999, 999999)
var _wet_landed: bool = false
var _audio: Node
var _vfx: Node

var is_input_locked: bool = false
## True after a jump tap is consumed. is_action_just_pressed misses a press that
## lands between flushes (smoke action_press + one frame + release).
var _jump_latched: bool = false
## Compat 0–3 orbit index; writing also sets locked_yaw_degrees to that stop.
var _locked_rotation: int = 0
var locked_rotation: int:
	set(v):
		_locked_rotation = int(v)
		locked_yaw_degrees = 45.0 + float(posmod(_locked_rotation, 4)) * 90.0
	get:
		return _locked_rotation
var locked_yaw_degrees: float = 45.0

var camera: Camera3D
var world_ready := false

var _floor_probe: _VoxelFloorProbe
## Overlap test runs every few physics frames (not a per-frame tree search).
var _overlap_tick: int = 0
var _unstuck_cooldown: float = 0.0
const UNSTUCK_COOLDOWN := 0.45
const OVERLAP_CHECK_FRAMES := 4

## Physics process exclusive breakdown (CRYSTALSTORM_PLAYER_PHYSICS_MEASURE=1).
var _phys_measure: bool = false
var _phys_n: int = 0
var _phys_sum_us: int = 0
var _phys_max_us: int = 0
var _phys_phase_sum: Dictionary = {}  # name -> us sum
var _phys_phase_max: Dictionary = {}
var _phys_phase_calls: Dictionary = {}
var _phys_worst_phases: Dictionary = {}
var _phys_worst_us: int = 0
var _phys_worst_frame: int = 0
var _phys_call_can_move: int = 0
var _phys_call_snap: int = 0
var _phys_call_grounded: int = 0
var _phys_call_collide: int = 0
var _phys_call_slope: int = 0
## Slope is flat on almost every column. Recompute on cell change, at most every 4 ticks.
var _slope_mul: float = 1.0
var _slope_cell: Vector2i = Vector2i(2147483647, 0)
var _slope_age: int = 99


func set_physics_measure_enabled(enabled: bool) -> void:
	_phys_measure = enabled
	if enabled:
		reset_physics_measure()
	if _floor_probe and _floor_probe.has_method("set_measure_enabled"):
		_floor_probe.set_measure_enabled(enabled)


func reset_physics_measure() -> void:
	_phys_n = 0
	_phys_sum_us = 0
	_phys_max_us = 0
	_phys_phase_sum.clear()
	_phys_phase_max.clear()
	_phys_phase_calls.clear()
	_phys_worst_phases.clear()
	_phys_worst_us = 0
	_phys_worst_frame = 0
	_phys_call_can_move = 0
	_phys_call_snap = 0
	_phys_call_grounded = 0
	_phys_call_collide = 0
	_phys_call_slope = 0
	if _floor_probe and _floor_probe.has_method("reset_measure"):
		_floor_probe.reset_measure()


func get_physics_measure() -> Dictionary:
	var phases: Array = []
	for k in _phys_phase_sum.keys():
		var s: int = int(_phys_phase_sum[k])
		var c: int = int(_phys_phase_calls.get(k, 0))
		phases.append({
			"phase": k,
			"total_us": s,
			"total_ms": float(s) / 1000.0,
			"avg_us": float(s) / float(maxi(c, 1)),
			"max_us": int(_phys_phase_max.get(k, 0)),
			"calls": c,
			"share_of_sum": float(s) / float(maxi(_phys_sum_us, 1)),
		})
	phases.sort_custom(func(a, b): return int(a.total_us) > int(b.total_us))
	var probe: Dictionary = {}
	if _floor_probe and _floor_probe.has_method("get_measure"):
		probe = _floor_probe.get_measure()
	return {
		"frames": _phys_n,
		"total_us": _phys_sum_us,
		"total_ms": float(_phys_sum_us) / 1000.0,
		"avg_us": float(_phys_sum_us) / float(maxi(_phys_n, 1)),
		"avg_ms": float(_phys_sum_us) / float(maxi(_phys_n, 1)) / 1000.0,
		"max_us": _phys_max_us,
		"max_ms": float(_phys_max_us) / 1000.0,
		"worst_frame": _phys_worst_frame,
		"worst_phases": _phys_worst_phases.duplicate(),
		"phases": phases,
		"call_counts": {
			"can_move_to": _phys_call_can_move,
			"snap_to_ground": _phys_call_snap,
			"is_grounded": _phys_call_grounded,
			"is_colliding_at": _phys_call_collide,
			"slope_speed_multiplier": _phys_call_slope,
		},
		"floor_probe": probe,
	}


func _phys_add(phase: String, us: int) -> void:
	if not _phys_measure:
		return
	_phys_phase_sum[phase] = int(_phys_phase_sum.get(phase, 0)) + us
	_phys_phase_max[phase] = maxi(int(_phys_phase_max.get(phase, 0)), us)
	_phys_phase_calls[phase] = int(_phys_phase_calls.get(phase, 0)) + 1


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
	# Publish the spawn column before the stream wait. ChunkManager follows
	# voxel_position; leaving it at the origin loads the map centre while the
	# crystal heart (and this body) sit in a corner.
	var spawn_x := float(spawn_col.x) + 0.5
	var spawn_z := float(spawn_col.y) + 0.5
	voxel_position = Vector3(spawn_x, _ws().layer_height() * 4.0, spawn_z)
	_sync_global_from_voxel()
	_ensure_spawn_chunks_loaded(spawn_col)
	var spawn_chunk := Vector2i(
		floori(float(spawn_col.x) / float(_ChunkData.SIZE)),
		floori(float(spawn_col.y) / float(_ChunkData.SIZE))
	)
	if chunk_manager.has_method("update_stream"):
		chunk_manager.update_stream(spawn_chunk.x, spawn_chunk.y)
	for _warmup in 360:
		if chunk_manager.spawn_area_ready(spawn_chunk.x, spawn_chunk.y):
			break
		await get_tree().process_frame

	var ph := _player_height()
	var pr := _player_radius()
	_PlayerBodyMesh.apply_to(player_mesh, ph, pr)
	player_material = player_mesh.material_override as StandardMaterial3D
	_mesh_rest_y = player_mesh.position.y
	_ContactShadow.attach(self, 0.05, 1.6)

	# Hint must sit on the surface slab. A hint of one layer is below every real
	# column, and the old cave-floor query then returned a Y inside the top voxel.
	var natural := world.get_surface_height(spawn_x, spawn_z) if world else 0.0
	_floor_probe.feet_height_hint = natural + _ws().layer_height()
	var surf := _sample_walkable_feet(spawn_x, spawn_z)
	max_health = stat_component.get_stat(_StatIds.MAX_HEALTH)
	health = max_health
	_publish_health()
	voxel_position = Vector3(spawn_x, surf, spawn_z)
	var lift_guard := 0
	while is_colliding_at(voxel_position) and voxel_position.y < surf + _ws().layer_height() * 6.0 and lift_guard < 48:
		voxel_position.y += _ws().half_layer() * 0.5
		lift_guard += 1

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
	# Capsule height includes the hemispheres. Center it so the bottom rests on the feet.
	_body_collision.position.y = capsule.height * 0.5
	add_child(_body_collision)


func _physics_process(delta: float) -> void:
	if not world_ready:
		return
	var measure := _phys_measure or OS.get_environment("CRYSTALSTORM_PLAYER_PHYSICS_MEASURE") == "1"
	if measure and not _phys_measure:
		set_physics_measure_enabled(true)
		measure = true
	var t_all := Time.get_ticks_usec() if measure else 0
	var phase_local: Dictionary = {} if measure else {}
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("player_physics")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("Player::_physics_process")
	_tick_hit_iframes(delta)

	var t0 := Time.get_ticks_usec() if measure else 0
	_floor_probe.feet_height_hint = voxel_position.y

	if current_state != State.FALLING:
		sprite_scale_modifier = sprite_scale_modifier.lerp(Vector2.ONE, 10.0 * delta)
		current_skew = lerp(current_skew, 0.0, 10.0 * delta)
	if measure:
		phase_local["animation_lerp"] = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec() if measure else 0
	var input_dir := Vector2.ZERO
	if not _GameplayInput.blocks_actions():
		if Input.is_action_pressed("move_right") or Input.is_action_pressed("ui_right"):
			input_dir.x += 1
		if Input.is_action_pressed("move_left") or Input.is_action_pressed("ui_left"):
			input_dir.x -= 1
		if Input.is_action_pressed("move_back") or Input.is_action_pressed("ui_down"):
			input_dir.y += 1
		if Input.is_action_pressed("move_forward") or Input.is_action_pressed("ui_up"):
			input_dir.y -= 1
		input_dir = input_dir.normalized()
	if measure:
		phase_local["input"] = Time.get_ticks_usec() - t0

	var moving := input_dir != Vector2.ZERO
	t0 = Time.get_ticks_usec() if measure else 0
	var jump_down := false
	if not _GameplayInput.blocks_actions():
		jump_down = Input.is_action_pressed("jump")
	if jump_down \
			and not _jump_latched \
			and current_state in [State.IDLE, State.RUNNING] \
			and _can_initiate_jump(moving):
		change_state(State.JUMPING)
		_jump_latched = true
	elif not jump_down:
		_jump_latched = false
	if measure:
		phase_local["jump_check"] = Time.get_ticks_usec() - t0

	if camera and "yaw_degrees" in camera:
		locked_yaw_degrees = float(camera.yaw_degrees)
	elif camera:
		locked_yaw_degrees = 45.0 + float(camera.orbit_rotation) * 90.0
	is_input_locked = input_dir != Vector2.ZERO

	t0 = Time.get_ticks_usec() if measure else 0
	var speed := stat_component.get_stat(_StatIds.MOVE_SPEED) if stat_component else move_speed
	if inventory and inventory.has_method("armor_speed_multiplier"):
		speed *= inventory.armor_speed_multiplier()
	speed *= _slope_speed_multiplier(moving or _move_vel_xz.length_squared() > 0.0004)
	if measure:
		phase_local["slope_speed"] = Time.get_ticks_usec() - t0
		_phys_call_slope += 1

	var airborne := current_state in [State.JUMPING, State.FALLING]
	t0 = Time.get_ticks_usec() if measure else 0
	# Continuous accel/friction → micro-smooth starts/stops (no binary grid lurch).
	var desired_vel := Vector2.ZERO
	if input_dir != Vector2.ZERO:
		var move_vec := rotate_input_to_world(input_dir, locked_yaw_degrees)
		desired_vel = move_vec * speed
	if _knock_left > 0.0:
		# The hit owns this step. Walk input resumes when the shove ends.
		_tick_player_knockback(delta, airborne)
		_move_vel_xz = _move_vel_xz.move_toward(Vector2.ZERO, move_friction * delta)
		if _move_vel_xz.length_squared() < 0.0004:
			_move_vel_xz = Vector2.ZERO
	else:
		var accel: float = move_accel if desired_vel.length_squared() > 0.0001 else move_friction
		_move_vel_xz = _move_vel_xz.move_toward(desired_vel, accel * delta)
		if _move_vel_xz.length_squared() < 0.0004 and desired_vel == Vector2.ZERO:
			_move_vel_xz = Vector2.ZERO

		if _move_vel_xz.length_squared() > 0.0001:
			var move_delta := _move_vel_xz * delta
			_try_move_delta(move_delta, airborne, delta)
			if not airborne and current_state == State.IDLE:
				change_state(State.RUNNING)
		elif not airborne and current_state == State.RUNNING:
			change_state(State.IDLE)
	if measure:
		phase_local["horizontal_move"] = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec() if measure else 0
	match current_state:
		State.JUMPING:
			velocity.y -= _gravity() * delta
			if velocity.y <= 0.0:
				# Gravity ate the impulse this frame. Do not step down into the slab.
				current_state = State.FALLING
			else:
				var next_pos := voxel_position + Vector3(0.0, velocity.y * delta, 0.0)
				if is_colliding_at(next_pos):
					velocity.y = 0.0
					current_state = State.FALLING
				else:
					voxel_position.y = next_pos.y

		State.FALLING:
			velocity.y -= _gravity() * delta
			var next_pos := voxel_position + Vector3(0.0, velocity.y * delta, 0.0)
			# is_colliding allows a fraction of a layer of sink. Stop at the walkable
			# top instead, or a landing step sits inside the rendered slab.
			var feet_h := _sample_walkable_feet(voxel_position.x, voxel_position.z)
			var reached_feet := velocity.y <= 0.0 and next_pos.y <= feet_h
			if reached_feet or is_colliding_at(next_pos):
				# Land with a firm settle (not a mid-air soft float).
				voxel_position.y = feet_h if reached_feet else _sample_walkable_feet(voxel_position.x, voxel_position.z)
				velocity.y = 0.0
				_move_vel_xz *= 0.65
				sprite_scale_modifier = Vector2(1.6, 0.5)
				current_skew = -0.1
				landing_timer += delta
				if landing_timer > 0.2:
					landing_timer = 0.0
					change_state(State.RUNNING if moving or _move_vel_xz.length_squared() > 0.01 else State.IDLE)
			else:
				voxel_position.y = next_pos.y

		State.IDLE, State.RUNNING:
			_soft_follow_ground(delta)
			if not _is_grounded(moving or _move_vel_xz.length_squared() > 0.01):
				change_state(State.FALLING)
				velocity.y = 0.0
	if measure:
		phase_local["vertical_state"] = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec() if measure else 0
	_tick_unstuck(delta)
	if measure:
		phase_local["unstuck"] = Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec() if measure else 0
	_sync_global_from_voxel()
	_apply_walk_bob(delta)
	player_mesh.rotation.y = current_skew
	_tick_feet_water()
	if measure:
		phase_local["sync_visual"] = Time.get_ticks_usec() - t0

	if profiler and profiler.has_method("end_func"):
		profiler.end_func("Player::_physics_process")
	if profiler and profiler.has_method("end"):
		profiler.end("player_physics")

	if measure:
		var total := Time.get_ticks_usec() - t_all
		_phys_n += 1
		_phys_sum_us += total
		_phys_max_us = maxi(_phys_max_us, total)
		for k in phase_local.keys():
			_phys_add(str(k), int(phase_local[k]))
		if total >= _phys_worst_us:
			_phys_worst_us = total
			_phys_worst_frame = Engine.get_physics_frames()
			_phys_worst_phases = phase_local.duplicate()


func _slope_speed_multiplier(moving: bool = true) -> float:
	# Horizontal movement stays independent of voxel height — only extreme slopes dip slightly.
	# Idle never applies the multiplier, so the slope sample stays off the standing tick.
	if not moving:
		_slope_age = 99
		return 1.0
	var cell := Vector2i(floori(voxel_position.x), floori(voxel_position.z))
	if cell == _slope_cell and _slope_age < 4:
		_slope_age += 1
		return _slope_mul
	_slope_cell = cell
	_slope_age = 0
	var excess: float = _floor_probe.slope_excess_at(voxel_position.x, voxel_position.z)
	var layer: float = _ws().layer_height()
	var radius: float = _ws().player_radius()
	var slope_limit: float = tan(deg_to_rad(_ws().player_slope_limit_degrees)) * radius
	if excess <= slope_limit * 1.35:
		_slope_mul = 1.0
		return 1.0
	_slope_mul = clampf(1.0 - (excess - slope_limit) / (layer * 2.2), 0.82, 1.0)
	return _slope_mul


func rotate_input_to_world(input: Vector2, yaw_degrees: float) -> Vector2:
	var rad := deg_to_rad(yaw_degrees)
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
	if _phys_measure:
		_phys_call_collide += 1
	_floor_probe.feet_height_hint = pos.y
	return _floor_probe.is_blocked_at(pos, _player_height(), _player_radius())


func _can_move_to(proposed: Vector3, airborne: bool = false) -> bool:
	if _phys_measure:
		_phys_call_can_move += 1
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


## Full diagonal move first, then axis slide — removes grid-axis stutter without losing wall slide.
func _try_move_delta(move_delta: Vector2, airborne: bool, delta: float) -> void:
	var full := voxel_position + Vector3(move_delta.x, 0.0, move_delta.y)
	if _can_move_to(full, airborne):
		voxel_position.x = full.x
		voxel_position.z = full.z
		if not airborne:
			_soft_follow_ground(delta)
		return
	var moved := false
	var only_x := voxel_position + Vector3(move_delta.x, 0.0, 0.0)
	if absf(move_delta.x) > 0.00001 and _can_move_to(only_x, airborne):
		voxel_position.x = only_x.x
		moved = true
	var only_z := voxel_position + Vector3(0.0, 0.0, move_delta.y)
	if absf(move_delta.y) > 0.00001 and _can_move_to(only_z, airborne):
		voxel_position.z = only_z.z
		moved = true
	if moved and not airborne:
		_soft_follow_ground(delta)
	elif not moved:
		# Fully blocked: kill residual velocity into the wall so we don't jitter.
		if not _can_move_to(voxel_position + Vector3(move_delta.x, 0.0, 0.0), airborne):
			_move_vel_xz.x = 0.0
		if not _can_move_to(voxel_position + Vector3(0.0, 0.0, move_delta.y), airborne):
			_move_vel_xz.y = 0.0


func _soft_follow_ground(delta: float) -> void:
	if _phys_measure:
		_phys_call_snap += 1
	if chunk_manager == null or chunk_manager.world == null:
		return
	if _floor_probe and _floor_probe.has_method("soft_follow_y"):
		voxel_position = _floor_probe.soft_follow_y(voxel_position, delta, ground_follow_rate)
	else:
		voxel_position = _floor_probe.snap_position_y(voxel_position)


func _snap_to_ground() -> void:
	if _phys_measure:
		_phys_call_snap += 1
	if chunk_manager == null or chunk_manager.world == null:
		return
	voxel_position = _floor_probe.snap_position_y(voxel_position)


func _tick_unstuck(delta: float) -> void:
	if _unstuck_cooldown > 0.0:
		_unstuck_cooldown = maxf(_unstuck_cooldown - delta, 0.0)
	if _floor_probe == null:
		return
	var manual := false
	if not _GameplayInput.blocks_actions() and InputMap.has_action("unstuck"):
		# Pressed, not just the edge: a tap between flushes still counts, and the cooldown blocks repeats.
		manual = Input.is_action_pressed("unstuck") and _unstuck_cooldown <= 0.0
	if manual:
		_apply_safe_stand()
		_unstuck_cooldown = UNSTUCK_COOLDOWN
		return
	_overlap_tick += 1
	if _overlap_tick < OVERLAP_CHECK_FRAMES:
		return
	_overlap_tick = 0
	if _floor_probe.body_overlaps_terrain(voxel_position, _player_height()):
		_apply_safe_stand()


func _apply_safe_stand() -> void:
	var stand: Vector3 = _floor_probe.nearest_safe_stand(voxel_position, _player_height())
	voxel_position = stand
	velocity.y = 0.0
	_move_vel_xz = Vector2.ZERO
	_knock_left = 0.0
	if current_state == State.JUMPING or current_state == State.FALLING:
		current_state = State.IDLE


func _sample_walkable_feet(wx: float, wz: float) -> float:
	return _floor_probe.sample_walkable_feet(wx, wz)


func _ground_snap_distance(moving: bool) -> float:
	var snap: float = _ws().floor_snap_distance()
	if moving:
		# Match probe min/max band while stepping between columns (avoids spurious FALLING).
		snap += _ws().layer_height() * 0.45
	return snap


func _is_grounded(moving: bool = false) -> bool:
	if _phys_measure:
		_phys_call_grounded += 1
	return _floor_probe.is_grounded_at(voxel_position, _ground_snap_distance(moving))


func _can_initiate_jump(moving: bool) -> bool:
	return _is_grounded(moving)


func _give_starting_loadout() -> void:
	inventory.set_slot(0, "wooden_sword", 1)
	inventory.set_slot(1, "stone_pick", 1)
	inventory.set_slot(2, "shortbow", 1)
	inventory.set_slot(3, "wood", 16)
	inventory.set_slot(4, "stone", 16)
	inventory.set_slot(5, "herb", 4)
	# Extra kit lives in the bag. Leather is already worn. No crafting bench:
	# sling spends stone, elites drop bombs and crystal weave.
	inventory.set_slot(8, "spear", 1)
	inventory.set_slot(9, "crystal_hammer", 1)
	inventory.set_slot(10, "sling", 1)
	inventory.set_slot(11, "crystal_bomb", 3)
	inventory.set_slot(12, "stone_plate", 1)
	inventory.armor_id = "leather_armor"


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
	# Start outside assault_distance (~48) so the first minutes are pure MAZE prep:
	# dig trenches / walls while watching crystal pressure build, then walk in to ASSAULT.
	var ring_offsets: Array[Vector2i] = []
	for dist in [56, 52, 60, 48, 64, 44]:
		ring_offsets.append(Vector2i(dist, 0))
		ring_offsets.append(Vector2i(-dist, 0))
		ring_offsets.append(Vector2i(0, dist))
		ring_offsets.append(Vector2i(0, -dist))
		ring_offsets.append(Vector2i(dist, -dist / 2))
		ring_offsets.append(Vector2i(-dist, dist / 2))
		ring_offsets.append(Vector2i(dist / 2, dist))
		ring_offsets.append(Vector2i(-dist / 2, -dist))
	for offset in ring_offsets:
		var candidate: Vector2i = source + offset
		if world == null:
			return candidate
		if _CrystalTypes.is_water_tile(world.get_tile_type(float(candidate.x), float(candidate.y))):
			continue
		return candidate
	# Last resort: still outside default assault_distance.
	return source + Vector2i(56, -12)


func get_stat(stat_id: StringName) -> float:
	return stat_component.get_stat(stat_id) if stat_component else 0.0


func _publish_health() -> void:
	health_changed.emit(health, max_health)


func get_voxel_position() -> Vector3:
	return voxel_position


func _on_stat_changed(stat_id: StringName, _value: float) -> void:
	if stat_id == _StatIds.MAX_HEALTH:
		var ratio := health / maxf(max_health, 1.0)
		max_health = stat_component.get_stat(_StatIds.MAX_HEALTH)
		health = clampf(health, 0.0, max_health)
		if health <= 0.0 and ratio > 0.0:
			health = maxf(1.0, max_health * ratio)
		_publish_health()


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
	_publish_health()


## World position of the attacker. The next burst hit shoves away from it.
func set_damage_origin(origin: Vector3) -> void:
	_damage_origin = origin
	_has_damage_origin = true


func take_damage(amount: float, source: StringName = &"") -> void:
	if amount <= 0.0:
		_has_damage_origin = false
		return
	var kind := source if source != &"" else damage_source_hint
	damage_source_hint = &"hit"
	var burst := kind != &"crystal_field"
	if burst and _hit_iframes > 0.0:
		_has_damage_origin = false
		return
	if inventory and inventory.has_method("armor_damage_multiplier"):
		amount *= inventory.armor_damage_multiplier()
	var defense := get_stat(_StatIds.DEFENSE)
	amount *= (1.0 - clampf(defense, 0.0, 0.9))
	health = maxf(health - amount, 0.0)
	_publish_health()
	if burst:
		_hit_iframes = HIT_IFRAMES
		var heavy := kind == &"boss" or amount >= 16.0
		_begin_hit_knockback(heavy)
		var tree := get_tree() if is_inside_tree() else null
		_Juice.request_hit_stop(0.08 if heavy else 0.04, tree)
		_Juice.request_shake(0.5 if heavy else 0.14)
		_play_sfx("player_death" if health <= 0.0 else "player_hurt")
	else:
		_has_damage_origin = false
	if health <= 0.0:
		died.emit()


func _begin_hit_knockback(heavy: bool) -> void:
	_knock_dir_xz = _knock_away_dir()
	_knock_left = HIT_KNOCK_HEAVY_COLUMNS if heavy else HIT_KNOCK_COLUMNS
	_has_damage_origin = false


## Walk-probe step. A wall ends the shove. Ramps stay on the same ground follow.
func _tick_player_knockback(delta: float, airborne: bool) -> void:
	if _floor_probe == null or _knock_left <= 0.0:
		_knock_left = 0.0
		return
	var step := minf(_knock_left, HIT_KNOCK_SPEED * delta)
	var before := Vector2(voxel_position.x, voxel_position.z)
	_try_move_delta(_knock_dir_xz * step, airborne, delta)
	var moved := before.distance_to(Vector2(voxel_position.x, voxel_position.z))
	if moved < step * 0.2:
		_knock_left = 0.0
		return
	_knock_left = maxf(_knock_left - step, 0.0)


## Column-space XZ, away from the attacker. A missing origin shoves backward.
func _knock_away_dir() -> Vector2:
	var away := Vector2.ZERO
	if _has_damage_origin:
		var ws = _ws()
		away = Vector2(
			voxel_position.x - ws.world_to_column(_damage_origin.x),
			voxel_position.z - ws.world_to_column(_damage_origin.z)
		)
	if away.length_squared() < 0.0001:
		away = rotate_input_to_world(Vector2(0.0, 1.0), locked_yaw_degrees)
	if away.length_squared() < 0.0001:
		return Vector2(1.0, 0.0)
	return away.normalized()


func _tick_hit_iframes(delta: float) -> void:
	if _hit_iframes <= 0.0:
		if player_mesh and not player_mesh.visible:
			player_mesh.visible = true
		return
	_hit_iframes = maxf(_hit_iframes - delta, 0.0)
	if player_mesh:
		player_mesh.visible = fmod(_hit_iframes * 16.0, 2.0) >= 1.0 or _hit_iframes <= 0.0
	if _hit_iframes <= 0.0 and player_mesh:
		player_mesh.visible = true


## Restore health from existing consumables (e.g. herb). No new survival meters.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = minf(max_health, health + amount)
	_publish_health()


func change_state(new_state: State) -> void:
	if new_state == State.IDLE and current_state != State.FALLING:
		sprite_scale_modifier = Vector2.ONE
		current_skew = 0.0
	current_state = new_state

	if new_state == State.JUMPING:
		velocity.y = _jump_force()
		sprite_scale_modifier = Vector2(0.6, 1.6)
		current_skew = 0.2


func _apply_walk_bob(delta: float) -> void:
	if player_mesh == null:
		return
	if _mesh_rest_y <= 0.0:
		_mesh_rest_y = player_mesh.position.y
	var sx := 1.0
	var sy := 1.0
	var bob := 0.0
	if current_state == State.RUNNING and _Juice.walk_bob_allowed():
		_bob_phase += delta * 11.0
		var s := sin(_bob_phase)
		bob = s * _ws().voxel_scale * 0.04
		sx = 1.0 + s * 0.06
		sy = 1.0 - s * 0.08
	else:
		_bob_phase = 0.0
	player_mesh.position.y = _mesh_rest_y + bob
	player_mesh.scale = Vector3(sprite_scale_modifier.x * sx, sprite_scale_modifier.y * sy, 1.0)


func _tick_feet_water() -> void:
	if world == null or not world.has_method("get_tile_type"):
		return
	var cell := Vector2i(floori(voxel_position.x), floori(voxel_position.z))
	var landed := current_state == State.IDLE or current_state == State.RUNNING
	if _wet_ready and cell == _wet_cell and landed == _wet_landed:
		return
	_wet_cell = cell
	_wet_landed = landed
	if not landed:
		return
	var wet := _CrystalTypes.is_water_tile(int(world.get_tile_type(float(cell.x) + 0.5, float(cell.y) + 0.5)))
	if not _wet_ready:
		_feet_wet = wet
		_wet_ready = true
		return
	if wet == _feet_wet:
		return
	_feet_wet = wet
	_splash_here()


func _splash_here() -> void:
	if not is_instance_valid(_vfx):
		_vfx = get_tree().get_first_node_in_group("combat_visual_feedback") if is_inside_tree() else null
	if _vfx and _vfx.has_method("splash_at"):
		_vfx.splash_at(global_position)
	else:
		_play_sfx("water_splash", global_position)


func _play_sfx(id: String, at: Variant = null) -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/AudioManager")
	if _audio == null or not _audio.has_method("play_sfx"):
		return
	if at is Vector3:
		_audio.play_sfx(id, at)
	else:
		_audio.play_sfx(id)
