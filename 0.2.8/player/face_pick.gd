class_name FacePick
extends RefCounted

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const MAX_STEPS := 900
const EYE_HEIGHT := 1.45


static func solid(world, cell: Vector3i) -> bool:
	return cell.y >= 0 and cell.y < _TerrainEdits.surface_block_y(world, cell.x, cell.z)


static func exposed(world, cell: Vector3i, normal: Vector3i) -> bool:
	return solid(world, cell) and not solid(world, cell + normal)


static func face_code(normal: Vector3i) -> int:
	if normal.y != 0:
		return 0 if normal.y > 0 else 1
	if normal.x != 0:
		return 2 if normal.x > 0 else 3
	return 4 if normal.z > 0 else 5


static func eye(player: Node3D) -> Vector3:
	var scale: float = maxf(_WorldSettings.get_active().voxel_scale, 0.001)
	var feet := player.global_position / scale
	return Vector3(feet.x, feet.y + EYE_HEIGHT, feet.z)


static func pick(world, origin: Vector3, dir: Vector3, eye_cells: Vector3, reach: float) -> Dictionary:
	var miss := {"hit": false}
	if world == null or dir.length_squared() < 0.0000001:
		return miss
	var scale: float = maxf(_WorldSettings.get_active().voxel_scale, 0.001)
	var d := dir.normalized()
	var p := origin / scale
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	if solid(world, cell):
		return miss
	var step := Vector3i(1 if d.x >= 0.0 else -1, 1 if d.y >= 0.0 else -1, 1 if d.z >= 0.0 else -1)
	var huge := 1.0e20
	var t_delta := Vector3(
		huge if absf(d.x) < 0.0000001 else absf(1.0 / d.x),
		huge if absf(d.y) < 0.0000001 else absf(1.0 / d.y),
		huge if absf(d.z) < 0.0000001 else absf(1.0 / d.z)
	)
	var t_max := Vector3(
		huge if absf(d.x) < 0.0000001 else (float(cell.x + (1 if step.x > 0 else 0)) - p.x) / d.x,
		huge if absf(d.y) < 0.0000001 else (float(cell.y + (1 if step.y > 0 else 0)) - p.y) / d.y,
		huge if absf(d.z) < 0.0000001 else (float(cell.z + (1 if step.z > 0 else 0)) - p.z) / d.z
	)
	for _i in MAX_STEPS:
		var axis := 0
		if t_max.y < t_max.x and t_max.y <= t_max.z:
			axis = 1
		elif t_max.z < t_max.x and t_max.z < t_max.y:
			axis = 2
		var t: float = t_max[axis]
		var normal := Vector3i.ZERO
		normal[axis] = -step[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		if cell.y < 0:
			return miss
		if solid(world, cell):
			if not exposed(world, cell, normal):
				return miss
			if (p + d * t).distance_to(eye_cells) > reach:
				return miss
			return {"hit": true, "cell": cell, "normal": normal, "place": cell + normal}
	return miss
