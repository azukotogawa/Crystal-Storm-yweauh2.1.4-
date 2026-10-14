class_name EntityNavigation
extends RefCounted

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _Water = preload("res://helpers/water_locomotion.gd")

## When true, entities use single-sample height (no 8-probe floor sampling).
static var use_lightweight_nav: bool = true

static var _shared_probe: _VoxelFloorProbe
static var _crystal_api: int = 0


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
	var col_x := floori(wx)
	var col_z := floori(wz)
	var at_center := absf(wx - (float(col_x) + 0.5)) < 0.002 and absf(wz - (float(col_z) + 0.5)) < 0.002
	var base: float
	if at_center:
		base = _VoxelFloorProbe.cached_column_center_walkable(world, chunk_manager, col_x, col_z)
	else:
		var entry: Dictionary = _VoxelFloorProbe.cached_ramp_entry(chunk_manager, wx, wz)
		base = _TerrainRamps.walkable_height_from_entry(world, wx, wz, entry)
	if crystal_manager == null:
		return base
	if _crystal_api == 0:
		if crystal_manager.has_method("crystal_walkable_floor"):
			_crystal_api = 1
		elif crystal_manager.has_method("get_walkable_height"):
			_crystal_api = 2
		else:
			_crystal_api = 3
	if _crystal_api == 1:
		return maxf(base, float(crystal_manager.crystal_walkable_floor(wx, wz)))
	if _crystal_api == 2:
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
	var ws = _WorldSettings.get_active()
	return Vector2i(
		floori(ws.world_to_column(world_pos.x)),
		floori(ws.world_to_column(world_pos.z))
	)


static func _column_xz_from_world(world_pos: Vector3) -> Vector2:
	var ws = _WorldSettings.get_active()
	return Vector2(ws.world_to_column(world_pos.x), ws.world_to_column(world_pos.z))


static func _world_xz_from_column(col_x: float, col_z: float) -> Vector2:
	var ws = _WorldSettings.get_active()
	return Vector2(ws.column_to_world(col_x), ws.column_to_world(col_z))


static func snap_to_ground(
	world_pos: Vector3,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager
) -> Vector3:
	var col := _column_xz_from_world(world_pos)
	var y := walkable_y(world, chunk_manager, crystal_manager, col.x, col.y, world_pos.y)
	return Vector3(world_pos.x, y, world_pos.z)


## First tied cardinal in NEIGHBOR_DIRS order. That is the cell the full scan keeps.
static func _cardinal_toward(from_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	var dx := target_cell.x - from_cell.x
	var dz := target_cell.y - from_cell.y
	var adx := absi(dx)
	var adz := absi(dz)
	if adx == 0 and adz == 0:
		return Vector2i.ZERO
	var step := Vector2i.ZERO
	if adx > adz:
		step.x = 1 if dx > 0 else -1
	elif adz > adx:
		step.y = 1 if dz > 0 else -1
	elif dx > 0:
		step.x = 1
	elif dx < 0:
		step.x = -1
	elif dz > 0:
		step.y = 1
	else:
		step.y = -1
	return step


static func _neighbor_step_ok(
	candidate: Vector2i,
	current_y: float,
	max_step_up: float,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager
) -> bool:
	if _VoxelFloorProbe.blocking_build_column(candidate.x, candidate.y):
		return false
	var cand_x := float(candidate.x) + 0.5
	var cand_z := float(candidate.y) + 0.5
	var cand_y: float
	if use_lightweight_nav:
		cand_y = walkable_y_light(world, chunk_manager, crystal_manager, cand_x, cand_z)
	else:
		var probe := _get_probe(world, chunk_manager, crystal_manager, current_y)
		cand_y = probe.sample_walkable_feet(cand_x, cand_z)
	# A pool bed can be many layers down. Swim across it, and step out only
	# when the bank is within a normal walk of the body.
	if _Water.column_has_water(world, candidate.x, candidate.y):
		var info := _Water.sample(world, candidate.x, candidate.y, current_y, cand_y)
		if bool(info.get("submerged", false)):
			var surface := float(info.get("surface_y", cand_y))
			var layer: float = _WorldSettings.get_active().layer_height()
			if current_y >= cand_y - 0.05 and current_y <= surface + layer * 0.25:
				return true
			cand_y = float(info.get("float_y", cand_y))
	return absf(cand_y - current_y) <= max_step_up + 0.05


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
		var rested := snap_to_ground(current, world, chunk_manager, crystal_manager)
		return _apply_water_y(current, rested, from_cell.x, from_cell.y, world, delta)

	var best_cell := from_cell
	var current_y := current.y
	# Cardinal neighbors only. The closest open step is unique (ties follow
	# NEIGHBOR_DIRS order). Other directions are checked only when that step is
	# walled or steeper than max_step_up, which is the same cell the full scan picks.
	var direct := _cardinal_toward(from_cell, target_cell)
	if direct != Vector2i.ZERO and _neighbor_step_ok(
		from_cell + direct, current_y, max_step_up, world, chunk_manager, crystal_manager
	):
		best_cell = from_cell + direct
	else:
		var best_score := -1
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var candidate: Vector2i = from_cell + dir
			if not _neighbor_step_ok(candidate, current_y, max_step_up, world, chunk_manager, crystal_manager):
				continue
			var sdx := candidate.x - target_cell.x
			var sdz := candidate.y - target_cell.y
			var score := sdx * sdx + sdz * sdz
			if best_score < 0 or score < best_score:
				best_score = score
				best_cell = candidate

	var goal_col_x := float(best_cell.x) + 0.5
	var goal_col_z := float(best_cell.y) + 0.5
	var goal_xz := _world_xz_from_column(goal_col_x, goal_col_z)
	var goal := Vector3(goal_xz.x, current.y, goal_xz.y)
	if use_lightweight_nav:
		goal.y = walkable_y_light(world, chunk_manager, crystal_manager, goal_col_x, goal_col_z)
	else:
		goal.y = _get_probe(world, chunk_manager, crystal_manager, current.y).sample_walkable_feet(goal_col_x, goal_col_z)
	var water := _water_at(world, best_cell.x, best_cell.y, current.y, goal.y)
	var to_goal := goal - current
	# Buoyancy owns vertical while submerged. A bed far below must not eat the step.
	if bool(water.get("submerged", false)):
		to_goal.y = 0.0
	var dist := to_goal.length()
	if dist <= 0.02:
		return _apply_water_y(current, goal, best_cell.x, best_cell.y, world, delta)
	var step := minf(move_speed * float(water.get("speed_mult", 1.0)) * delta, dist)
	var next := current + to_goal.normalized() * step
	var next_cell := column_pos(next)
	if next_cell != from_cell and _VoxelFloorProbe.blocking_build_column(next_cell.x, next_cell.y):
		var stayed := snap_to_ground(current, world, chunk_manager, crystal_manager)
		return _apply_water_y(current, stayed, from_cell.x, from_cell.y, world, delta)
	var next_col := _column_xz_from_world(next)
	if use_lightweight_nav:
		next.y = walkable_y_light(world, chunk_manager, crystal_manager, next_col.x, next_col.y)
	else:
		next.y = _get_probe(world, chunk_manager, crystal_manager, current.y).sample_walkable_feet(next_col.x, next_col.y)
	return _apply_water_y(current, next, next_cell.x, next_cell.y, world, delta)


static func flee_cell(from_cell: Vector2i, threat_cell: Vector2i, distance: int = 3) -> Vector2i:
	var dir := Vector2(from_cell - threat_cell)
	if dir.length_squared() < 0.01:
		dir = Vector2(1, 0)
	dir = dir.normalized()
	return from_cell + Vector2i(
		int(round(dir.x * float(distance))),
		int(round(dir.y * float(distance)))
	)


## Shove in world space. A step that would climb more than one layer stays put.
## WorldObject walls block the segment, not only the destination column.
## A world with sample_knock_ground(x, z) is a test stub. Live worlds use the walkable query.
static func knockback_step(
	current: Vector3,
	dir: Vector3,
	distance: float,
	world,
	chunk_manager,
	crystal
) -> Vector3:
	if distance <= 0.0:
		return current
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return current
	flat = flat.normalized()
	var dest := current + flat * distance
	if _segment_hits_blocking_wall(current, dest):
		return current
	var ground := _knock_ground_y(world, chunk_manager, crystal, dest, current.y)
	var col := _column_xz_from_world(dest)
	var water := _water_at(world, floori(col.x), floori(col.y), current.y, ground)
	# The bed of a pool is not a wall. Slide along the float line.
	if bool(water.get("submerged", false)):
		dest.y = _Water.settle_y(current.y, water, 0.05)
		return dest
	var max_up: float = _WorldSettings.get_active().max_step_up_walk()
	if absf(ground - current.y) > max_up + 0.05:
		return current
	dest.y = ground
	return dest


## Samples the segment in column space. The start cell is allowed so a body can leave a wall.
static func _segment_hits_blocking_wall(from_pos: Vector3, to_pos: Vector3) -> bool:
	var a := _column_xz_from_world(from_pos)
	var b := _column_xz_from_world(to_pos)
	var dx := b.x - a.x
	var dz := b.y - a.y
	var steps := maxi(1, int(ceil(maxf(absf(dx), absf(dz)))))
	var start := Vector2i(floori(a.x), floori(a.y))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var col := Vector2i(floori(p.x), floori(p.y))
		if col == start:
			continue
		if _VoxelFloorProbe.blocking_build_column(col.x, col.y):
			return true
	return false


static func _water_at(world, col_x: int, col_z: int, feet_y: float, ground_y: float) -> Dictionary:
	if not _Water.column_has_water(world, col_x, col_z):
		return _Water.dry(ground_y)
	return _Water.sample(world, col_x, col_z, feet_y, ground_y)


## Submerged bodies float toward the waterline and do not stay pinned to the bed.
static func _apply_water_y(
	current: Vector3,
	grounded: Vector3,
	col_x: int,
	col_z: int,
	world,
	delta: float
) -> Vector3:
	var info := _water_at(world, col_x, col_z, current.y, grounded.y)
	if not bool(info.get("submerged", false)):
		return grounded
	var out := grounded
	out.y = _Water.settle_y(current.y, info, delta)
	return out


static func _knock_ground_y(world, chunk_manager, crystal, dest: Vector3, hint: float) -> float:
	if world != null and world.has_method("sample_knock_ground"):
		return float(world.sample_knock_ground(dest.x, dest.z))
	var ws = _WorldSettings.get_active()
	return walkable_y(
		world,
		chunk_manager,
		crystal,
		ws.world_to_column(dest.x),
		ws.world_to_column(dest.z),
		hint
	)