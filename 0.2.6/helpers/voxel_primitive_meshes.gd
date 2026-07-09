class_name VoxelPrimitiveMeshes
extends RefCounted

## Exact unit-voxel primitives in local space [0,s]³.
## +X = east, +Z = south, +Y = up.
## Ramp/corner/concave meshes include slopes plus back/floor/side fills (greedy skips these cells).
## Cardinal +Z ramps are derived from the west (toward-low-west) reference via axis transforms.

const _WorldSettings = preload("res://config/world_settings.gd")

const MESH_REV := 11

static var _cache: Dictionary = {}
static var _scale_key: float = -1.0


static func invalidate_cache() -> void:
	_cache.clear()
	_scale_key = -1.0


static func _s() -> float:
	return _WorldSettings.get_active().voxel_scale


static func _ensure() -> void:
	var s: float = _s()
	if _scale_key == s and not _cache.is_empty():
		return
	_cache.clear()
	_scale_key = s
	_cache[&"cube"] = _build_cube(s)
	_cache[&"half"] = _build_half_cube(s)
	_cache[&"ramp_e"] = _build_cardinal_ramp(s, Vector2i(1, 0))
	_cache[&"ramp_w"] = _build_cardinal_ramp(s, Vector2i(-1, 0))
	_cache[&"ramp_s"] = _build_cardinal_ramp(s, Vector2i(0, 1))
	_cache[&"ramp_n"] = _build_cardinal_ramp(s, Vector2i(0, -1))
	_cache[&"corner_es"] = _build_corner_ramp(s, Vector2i(1, 0), Vector2i(0, 1))
	_cache[&"corner_en"] = _build_corner_ramp(s, Vector2i(1, 0), Vector2i(0, -1))
	_cache[&"corner_ws"] = _build_corner_ramp(s, Vector2i(-1, 0), Vector2i(0, 1))
	_cache[&"corner_wn"] = _build_corner_ramp(s, Vector2i(-1, 0), Vector2i(0, -1))
	_cache[&"concave_pp"] = _build_concave_oriented(s, 1, 1)
	_cache[&"concave_pn"] = _build_concave_oriented(s, 1, -1)
	_cache[&"concave_np"] = _build_concave_oriented(s, -1, 1)
	_cache[&"concave_nn"] = _build_concave_oriented(s, -1, -1)


static func get_cube_mesh() -> ArrayMesh:
	_ensure()
	return _cache[&"cube"]


static func get_half_cube_mesh() -> ArrayMesh:
	_ensure()
	return _cache[&"half"]


static func get_cardinal_ramp_mesh(toward_low: Vector2i) -> ArrayMesh:
	_ensure()
	if toward_low == Vector2i(1, 0):
		return _cache[&"ramp_e"]
	if toward_low == Vector2i(-1, 0):
		return _cache[&"ramp_w"]
	if toward_low == Vector2i(0, 1):
		return _cache[&"ramp_s"]
	if toward_low == Vector2i(0, -1):
		return _cache[&"ramp_n"]
	return _cache[&"ramp_e"]


static func get_corner_ramp_mesh(dir_a: Vector2i, dir_b: Vector2i) -> ArrayMesh:
	_ensure()
	var hx: int = dir_a.x if dir_a.x != 0 else dir_b.x
	var hz: int = dir_b.y if dir_b.y != 0 else dir_a.y
	if hx > 0 and hz > 0:
		return _cache[&"corner_es"]
	if hx > 0 and hz < 0:
		return _cache[&"corner_en"]
	if hx < 0 and hz > 0:
		return _cache[&"corner_ws"]
	if hx < 0 and hz < 0:
		return _cache[&"corner_wn"]
	return _cache[&"corner_es"]


static func get_concave_mesh(leg_x: int = 1, leg_z: int = 1) -> ArrayMesh:
	_ensure()
	if leg_x > 0 and leg_z > 0:
		return _cache[&"concave_pp"]
	if leg_x > 0 and leg_z < 0:
		return _cache[&"concave_pn"]
	if leg_x < 0 and leg_z > 0:
		return _cache[&"concave_np"]
	return _cache[&"concave_nn"]


static func voxel_origin(world_x: float, world_z: float, surface_y: float) -> Vector3:
	var ws = _WorldSettings.get_active()
	return Vector3(ws.column_to_world(world_x), surface_y, ws.column_to_world(world_z))


static func _build_cube(s: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s), Vector3.DOWN)
	_add_quad(st, Vector3(0, s, 0), Vector3(0, s, s), Vector3(s, s, s), Vector3(s, s, 0), Vector3.UP)
	_add_quad(st, Vector3(0, 0, 0), Vector3(0, s, 0), Vector3(0, s, s), Vector3(0, 0, s), Vector3(-1, 0, 0))
	_add_quad(st, Vector3(s, 0, s), Vector3(s, s, s), Vector3(s, s, 0), Vector3(s, 0, 0), Vector3(1, 0, 0))
	_add_quad(st, Vector3(0, 0, s), Vector3(0, s, s), Vector3(s, s, s), Vector3(s, 0, s), Vector3(0, 0, 1))
	_add_quad(st, Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(0, s, 0), Vector3(0, 0, 0), Vector3(0, 0, -1))
	return st.commit()


static func _build_half_cube(s: float) -> ArrayMesh:
	var h: float = s * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s), Vector3.DOWN)
	_add_quad(st, Vector3(0, h, 0), Vector3(0, h, s), Vector3(s, h, s), Vector3(s, h, 0), Vector3.UP)
	_add_quad(st, Vector3(0, 0, 0), Vector3(0, h, 0), Vector3(0, h, s), Vector3(0, 0, s), Vector3(-1, 0, 0))
	_add_quad(st, Vector3(s, 0, s), Vector3(s, h, s), Vector3(s, h, 0), Vector3(s, 0, 0), Vector3(1, 0, 0))
	_add_quad(st, Vector3(0, 0, s), Vector3(0, h, s), Vector3(s, h, s), Vector3(s, 0, s), Vector3(0, 0, 1))
	_add_quad(st, Vector3(s, 0, 0), Vector3(s, h, 0), Vector3(0, h, 0), Vector3(0, 0, 0), Vector3(0, 0, -1))
	return st.commit()


## Reference mesh: toward-low-west landing (high east back, side fills peak on east edge).
static func _cardinal_west_faces(s: float) -> Array:
	return [
		{
			"kind": &"quad",
			"verts": [Vector3(s, s, 0), Vector3(s, s, s), Vector3(0, 0, s), Vector3(0, 0, 0)],
			"normal": _norm(Vector3(-1, 1, 0)),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(s, s, s), Vector3(s, s, 0)],
			"normal": Vector3(1, 0, 0),
		},
		{
			"kind": &"tri",
			"verts": [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, s, 0)],
			"normal": Vector3(0, 0, -1),
		},
		{
			"kind": &"tri",
			"verts": [Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s)],
			"normal": Vector3(0, 0, 1),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s)],
			"normal": Vector3.DOWN,
		},
	]


## Reference mesh: toward-low-west + toward-low-north corner (high WN, fills on east/south).
static func _corner_wn_faces(s: float) -> Array:
	return [
		{
			"kind": &"quad",
			"verts": [Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(0, s, 0), Vector3(0, s, s)],
			"normal": _norm(Vector3(-1, 1, 0)),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(s, 0, s), Vector3(0, 0, s), Vector3(0, s, 0), Vector3(s, s, 0)],
			"normal": _norm(Vector3(0, 1, -1)),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(s, s, s), Vector3(s, s, 0)],
			"normal": Vector3(1, 0, 0),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, s, s), Vector3(0, s, s)],
			"normal": Vector3(0, 0, 1),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(s, 0, s), Vector3(0, 0, s)],
			"normal": Vector3.DOWN,
		},
	]


static func _build_cardinal_ramp(s: float, toward_low: Vector2i) -> ArrayMesh:
	var faces: Array = _cardinal_west_faces(s)
	if toward_low == Vector2i(1, 0):
		faces = _mirror_faces_x(faces, s)
	elif toward_low == Vector2i(0, -1):
		faces = _rotate_faces_y_cw(faces, s)
	elif toward_low == Vector2i(0, 1):
		faces = _rotate_faces_y_ccw(faces, s)
	return _commit_faces(faces)


static func _build_corner_ramp(s: float, dir_a: Vector2i, dir_b: Vector2i) -> ArrayMesh:
	var hx: int = dir_a.x if dir_a.x != 0 else dir_b.x
	var hz: int = dir_b.y if dir_b.y != 0 else dir_a.y
	var faces: Array = _corner_wn_faces(s)
	if hx > 0 and hz > 0:
		faces = _mirror_faces_x(_mirror_faces_z(faces, s), s)
	elif hx > 0 and hz < 0:
		faces = _mirror_faces_z(faces, s)
	elif hx < 0 and hz > 0:
		faces = _mirror_faces_x(faces, s)
	return _commit_faces(faces)


## Reference wedge NW of diagonal (leg_x=1, leg_z=1). Floor uses UP so isometric camera sees interior ground.
static func _concave_nw_faces(s: float) -> Array:
	return [
		{
			"kind": &"quad",
			"verts": [Vector3(0, 0, s), Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(0, s, s)],
			"normal": _norm(Vector3(1, 1, 0)),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0), Vector3(0, 0, 0)],
			"normal": Vector3(-1, 0, 0),
		},
		{
			"kind": &"quad",
			"verts": [Vector3(0, 0, 0), Vector3(0, s, 0), Vector3(s, s, 0), Vector3(s, 0, 0)],
			"normal": Vector3(0, 0, -1),
		},
		{
			"kind": &"tri",
			"verts": [Vector3(0, s, 0), Vector3(s, s, 0), Vector3(0, s, s)],
			"normal": Vector3.UP,
		},
		{
			"kind": &"tri",
			"verts": [Vector3(0, 0, 0), Vector3(s, 0, 0), Vector3(0, 0, s)],
			"normal": Vector3.UP,
		},
	]


static func _build_concave_oriented(s: float, leg_x: int, leg_z: int) -> ArrayMesh:
	var faces: Array = _concave_nw_faces(s)
	if leg_x < 0:
		faces = _mirror_faces_x(faces, s)
	if leg_z < 0:
		faces = _mirror_faces_z(faces, s)
	return _commit_faces(faces)


static func _mirror_vert_x(v: Vector3, s: float) -> Vector3:
	return Vector3(s - v.x, v.y, v.z)


static func _mirror_normal_x(n: Vector3) -> Vector3:
	return Vector3(-n.x, n.y, n.z)


static func _mirror_vert_z(v: Vector3, s: float) -> Vector3:
	return Vector3(v.x, v.y, s - v.z)


static func _mirror_normal_z(n: Vector3) -> Vector3:
	return Vector3(n.x, n.y, -n.z)


static func _rotate_vert_y_cw(v: Vector3, s: float) -> Vector3:
	return Vector3(s - v.z, v.y, v.x)


static func _rotate_normal_y_cw(n: Vector3) -> Vector3:
	return _norm(Vector3(-n.z, n.y, n.x))


static func _rotate_vert_y_ccw(v: Vector3, s: float) -> Vector3:
	return Vector3(v.z, v.y, s - v.x)


static func _rotate_normal_y_ccw(n: Vector3) -> Vector3:
	return _norm(Vector3(n.z, n.y, -n.x))


static func _map_face_verts(face: Dictionary, mapper: Callable) -> Array:
	var out: Array = []
	for v in face["verts"]:
		out.append(mapper.call(v))
	return out


static func _map_face_normal(face: Dictionary, mapper: Callable) -> Vector3:
	var n: Vector3 = face["normal"]
	return _norm(mapper.call(n))


static func _mirror_faces_x(faces: Array, s: float) -> Array:
	var out: Array = []
	for face in faces:
		out.append({
			"kind": face["kind"],
			"verts": _map_face_verts(face, func(v): return _mirror_vert_x(v, s)),
			"normal": _map_face_normal(face, _mirror_normal_x),
		})
	return out


static func _mirror_faces_z(faces: Array, s: float) -> Array:
	var out: Array = []
	for face in faces:
		out.append({
			"kind": face["kind"],
			"verts": _map_face_verts(face, func(v): return _mirror_vert_z(v, s)),
			"normal": _map_face_normal(face, _mirror_normal_z),
		})
	return out


static func _rotate_faces_y_cw(faces: Array, s: float) -> Array:
	var out: Array = []
	for face in faces:
		out.append({
			"kind": face["kind"],
			"verts": _map_face_verts(face, func(v): return _rotate_vert_y_cw(v, s)),
			"normal": _map_face_normal(face, _rotate_normal_y_cw),
		})
	return out


static func _rotate_faces_y_ccw(faces: Array, s: float) -> Array:
	var out: Array = []
	for face in faces:
		out.append({
			"kind": face["kind"],
			"verts": _map_face_verts(face, func(v): return _rotate_vert_y_ccw(v, s)),
			"normal": _map_face_normal(face, _rotate_normal_y_ccw),
		})
	return out


static func _orient_tri(a: Vector3, b: Vector3, c: Vector3, intended: Vector3) -> Array:
	var computed: Vector3 = (b - a).cross(c - a)
	if computed.length_squared() < 0.000001:
		return [a, b, c]
	if computed.normalized().dot(intended) < 0.0:
		return [a, c, b]
	return [a, b, c]


static func _commit_faces(faces: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var intended: Vector3 = face["normal"]
		var verts: Array = face["verts"]
		if face["kind"] == &"tri":
			var tri: Array = _orient_tri(verts[0], verts[1], verts[2], intended)
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			_add_tri(st, tri[0], tri[1], tri[2], n)
		else:
			var tri_a: Array = _orient_tri(verts[0], verts[1], verts[2], intended)
			var n_a: Vector3 = (tri_a[1] - tri_a[0]).cross(tri_a[2] - tri_a[0]).normalized()
			_add_tri(st, tri_a[0], tri_a[1], tri_a[2], n_a)
			var tri_b: Array = _orient_tri(verts[0], verts[2], verts[3], intended)
			var n_b: Vector3 = (tri_b[1] - tri_b[0]).cross(tri_b[2] - tri_b[0]).normalized()
			_add_tri(st, tri_b[0], tri_b[1], tri_b[2], n_b)
	return st.commit()


static func _norm(v: Vector3) -> Vector3:
	return v.normalized()


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(a.x, a.z))
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z))
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z))
	st.add_vertex(c)


static func _add_quad_computed(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 0.000001:
		return
	_add_quad(st, a, b, c, d, n.normalized())


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_add_tri(st, a, b, c, normal)
	_add_tri(st, a, c, d, normal)