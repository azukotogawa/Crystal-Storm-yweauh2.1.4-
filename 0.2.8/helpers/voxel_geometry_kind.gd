class_name VoxelGeometryKind
extends RefCounted

enum Kind {
	AIR = 0,
	FULL_CUBE = 1,
	HALF_CUBE = 2,
	RAMP = 3,
	DIAGONAL_RAMP = 4,
	CORNER_RAMP = 5,
}

const MESH_FULL_CUBE := &"full_cube"
const MESH_HALF_CUBE := &"half_cube"
const MESH_RAMP_E := &"ramp_e"
const MESH_RAMP_W := &"ramp_w"
const MESH_RAMP_S := &"ramp_s"
const MESH_RAMP_N := &"ramp_n"
const MESH_CORNER_ES := &"corner_es"
const MESH_CORNER_EN := &"corner_en"
const MESH_CORNER_WS := &"corner_ws"
const MESH_CORNER_WN := &"corner_wn"
const MESH_CONCAVE_PP := &"concave_pp"
const MESH_CONCAVE_PN := &"concave_pn"
const MESH_CONCAVE_NP := &"concave_np"
const MESH_CONCAVE_NN := &"concave_nn"

const MESH_GROUP_ORDER: Array[StringName] = [
	MESH_FULL_CUBE,
	MESH_HALF_CUBE,
	MESH_RAMP_E,
	MESH_RAMP_W,
	MESH_RAMP_S,
	MESH_RAMP_N,
	MESH_CORNER_ES,
	MESH_CORNER_EN,
	MESH_CORNER_WS,
	MESH_CORNER_WN,
	MESH_CONCAVE_PP,
	MESH_CONCAVE_PN,
	MESH_CONCAVE_NP,
	MESH_CONCAVE_NN,
]


static func from_ramp_entry(entry: Dictionary) -> int:
	if entry.is_empty():
		return Kind.FULL_CUBE
	if entry.get("concave", false):
		return Kind.DIAGONAL_RAMP
	if entry.get("corner", false):
		return Kind.CORNER_RAMP
	if entry.get("dir", Vector2i.ZERO) != Vector2i.ZERO:
		return Kind.RAMP
	return Kind.FULL_CUBE


static func is_solid_kind(kind: int) -> bool:
	return kind != Kind.AIR


static func replaces_full_cube(kind: int) -> bool:
	return kind in [Kind.RAMP, Kind.DIAGONAL_RAMP, Kind.CORNER_RAMP, Kind.HALF_CUBE]


static func mesh_group_for_quad(quad: Dictionary) -> StringName:
	var face_code := int(quad.get("face_code", 0))
	if face_code == 7:
		var d := Vector2i(int(quad.get("ramp_dir_x", 0)), int(quad.get("ramp_dir_z", 0)))
		if d == Vector2i(1, 0):
			return MESH_RAMP_E
		if d == Vector2i(-1, 0):
			return MESH_RAMP_W
		if d == Vector2i(0, 1):
			return MESH_RAMP_S
		if d == Vector2i(0, -1):
			return MESH_RAMP_N
		return MESH_RAMP_E
	if face_code == 8:
		var d_a := Vector2i(int(quad.get("ramp_dir_x", 0)), int(quad.get("ramp_dir_z", 0)))
		var d_b := Vector2i(int(quad.get("ramp_dir2_x", 0)), int(quad.get("ramp_dir2_z", 0)))
		var hx: int = d_a.x if d_a.x != 0 else d_b.x
		var hz: int = d_b.y if d_b.y != 0 else d_a.y
		if hx > 0 and hz > 0:
			return MESH_CORNER_ES
		if hx > 0 and hz < 0:
			return MESH_CORNER_EN
		if hx < 0 and hz > 0:
			return MESH_CORNER_WS
		return MESH_CORNER_WN
	if face_code == 9:
		return concave_mesh_group_for_quad(quad)
	if int(quad.get("geometry_kind", Kind.FULL_CUBE)) == Kind.HALF_CUBE:
		return MESH_HALF_CUBE
	return MESH_FULL_CUBE


static func concave_mesh_group_for_quad(quad: Dictionary) -> StringName:
	var leg_x: int = int(quad.get("ramp_dir_x", 1))
	var leg_z: int = int(quad.get("ramp_dir2_z", 1))
	if leg_x > 0 and leg_z > 0:
		return MESH_CONCAVE_PP
	if leg_x > 0 and leg_z < 0:
		return MESH_CONCAVE_PN
	if leg_x < 0 and leg_z > 0:
		return MESH_CONCAVE_NP
	return MESH_CONCAVE_NN


static func concave_legs_for_mesh_group(group_name: StringName) -> Vector2i:
	if group_name == MESH_CONCAVE_PN:
		return Vector2i(1, -1)
	if group_name == MESH_CONCAVE_NP:
		return Vector2i(-1, 1)
	if group_name == MESH_CONCAVE_NN:
		return Vector2i(-1, -1)
	return Vector2i(1, 1)


static func face_code_for_kind(geo_kind: int) -> int:
	match geo_kind:
		Kind.RAMP:
			return 7
		Kind.CORNER_RAMP:
			return 8
		Kind.DIAGONAL_RAMP:
			return 9
		_:
			return 0