class_name VoxelFloorProbe
extends RefCounted

## Shared heightfield + ramp floor sampling and voxel body collision.
## Used by Player (CharacterBody3D) and EntityNavigation.

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager

## Feet height hint — when below surface, cave floors may apply.
var feet_height_hint: float = 0.0

var _probe_offsets: Array[Vector2] = []

## Per-physics-frame caches: can_step_to → is_blocked_at re-samples the same
## (wx,wz) offsets; slope/snap/grounded also re-query identical columns.
## Disable with CRYSTALSTORM_PLAYER_HEIGHT_CACHE=0 for A/B measurement.
var _height_cache_enabled: bool = true
var _cache_physics_frame: int = -1
var _walkable_height_cache: Dictionary = {}  # Vector3(wx,wz,feet_hint) -> float
var _sample_feet_cache: Dictionary = {}  # Vector3 -> float

## Nested measure (owned by Player physics measure).
var _measure: bool = false
var _m_walkable_height: int = 0
var _m_walkable_height_us: int = 0
var _m_walkable_height_hits: int = 0
var _m_sample_feet: int = 0
var _m_sample_feet_us: int = 0
var _m_sample_feet_hits: int = 0
var _m_can_step: int = 0
var _m_can_step_us: int = 0
var _m_blocked: int = 0
var _m_blocked_us: int = 0
var _m_grounded: int = 0
var _m_grounded_us: int = 0
var _m_surface_height: int = 0
var _m_tile_type: int = 0
var _m_get_solid: int = 0
var _m_ramp_entry: int = 0
var _m_cave_floor: int = 0
var _m_crystal_height: int = 0


func set_measure_enabled(enabled: bool) -> void:
	_measure = enabled
	var raw := OS.get_environment("CRYSTALSTORM_PLAYER_HEIGHT_CACHE").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off":
		_height_cache_enabled = false
	elif raw == "1" or raw == "true" or raw == "on":
		_height_cache_enabled = true


func reset_measure() -> void:
	_m_walkable_height = 0
	_m_walkable_height_us = 0
	_m_walkable_height_hits = 0
	_m_sample_feet = 0
	_m_sample_feet_us = 0
	_m_sample_feet_hits = 0
	_m_can_step = 0
	_m_can_step_us = 0
	_m_blocked = 0
	_m_blocked_us = 0
	_m_grounded = 0
	_m_grounded_us = 0
	_m_surface_height = 0
	_m_tile_type = 0
	_m_get_solid = 0
	_m_ramp_entry = 0
	_m_cave_floor = 0
	_m_crystal_height = 0
	_cache_physics_frame = -1
	_walkable_height_cache.clear()
	_sample_feet_cache.clear()


func get_measure() -> Dictionary:
	var wh_n := _m_walkable_height
	var sf_n := _m_sample_feet
	return {
		"walkable_height_calls": _m_walkable_height,
		"walkable_height_us": _m_walkable_height_us,
		"walkable_height_hits": _m_walkable_height_hits,
		"walkable_height_hit_rate": float(_m_walkable_height_hits) / float(maxi(wh_n, 1)),
		"sample_feet_calls": _m_sample_feet,
		"sample_feet_us": _m_sample_feet_us,
		"sample_feet_hits": _m_sample_feet_hits,
		"sample_feet_hit_rate": float(_m_sample_feet_hits) / float(maxi(sf_n, 1)),
		"can_step_calls": _m_can_step,
		"can_step_us": _m_can_step_us,
		"blocked_calls": _m_blocked,
		"blocked_us": _m_blocked_us,
		"grounded_calls": _m_grounded,
		"grounded_us": _m_grounded_us,
		"world_get_surface_height": _m_surface_height,
		"world_get_tile_type": _m_tile_type,
		"world_get_solid": _m_get_solid,
		"ramp_entry": _m_ramp_entry,
		"cave_floor": _m_cave_floor,
		"crystal_walkable_height": _m_crystal_height,
	}


func _sync_frame_cache() -> void:
	if not _height_cache_enabled:
		return
	var f := Engine.get_physics_frames()
	if f == _cache_physics_frame:
		return
	_cache_physics_frame = f
	_walkable_height_cache.clear()
	_sample_feet_cache.clear()


func _height_cache_key(wx: float, wz: float) -> Vector3:
	# feet_height_hint affects cave-floor branch — must be part of the key.
	return Vector3(wx, wz, feet_height_hint)


func _init() -> void:
	_rebuild_probe_offsets()


func configure(
	p_world: InfiniteNoiseWorld,
	p_chunk_manager: ChunkManager,
	p_crystal_manager = null
) -> void:
	world = p_world
	chunk_manager = p_chunk_manager
	crystal_manager = p_crystal_manager
	_rebuild_probe_offsets()


func _ws():
	return _WorldSettings.get_active()


func _rebuild_probe_offsets() -> void:
	var r: float = _ws().player_floor_probe_radius
	_probe_offsets = [
		Vector2(0.0, 0.0),
		Vector2(r, 0.0),
		Vector2(-r, 0.0),
		Vector2(0.0, r),
		Vector2(0.0, -r),
		Vector2(r * 0.7, r * 0.7),
		Vector2(-r * 0.7, r * 0.7),
	]


func ramp_entry_at(wx: float, wz: float) -> Dictionary:
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		if _measure:
			_m_ramp_entry += 1
		return chunk_manager.get_ramp_entry_at_world(wx, wz)
	return {}


func walkable_height_at(wx: float, wz: float) -> float:
	var t0 := Time.get_ticks_usec() if _measure else 0
	if _measure:
		_m_walkable_height += 1
	if _height_cache_enabled:
		_sync_frame_cache()
		var key := _height_cache_key(wx, wz)
		if _walkable_height_cache.has(key):
			if _measure:
				_m_walkable_height_hits += 1
				_m_walkable_height_us += Time.get_ticks_usec() - t0
			return float(_walkable_height_cache[key])
	var h: float
	if world == null:
		h = _ws().layer_height()
		if _height_cache_enabled:
			_walkable_height_cache[_height_cache_key(wx, wz)] = h
		if _measure:
			_m_walkable_height_us += Time.get_ticks_usec() - t0
		return h
	if _measure:
		_m_surface_height += 1
	var surf := world.get_surface_height(wx, wz)
	if feet_height_hint < surf - _ws().layer_height() * 0.75 and world.has_method("get_cave_floor_height"):
		if _measure:
			_m_cave_floor += 1
		var cave_floor := world.get_cave_floor_height(wx, wz)
		if cave_floor > 0.01:
			if _height_cache_enabled:
				_walkable_height_cache[_height_cache_key(wx, wz)] = cave_floor
			if _measure:
				_m_walkable_height_us += Time.get_ticks_usec() - t0
			return cave_floor
	var entry := ramp_entry_at(wx, wz)
	var base := TerrainRamps.walkable_height_from_entry(world, wx, wz, entry)
	if crystal_manager and crystal_manager.has_method("get_walkable_height"):
		if _measure:
			_m_crystal_height += 1
		base = maxf(base, crystal_manager.get_walkable_height(wx, wz))
	if _height_cache_enabled:
		_walkable_height_cache[_height_cache_key(wx, wz)] = base
	if _measure:
		_m_walkable_height_us += Time.get_ticks_usec() - t0
	return base


func sample_walkable_feet(wx: float, wz: float) -> float:
	var t0 := Time.get_ticks_usec() if _measure else 0
	if _measure:
		_m_sample_feet += 1
	if _height_cache_enabled:
		_sync_frame_cache()
		var fkey := _height_cache_key(wx, wz)
		if _sample_feet_cache.has(fkey):
			if _measure:
				_m_sample_feet_hits += 1
				_m_sample_feet_us += Time.get_ticks_usec() - t0
			return float(_sample_feet_cache[fkey])
	var best := -INF
	for offset in _probe_offsets:
		best = maxf(best, walkable_height_at(wx + offset.x, wz + offset.y))
	if _height_cache_enabled:
		_sample_feet_cache[_height_cache_key(wx, wz)] = best
	if _measure:
		_m_sample_feet_us += Time.get_ticks_usec() - t0
	return best


func is_grounded_at(pos: Vector3, snap_distance: float = -1.0) -> bool:
	var t0 := Time.get_ticks_usec() if _measure else 0
	if _measure:
		_m_grounded += 1
	if snap_distance < 0.0:
		snap_distance = _ws().floor_snap_distance()
	var center_h := walkable_height_at(pos.x, pos.z)
	if absf(pos.y - center_h) <= snap_distance:
		if _measure:
			_m_grounded_us += Time.get_ticks_usec() - t0
		return true
	var max_h := sample_walkable_feet(pos.x, pos.z)
	var min_h := center_h
	for offset in _probe_offsets:
		if offset == Vector2.ZERO:
			continue
		min_h = minf(min_h, walkable_height_at(pos.x + offset.x, pos.z + offset.y))
	var ok := pos.y >= min_h - snap_distance and pos.y <= max_h + snap_distance
	if _measure:
		_m_grounded_us += Time.get_ticks_usec() - t0
	return ok


func is_blocked_at(
	pos: Vector3,
	player_height: float,
	player_radius: float
) -> bool:
	var t0 := Time.get_ticks_usec() if _measure else 0
	if _measure:
		_m_blocked += 1
	if world == null:
		if _measure:
			_m_blocked_us += Time.get_ticks_usec() - t0
		return false

	var floor_h := sample_walkable_feet(pos.x, pos.z)
	var layer: float = _ws().layer_height()

	if pos.y < floor_h - layer * 0.15:
		if _measure:
			_m_blocked_us += Time.get_ticks_usec() - t0
		return true

	if _measure:
		_m_surface_height += 1
	var surf := world.get_surface_height(pos.x, pos.z)
	if pos.y < surf - layer * 0.75:
		if world.has_method("get_cave_floor_height"):
			if _measure:
				_m_cave_floor += 1
			var cave_floor := world.get_cave_floor_height(pos.x, pos.z)
			if cave_floor > 0.01 and pos.y < cave_floor - layer * 0.05:
				if _measure:
					_m_blocked_us += Time.get_ticks_usec() - t0
				return true

	if world.has_method("get_solid"):
		var head_y := pos.y + player_height
		var pr := player_radius
		var player_min := pos - Vector3(pr, 0.0, pr)
		var player_max := pos + Vector3(pr, 0.0, pr)
		for x_world in range(floori(player_min.x), floori(player_max.x) + 1):
			for z_world in range(floori(player_min.z), floori(player_max.z) + 1):
				var wx := float(x_world)
				var wz := float(z_world)
				var check_y := floori(head_y)
				if _measure:
					_m_get_solid += 2
				if world.get_solid(wx, float(check_y), wz) or world.get_solid(wx, float(check_y + 1), wz):
					if _measure:
						_m_blocked_us += Time.get_ticks_usec() - t0
					return true

	if _measure:
		_m_blocked_us += Time.get_ticks_usec() - t0
	return false


func can_step_to(
	from_pos: Vector3,
	to_pos: Vector3,
	player_height: float,
	player_radius: float,
	max_step: float,
	airborne: bool = false
) -> bool:
	var t0 := Time.get_ticks_usec() if _measure else 0
	if _measure:
		_m_can_step += 1
	if _WorldBorder.blocks_player_movement(to_pos.x, to_pos.z):
		if _measure:
			_m_can_step_us += Time.get_ticks_usec() - t0
		return false
	if world != null:
		if _measure:
			_m_tile_type += 1
		var tile: int = world.get_tile_type(to_pos.x, to_pos.z)
		if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3]:
			if _WorldBorder.zone_info(to_pos.x, to_pos.z).zone == "border":
				if _measure:
					_m_can_step_us += Time.get_ticks_usec() - t0
				return false
	var target_feet := sample_walkable_feet(to_pos.x, to_pos.z)
	var rise := target_feet - from_pos.y
	var snap_dist: float = _ws().floor_snap_distance()

	if rise > -snap_dist and rise <= max_step:
		var stepped := to_pos
		stepped.y = target_feet
		var ok := not is_blocked_at(stepped, player_height, player_radius)
		if _measure:
			_m_can_step_us += Time.get_ticks_usec() - t0
		return ok

	if not is_blocked_at(to_pos, player_height, player_radius):
		if airborne or rise <= max_step * 2.0:
			if _measure:
				_m_can_step_us += Time.get_ticks_usec() - t0
			return true
	if _measure:
		_m_can_step_us += Time.get_ticks_usec() - t0
	return false


func snap_position_y(pos: Vector3, max_snap: float = -1.0) -> Vector3:
	if max_snap < 0.0:
		max_snap = _ws().max_step_up_jump()
	var target_feet := sample_walkable_feet(pos.x, pos.z)
	var out := pos
	if absf(target_feet - pos.y) <= max_snap:
		out.y = target_feet
	return out


func slope_excess_at(wx: float, wz: float) -> float:
	var center := walkable_height_at(wx, wz)
	var max_delta := 0.0
	for offset in _probe_offsets:
		if offset == Vector2.ZERO:
			continue
		max_delta = maxf(max_delta, absf(walkable_height_at(wx + offset.x, wz + offset.y) - center))
	return max_delta