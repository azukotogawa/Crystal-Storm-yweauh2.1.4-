class_name EntityNavigation
extends RefCounted

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")

## When true, entities use single-sample height (no 8-probe floor sampling).
static var use_lightweight_nav: bool = true

static var _shared_probe: _VoxelFloorProbe


static func _get_probe(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager,
	feet_hint: float = 0.0
) -> _VoxelFloorProbe:
	if _shared_probe == null:
		_shared_probe = _VoxelFloorProbe.new()
	_shared_probe.configure(world, chunk_manager, crystal_manager)
	_shared_probe.feet_height_hint = feet_hint
	return _shared_probe


static func walkable_y_light(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager,
	wx: float,
	wz: float
) -> float:
	if world == null:
		return _WorldSettings.get_active().layer_height()
	var entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		entry = chunk_manager.get_ramp_entry_at_world(wx, wz)
	var base := _TerrainRamps.walkable_height_from_entry(world, wx, wz, entry)
	if crystal_manager and crystal_manager.has_method("get_walkable_height"):
		return maxf(base, crystal_manager.get_walkable_height(wx, wz))
	return base


static func walkable_y(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager,
	wx: float,
	wz: float,
	feet_hint: float = 0.0
) -> float:
	if use_lightweight_nav:
		return walkable_y_light(world, chunk_manager, crystal_manager, wx, wz)
	if world == null:
		return _WorldSettings.get_active().layer_height()
	var probe := _get_probe(world, chunk_manager, crystal_manager, feet_hint)
	return probe.sample_walkable_feet(wx, wz)


static func column_pos(world_pos: Vector3) -> Vector2i:
	return Vector2i(floori(world_pos.x), floori(world_pos.z))


static func snap_to_ground(
	world_pos: Vector3,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager
) -> Vector3:
	var y := walkable_y(world, chunk_manager, crystal_manager, world_pos.x, world_pos.z, world_pos.y)
	return Vector3(world_pos.x, y, world_pos.z)


static func step_toward_cell(
	current: Vector3,
	target_cell: Vector2i,
	move_speed: float,
	delta: float,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager,
	max_step_up: float = -1.0
) -> Vector3:
	if max_step_up < 0.0:
		max_step_up = _WorldSettings.get_active().max_step_up_walk()

	var from_cell := column_pos(current)
	if from_cell == target_cell:
		return snap_to_ground(current, world, chunk_manager, crystal_manager)

	var probe: _VoxelFloorProbe = null
	var best_cell := from_cell
	var best_score := INF
	var current_y := current.y

	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var candidate: Vector2i = from_cell + dir
		var cand_x := float(candidate.x) + 0.5
		var cand_z := float(candidate.y) + 0.5
		var cand_y: float
		if use_lightweight_nav:
			cand_y = walkable_y_light(world, chunk_manager, crystal_manager, cand_x, cand_z)
		else:
			if probe == null:
				probe = _get_probe(world, chunk_manager, crystal_manager, current.y)
			cand_y = probe.sample_walkable_feet(cand_x, cand_z)
		if absf(cand_y - current_y) > max_step_up + 0.05:
			continue
		var score := Vector2(candidate).distance_squared_to(Vector2(target_cell))
		if score < best_score:
			best_score = score
			best_cell = candidate

	var goal := Vector3(float(best_cell.x) + 0.5, current.y, float(best_cell.y) + 0.5)
	if use_lightweight_nav:
		goal.y = walkable_y_light(world, chunk_manager, crystal_manager, goal.x, goal.z)
	else:
		if probe == null:
			probe = _get_probe(world, chunk_manager, crystal_manager, current.y)
		goal.y = probe.sample_walkable_feet(goal.x, goal.z)
	var to_goal := goal - current
	var dist := to_goal.length()
	if dist <= 0.02:
		return goal
	var step := minf(move_speed * delta, dist)
	var next := current + to_goal.normalized() * step
	if use_lightweight_nav:
		next.y = walkable_y_light(world, chunk_manager, crystal_manager, next.x, next.z)
	else:
		if probe == null:
			probe = _get_probe(world, chunk_manager, crystal_manager, current.y)
		next.y = probe.sample_walkable_feet(next.x, next.z)
	return next


static func flee_cell(from_cell: Vector2i, threat_cell: Vector2i, distance: int = 3) -> Vector2i:
	var dir := Vector2(from_cell - threat_cell)
	if dir.length_squared() < 0.01:
		dir = Vector2(1, 0)
	dir = dir.normalized()
	return from_cell + Vector2i(
		int(round(dir.x * float(distance))),
		int(round(dir.y * float(distance)))
	)