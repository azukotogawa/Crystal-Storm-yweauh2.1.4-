class_name CrystalClusterMesh
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")

static var _mesh: ArrayMesh
static var _mesh_rev: int = -1
const MESH_REV := 1


static func get_mesh() -> ArrayMesh:
	var s: float = _WorldSettings.get_active().voxel_scale
	if _mesh != null and _mesh_rev == MESH_REV:
		return _mesh
	_mesh_rev = MESH_REV
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := s * 0.5
	_add_pyramid(st, Vector3(s * 0.52, s * 0.08, s * 0.48), u * 0.92, s * 0.88, Vector3(0.15, 1.0, 0.1))
	_add_pyramid(st, Vector3(s * 0.22, s * 0.05, s * 0.68), u * 0.55, s * 0.52, Vector3(-0.35, 0.9, 0.25))
	_add_pyramid(st, Vector3(s * 0.74, s * 0.04, s * 0.26), u * 0.48, s * 0.46, Vector3(0.4, 0.85, -0.3))
	_add_pyramid(st, Vector3(s * 0.38, s * 0.06, s * 0.22), u * 0.42, s * 0.38, Vector3(-0.2, 0.75, -0.55))
	_add_pyramid(st, Vector3(s * 0.66, s * 0.05, s * 0.72), u * 0.4, s * 0.34, Vector3(0.55, 0.7, 0.45))
	_mesh = st.commit()
	return _mesh


static func _add_pyramid(
	st: SurfaceTool,
	base_center: Vector3,
	half: float,
	height: float,
	normal_hint: Vector3
) -> void:
	var bx0 := base_center.x - half
	var bx1 := base_center.x + half
	var bz0 := base_center.z - half
	var bz1 := base_center.z + half
	var by := base_center.y
	var apex := base_center + Vector3(0.0, height, 0.0)
	var a := Vector3(bx0, by, bz0)
	var b := Vector3(bx1, by, bz0)
	var c := Vector3(bx1, by, bz1)
	var d := Vector3(bx0, by, bz1)
	_add_tri(st, a, b, c, Vector3.DOWN, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_add_tri(st, a, c, d, Vector3.DOWN, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
	var n_ab := normal_hint.cross(b - a).normalized()
	var n_bc := normal_hint.cross(c - b).normalized()
	var n_cd := normal_hint.cross(d - c).normalized()
	var n_da := normal_hint.cross(a - d).normalized()
	_add_tri(st, a, b, apex, n_ab, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))
	_add_tri(st, b, c, apex, n_bc, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))
	_add_tri(st, c, d, apex, n_cd, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))
	_add_tri(st, d, a, apex, n_da, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))


static func _add_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2
) -> void:
	st.set_normal(normal)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)