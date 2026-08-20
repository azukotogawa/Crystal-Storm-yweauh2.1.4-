class_name CrystalClusterMesh
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")

const LOD_FAR := 0
const LOD_MID := 1
const LOD_NEAR := 2
const LOD_FULL := 3

const MESH_REV := 3
const TRANSFORM_BYTES_PER_INSTANCE := 64
const VERTEX_BYTES_PER_TRIANGLE := 96
const DRAW_CALL_OVERHEAD_BYTES := 256

const _PYRAMID_SPECS: Array = [
	{"base": Vector3(0.52, 0.08, 0.48), "half": 0.92, "height": 0.88, "hint": Vector3(0.15, 1.0, 0.1)},
	{"base": Vector3(0.22, 0.05, 0.68), "half": 0.55, "height": 0.52, "hint": Vector3(-0.35, 0.9, 0.25)},
	{"base": Vector3(0.74, 0.04, 0.26), "half": 0.48, "height": 0.46, "hint": Vector3(0.4, 0.85, -0.3)},
	{"base": Vector3(0.38, 0.06, 0.22), "half": 0.42, "height": 0.38, "hint": Vector3(-0.2, 0.75, -0.55)},
	{"base": Vector3(0.66, 0.05, 0.72), "half": 0.4, "height": 0.34, "hint": Vector3(0.55, 0.7, 0.45)},
]

static var _meshes: Dictionary = {}
static var _mesh_rev: int = -1
static var _tri_counts: Dictionary = {}


static func use_legacy_renderer() -> bool:
	return OS.get_environment("CRYSTALSTORM_CRYSTAL_RENDERER").strip_edges().to_lower() == "legacy"


static func natural_height() -> float:
	return _WorldSettings.get_active().voxel_scale * 0.88


static func pyramid_count_for_lod(lod_tier: int) -> int:
	match clampi(lod_tier, LOD_FAR, LOD_FULL):
		LOD_FAR:
			return 1
		LOD_MID, LOD_NEAR:
			return 2
		_:
			return _PYRAMID_SPECS.size()


static func lod_tier_for_chunk_distance(chunk_dist: int) -> int:
	if chunk_dist >= 2:
		return LOD_FAR
	if chunk_dist >= 1:
		return LOD_MID
	return LOD_NEAR


static func get_mesh_for_lod(lod_tier: int) -> ArrayMesh:
	var tier := clampi(lod_tier, LOD_FAR, LOD_FULL)
	_ensure_meshes()
	return _meshes.get(tier, _meshes[LOD_FULL]) as ArrayMesh


static func get_mesh() -> ArrayMesh:
	return get_mesh_for_lod(LOD_FULL)


static func triangle_count_for_lod(lod_tier: int) -> int:
	var tier := clampi(lod_tier, LOD_FAR, LOD_FULL)
	_ensure_meshes()
	return int(_tri_counts.get(tier, 30))


static func triangle_count_for_instance(lod_tier: int) -> int:
	return triangle_count_for_lod(lod_tier)


static func estimate_gpu_buffer_bytes(instances: int, triangles: int, draw_nodes: int) -> int:
	return (
		instances * TRANSFORM_BYTES_PER_INSTANCE
		+ triangles * VERTEX_BYTES_PER_TRIANGLE
		+ draw_nodes * DRAW_CALL_OVERHEAD_BYTES
	)


static func growth_rotation_y(neighbor_mask: int) -> float:
	if neighbor_mask == 0:
		return 0.0
	var dx := 0.0
	var dz := 0.0
	if neighbor_mask & 1 != 0:
		dz -= 1.0
	if neighbor_mask & 2 != 0:
		dx += 1.0
	if neighbor_mask & 4 != 0:
		dz += 1.0
	if neighbor_mask & 8 != 0:
		dx -= 1.0
	return atan2(dx, dz)


static func neighbor_mask_from_depths(
	pos: Vector2i,
	depth_map: Dictionary,
	min_depth: float
) -> int:
	var mask := 0
	if _depth_at(depth_map, pos + Vector2i(0, -1)) >= min_depth:
		mask |= 1
	if _depth_at(depth_map, pos + Vector2i(1, 0)) >= min_depth:
		mask |= 2
	if _depth_at(depth_map, pos + Vector2i(0, 1)) >= min_depth:
		mask |= 4
	if _depth_at(depth_map, pos + Vector2i(-1, 0)) >= min_depth:
		mask |= 8
	return mask


static func _depth_at(depth_map: Dictionary, pos: Vector2i) -> float:
	if not depth_map.has(pos):
		return 0.0
	return float(depth_map[pos])


static func _ensure_meshes() -> void:
	var s: float = _WorldSettings.get_active().voxel_scale
	if not _meshes.is_empty() and _mesh_rev == MESH_REV:
		return
	_meshes.clear()
	_tri_counts.clear()
	_mesh_rev = MESH_REV
	for tier in [LOD_FAR, LOD_MID, LOD_NEAR, LOD_FULL]:
		var count := pyramid_count_for_lod(tier)
		var built := _build_mesh(s, count)
		_meshes[tier] = built
		_tri_counts[tier] = count * 6


static func _build_mesh(s: float, pyramid_count: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u := s * 0.5
	for i in pyramid_count:
		var spec: Dictionary = _PYRAMID_SPECS[i]
		_add_pyramid(
			st,
			Vector3(s * spec.base.x, s * spec.base.y, s * spec.base.z),
			u * float(spec.half),
			s * float(spec.height),
			spec.hint
		)
	return st.commit()


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