class_name WorldVisualCoords
extends RefCounted
## Single column ↔ Godot-world contract.
##
## Gameplay / overlays / targeting use integer columns (wx, wz).
## Y is already in world units (layer_height == voxel_scale).
## Node3D XZ is column * voxel_scale. Never treat global_position.x as a column
## and never treat voxel_position.x as a world-space metre.

const _WorldSettings = preload("res://config/world_settings.gd")

## Must match ChunkView.gdshader face_code and ChunkManager FACE_* constants.
const FACE_TOP := 0
const FACE_BOTTOM := 2
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9


static func settings():
	return _WorldSettings.get_active()


static func voxel_scale() -> float:
	return settings().voxel_scale


static func layer_height() -> float:
	return settings().layer_height()


static func column_to_world_pos(column_x: float, world_y: float, column_z: float) -> Vector3:
	var ws = settings()
	return Vector3(
		ws.column_to_world(column_x),
		world_y,
		ws.column_to_world(column_z)
	)


static func cell_center(column_x: int, world_y: float, column_z: int) -> Vector3:
	return column_to_world_pos(float(column_x) + 0.5, world_y, float(column_z) + 0.5)


static func world_to_column_xz(world_x: float, world_z: float) -> Vector2:
	var ws = settings()
	return Vector2(ws.world_to_column(world_x), ws.world_to_column(world_z))


static func column_from_node(node: Node3D) -> Vector2:
	if node == null:
		return Vector2.ZERO
	if node.has_method("get_voxel_position"):
		var v: Vector3 = node.get_voxel_position()
		return Vector2(v.x, v.z)
	var xz := world_to_column_xz(node.global_position.x, node.global_position.z)
	return xz


## Gameplay / walk / debug AABB for one column. Size XZ is one voxel, not 1.0 world unit.
static func cell_aabb(wx: int, y0: float, wz: int, y1: float) -> AABB:
	var vs: float = voxel_scale()
	var top: float = maxf(y1, y0 + layer_height() * 0.05)
	var origin := column_to_world_pos(float(wx), y0, float(wz))
	return AABB(origin, Vector3(vs, maxf(top - y0, layer_height() * 0.05), vs))


static func chunk_aabb(cx: int, cz: int, y0: float = 0.0, y1: float = 24.0) -> AABB:
	var ws = settings()
	var size: float = ws.chunk_world_size()
	return AABB(
		Vector3(ws.column_to_world(float(cx * ws.chunk_size_voxels)), y0, ws.column_to_world(float(cz * ws.chunk_size_voxels))),
		Vector3(size, maxf(y1 - y0, 1.0), size)
	)


static func face_code_is_horizontal_slab(face_code: int) -> bool:
	return face_code == FACE_TOP or face_code == FACE_BOTTOM


static func face_code_is_side(face_code: int) -> bool:
	return face_code >= FACE_NEG_X and face_code <= FACE_POS_Z
