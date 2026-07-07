class_name VoxelFloorProbe
extends RefCounted

## Shared heightfield + ramp floor sampling and voxel body collision.
## Used by Player (CharacterBody3D) and EntityNavigation.

const _WorldSettings = preload("res://config/world_settings.gd")

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager

## Feet height hint — when below surface, cave floors may apply.
var feet_height_hint: float = 0.0

var _probe_offsets: Array[Vector2] = []


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
		return chunk_manager.get_ramp_entry_at_world(wx, wz)
	return {}


func walkable_height_at(wx: float, wz: float) -> float:
	if world == null:
		return _ws().layer_height()
	var surf := world.get_surface_height(wx, wz)
	if feet_height_hint < surf - _ws().layer_height() * 0.75 and world.has_method("get_cave_floor_height"):
		var cave_floor := world.get_cave_floor_height(wx, wz)
		if cave_floor > 0.01:
			return cave_floor
	var entry := ramp_entry_at(wx, wz)
	var base := TerrainRamps.walkable_height_from_entry(world, wx, wz, entry)
	if crystal_manager and crystal_manager.has_method("get_walkable_height"):
		return maxf(base, crystal_manager.get_walkable_height(wx, wz))
	return base


func sample_walkable_feet(wx: float, wz: float) -> float:
	var best := -INF
	for offset in _probe_offsets:
		best = maxf(best, walkable_height_at(wx + offset.x, wz + offset.y))
	return best


func is_grounded_at(pos: Vector3, snap_distance: float = -1.0) -> bool:
	if snap_distance < 0.0:
		snap_distance = _ws().floor_snap_distance()
	var floor_h := sample_walkable_feet(pos.x, pos.z)
	return absf(pos.y - floor_h) <= snap_distance


func is_blocked_at(
	pos: Vector3,
	player_height: float,
	player_radius: float
) -> bool:
	if world == null:
		return false

	var floor_h := sample_walkable_feet(pos.x, pos.z)
	var layer: float = _ws().layer_height()

	if pos.y < floor_h - layer * 0.15:
		return true

	var surf := world.get_surface_height(pos.x, pos.z)
	if pos.y < surf - layer * 0.75:
		if world.has_method("get_cave_floor_height"):
			var cave_floor := world.get_cave_floor_height(pos.x, pos.z)
			if cave_floor > 0.01 and pos.y < cave_floor - layer * 0.05:
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
				if world.get_solid(wx, float(check_y), wz) or world.get_solid(wx, float(check_y + 1), wz):
					return true

	return false


func can_step_to(
	from_pos: Vector3,
	to_pos: Vector3,
	player_height: float,
	player_radius: float,
	max_step: float,
	airborne: bool = false
) -> bool:
	var target_feet := sample_walkable_feet(to_pos.x, to_pos.z)
	var rise := target_feet - from_pos.y
	var snap_dist: float = _ws().floor_snap_distance()

	if rise > -snap_dist and rise <= max_step:
		var stepped := to_pos
		stepped.y = target_feet
		return not is_blocked_at(stepped, player_height, player_radius)

	if not is_blocked_at(to_pos, player_height, player_radius):
		if airborne or rise <= max_step * 2.0:
			return true
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