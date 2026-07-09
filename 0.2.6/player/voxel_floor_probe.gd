class_name VoxelFloorProbe
extends RefCounted

## Shared heightfield + ramp floor sampling and voxel body collision.
## Used by Player (CharacterBody3D) and EntityNavigation.

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

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


func _column_surface_height(wx: float, wz: float) -> float:
	if chunk_manager and chunk_manager.has_method("get_chunk_data_at_world_pos"):
		var data: ChunkData = chunk_manager.get_chunk_data_at_world_pos(Vector3(wx, 0.0, wz))
		if data:
			var ix := floori(wx)
			var iz := floori(wz)
			var lx := ix - data.position.x * _ChunkData.SIZE
			var lz := iz - data.position.y * _ChunkData.SIZE
			if lx >= 0 and lx < _ChunkData.SIZE and lz >= 0 and lz < _ChunkData.SIZE:
				return data.get_surface_y(lx, lz)
	if world:
		return world.get_surface_height(wx, wz)
	return 0.0


func walkable_height_at(wx: float, wz: float) -> float:
	if world == null:
		return _ws().layer_height()
	var surf := _column_surface_height(wx, wz)
	if feet_height_hint < surf - _ws().layer_height() * 0.75 and world.has_method("get_cave_floor_height"):
		var cave_floor := world.get_cave_floor_height(wx, wz)
		if cave_floor > 0.01:
			return cave_floor
	var entry := ramp_entry_at(wx, wz)
	var base: float
	if entry.is_empty():
		base = TerrainRamps.voxel_top_y(surf)
	elif TerrainRamps.is_landing_ramp_entry(entry):
		var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
		base = TerrainRamps.surface_height_on_ramp(wx, wz, surf, dir)
	else:
		base = TerrainRamps.voxel_top_y(surf)
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
	var center_h := walkable_height_at(pos.x, pos.z)
	if absf(pos.y - center_h) <= snap_distance:
		return true
	var max_h := sample_walkable_feet(pos.x, pos.z)
	var min_h := center_h
	for offset in _probe_offsets:
		if offset == Vector2.ZERO:
			continue
		min_h = minf(min_h, walkable_height_at(pos.x + offset.x, pos.z + offset.y))
	return pos.y >= min_h - snap_distance and pos.y <= max_h + snap_distance


func is_blocked_at(
	pos: Vector3,
	player_height: float,
	player_radius: float
) -> bool:
	if world == null:
		return false

	var layer: float = _ws().layer_height()
	var center_floor := walkable_height_at(pos.x, pos.z)
	var support_floor := sample_walkable_feet(pos.x, pos.z)
	# Slopes: don't treat feet as "below floor" when center is on-surface but edge probes read higher.
	var floor_h := minf(center_floor, support_floor)

	if pos.y < floor_h - layer * 0.15:
		return true

	var surf := _column_surface_height(pos.x, pos.z)
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
		var clearance: float = layer * 0.12
		for x_world in range(floori(player_min.x), floori(player_max.x) + 1):
			for z_world in range(floori(player_min.z), floori(player_max.z) + 1):
				var wx := float(x_world)
				var wz := float(z_world)
				var col_floor := walkable_height_at(wx, wz)
				var min_block_y := col_floor + clearance
				for check_y in [floori(head_y), floori(head_y) + 1]:
					if float(check_y) < min_block_y:
						continue
					if world.get_solid(wx, float(check_y), wz):
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
	if _WorldBorder.blocks_player_movement(to_pos.x, to_pos.z):
		return false
	if world != null:
		var tile: int = world.get_tile_type(to_pos.x, to_pos.z)
		if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3]:
			if _WorldBorder.zone_info(to_pos.x, to_pos.z).zone == "border":
				return false
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