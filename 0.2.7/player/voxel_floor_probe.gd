class_name VoxelFloorProbe
extends RefCounted

## Shared heightfield + ramp floor sampling and voxel body collision.
## Used by Player (CharacterBody3D) and EntityNavigation.

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")

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
var _walkable_height_cache: Dictionary = {}  # String key -> float
var _sample_feet_cache: Dictionary = {}

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


func _height_cache_key(wx: float, wz: float) -> String:
	# Include live terrain edit delta so dig/build invalidate the same-frame cache.
	# live_delta - snap_delta: live WorldState overlay over any chunk snapshot base.
	var ix: int = floori(wx)
	var iz: int = floori(wz)
	var live_delta: float = _TerrainEdits.get_height_delta(ix, iz)
	var snap_delta: float = 0.0
	return "%s_%s_%s_%s" % [wx, wz, feet_height_hint, live_delta - snap_delta]


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
	# Probe XZ is in column units. player_radius() is world units (voxel_scale wide).
	var r: float = _ws().player_radius() / maxf(_ws().voxel_scale, 0.001)
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
		# Ignore the old false floor (inside the rendered top voxel) and only
		# stand on a cave when the feet hint is already down in that air.
		var layer_h: float = _ws().layer_height()
		if cave_floor > 0.01 and cave_floor < surf - layer_h * 0.25 \
				and feet_height_hint <= cave_floor + layer_h * 0.75:
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
	## Continuous feet: center sample (ramps already interpolate within the cell).
	## Neighbor max only when a higher contact is within a soft step band (ledge approach).
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
	var center := walkable_height_at(wx, wz)
	var layer: float = _ws().layer_height()
	var best := center
	for offset in _probe_offsets:
		if offset == Vector2.ZERO:
			continue
		var sx := wx + offset.x
		var sz := wz + offset.y
		# A wall beside the body must not pull feet up onto that column.
		if _grazes_blocking_wall(wx, wz, sx, sz):
			continue
		var h: float = walkable_height_at(sx, sz)
		# Only pull up toward gentle higher contacts — not a hard max of all probes.
		if h > best and (h - center) <= layer * 0.65:
			best = lerpf(best, h, 0.55)
	var result: float = best
	if _height_cache_enabled:
		_sample_feet_cache[_height_cache_key(wx, wz)] = result
	if _measure:
		_m_sample_feet_us += Time.get_ticks_usec() - t0
	return result


## Highest probe contact — step-up / wall tests.
func sample_walkable_feet_max(wx: float, wz: float) -> float:
	var best := walkable_height_at(wx, wz)
	for offset in _probe_offsets:
		if offset == Vector2.ZERO:
			continue
		var sx := wx + offset.x
		var sz := wz + offset.y
		if _grazes_blocking_wall(wx, wz, sx, sz):
			continue
		best = maxf(best, walkable_height_at(sx, sz))
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
		# Horizontal extent is columns; the body radius is authored in world units.
		var pr: float = player_radius / maxf(_ws().voxel_scale, 0.001)
		var player_min := pos - Vector3(pr, 0.0, pr)
		var player_max := pos + Vector3(pr, 0.0, pr)
		for x_world in range(floori(player_min.x), floori(player_max.x) + 1):
			for z_world in range(floori(player_min.z), floori(player_max.z) + 1):
				var wx := float(x_world)
				var wz := float(z_world)
				# Ramp-aware head clearance: ignore solids at/under the walkable foot plane.
				if _solid_blocks_head(wx, wz, head_y, floor_h, layer):
					if _measure:
						_m_blocked_us += Time.get_ticks_usec() - t0
					return true

	if _measure:
		_m_blocked_us += Time.get_ticks_usec() - t0
	return false


## True when a solid at this column would hit the player's head (not floor/ramp body).
func _solid_blocks_head(wx: float, wz: float, head_y: float, floor_h: float, layer: float) -> bool:
	if world == null or not world.has_method("get_solid"):
		return false
	if _measure:
		_m_get_solid += 2
	var check_y := floori(head_y)
	var floor_y := floori(floor_h + layer * 0.05)
	# Solids at or below the foot plane are ground, not head collision.
	if check_y <= floor_y:
		return false
	if world.get_solid(wx, float(check_y), wz) or world.get_solid(wx, float(check_y + 1), wz):
		return true
	return false


## Wood/stone walls block the column. Gates and bridges do not. No string alloc on the step path.
static func blocking_build_column(wx: int, wz: int) -> bool:
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.is_empty():
		return false
	if bool(feat.get("is_passage", false)) or bool(feat.get("is_bridge", false)):
		return false
	var build_id = feat.get("build_id", "")
	return build_id == "wood_wall" or build_id == "stone_wall"


func _blocking_build_at(wx: int, wz: int) -> bool:
	return blocking_build_column(wx, wz)


## True when a probe offset only grazes a wall in a neighboring column.
func _grazes_blocking_wall(center_x: float, center_z: float, sample_x: float, sample_z: float) -> bool:
	var sx := floori(sample_x)
	var sz := floori(sample_z)
	if sx == floori(center_x) and sz == floori(center_z):
		return false
	return blocking_build_column(sx, sz)


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
	var tile_id: int = -1
	if world != null:
		if _measure:
			_m_tile_type += 1
		tile_id = world.get_tile_type(to_pos.x, to_pos.z)
	# Oceans stop the player; border mountains block traversal; deep rim is impassable.
	if _WorldBorder.blocks_player_at(to_pos.x, to_pos.z, tile_id):
		if _measure:
			_m_can_step_us += Time.get_ticks_usec() - t0
		return false
	# Wood and stone walls are WorldObjects. They do not raise the heightfield,
	# so the step test refuses entering that column. A body already inside can
	# shuffle in the cell or leave it; probe offsets that only graze a wall do not.
	var to_col_x := floori(to_pos.x)
	var to_col_z := floori(to_pos.z)
	if blocking_build_column(to_col_x, to_col_z):
		if floori(from_pos.x) != to_col_x or floori(from_pos.z) != to_col_z:
			if _measure:
				_m_can_step_us += Time.get_ticks_usec() - t0
			return false
	# Horizontal intent is independent of exact voxel height: soft-follow Y after XZ moves.
	# Step clearance uses max contact so multi-layer walls still block honestly.
	var target_feet := sample_walkable_feet_max(to_pos.x, to_pos.z)
	var rise := target_feet - from_pos.y
	var layer: float = _ws().layer_height()
	# Allow ~1 layer up and ~1.25 layers down while walking so reshaped terrain feels smooth.
	var max_drop: float = max_step if airborne else maxf(max_step, layer * 1.25)
	var max_up: float = max_step if airborne else maxf(max_step, layer * 1.05)

	if rise >= -max_drop and rise <= max_up:
		var stepped := to_pos
		# Keep proposed Y near current; soft_follow settles onto feet (not a hard snap).
		stepped.y = from_pos.y if not airborne else target_feet
		if airborne:
			stepped.y = to_pos.y
		var ok := not is_blocked_at(stepped, player_height, player_radius)
		if not ok and not airborne:
			# Retry at target feet for true step-up onto built walls.
			stepped.y = target_feet
			ok = not is_blocked_at(stepped, player_height, player_radius)
		if _measure:
			_m_can_step_us += Time.get_ticks_usec() - t0
		return ok

	# Free move into open space when the destination body isn't blocked.
	if not is_blocked_at(to_pos, player_height, player_radius):
		if airborne:
			if _measure:
				_m_can_step_us += Time.get_ticks_usec() - t0
			return true
		if rise <= max_up * 1.05:
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


## Soft ground follow for continuous walking (no hard Y snap).
func soft_follow_y(pos: Vector3, delta: float, follow_rate: float = 22.0) -> Vector3:
	var target_feet := sample_walkable_feet(pos.x, pos.z)
	var out := pos
	var dy: float = target_feet - pos.y
	var layer: float = _ws().layer_height()
	# Large steps settle faster so ledges don't feel floaty; micro deltas ease in.
	var rate: float = follow_rate
	if absf(dy) > layer * 0.4:
		rate = follow_rate * 1.75
	elif absf(dy) < layer * 0.08:
		rate = follow_rate * 0.85
	var k: float = clampf(rate * delta, 0.0, 1.0)
	out.y = lerpf(pos.y, target_feet, k)
	return out


## Rendered walkable top, ignoring a low feet hint so the surface slab is not a cave.
func rendered_top_at(wx: float, wz: float) -> float:
	var saved: float = feet_height_hint
	var surf: float = world.get_surface_height(wx, wz) if world else 0.0
	feet_height_hint = surf + _ws().layer_height()
	var top: float = sample_walkable_feet(wx, wz)
	feet_height_hint = saved
	return top


## Body intersects the rendered ground slab or a solid voxel that is not cave air.
## Samples the column under the feet only — no scene-tree search.
func body_overlaps_terrain(pos: Vector3, player_height: float) -> bool:
	if world == null:
		return false
	var layer: float = _ws().layer_height()
	var surf: float = world.get_surface_height(pos.x, pos.z)
	var top: float = rendered_top_at(pos.x, pos.z)
	if pos.y < top - 0.08 and pos.y > surf - layer * 0.35:
		return true
	if not world.has_method("get_solid"):
		return false
	var feet_s: float = pos.y + 0.15
	var mid_s: float = pos.y + player_height * 0.5
	var head_s: float = pos.y + player_height * 0.85
	if feet_s < top - 0.02 and world.get_solid(pos.x, feet_s, pos.z):
		return true
	if mid_s < top - 0.02 and world.get_solid(pos.x, mid_s, pos.z):
		return true
	if head_s < top - 0.02 and world.get_solid(pos.x, head_s, pos.z):
		return true
	return false


## Nearest free standing spot: this column's rendered top, then a one-cell ring, then straight up.
func nearest_safe_stand(pos: Vector3, player_height: float) -> Vector3:
	var layer: float = _ws().layer_height()
	var best := Vector3(pos.x, rendered_top_at(pos.x, pos.z), pos.z)
	var best_cost := INF
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
	]
	var radius: float = _ws().player_radius()
	for off in offsets:
		var x: float = pos.x + off.x
		var z: float = pos.z + off.y
		var top: float = rendered_top_at(x, z)
		var candidate := Vector3(x, top, z)
		if body_overlaps_terrain(candidate, player_height):
			continue
		if is_blocked_at(candidate, player_height, radius):
			continue
		var cost: float = absf(off.x) + absf(off.y) + absf(top - pos.y) * 0.05
		if cost < best_cost:
			best_cost = cost
			best = candidate
	if best_cost < INF:
		return best
	var lifted := Vector3(pos.x, pos.y, pos.z)
	for _step in 16:
		lifted.y += layer
		if not body_overlaps_terrain(lifted, player_height) \
				and not is_blocked_at(lifted, player_height, radius):
			return lifted
	return Vector3(pos.x, rendered_top_at(pos.x, pos.z), pos.z)


func slope_excess_at(wx: float, wz: float) -> float:
	var center := walkable_height_at(wx, wz)
	var max_delta := 0.0
	for offset in _probe_offsets:
		if offset == Vector2.ZERO:
			continue
		var sx := wx + offset.x
		var sz := wz + offset.y
		if _grazes_blocking_wall(wx, wz, sx, sz):
			continue
		max_delta = maxf(max_delta, absf(walkable_height_at(sx, sz) - center))
	return max_delta