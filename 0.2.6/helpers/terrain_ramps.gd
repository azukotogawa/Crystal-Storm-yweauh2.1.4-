class_name TerrainRamps
extends RefCounted

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const PLACEMENT_CHANCE := 28
static var placement_chance: int = PLACEMENT_CHANCE

const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

static var _wedge_mesh: ArrayMesh
static var _concave_mesh: ArrayMesh
static var _mesh_scale_key: float = -1.0
const CONCAVE_MESH_REV := 2
const WEDGE_MESH_REV := 3
static var _concave_mesh_rev: int = -1
static var _wedge_mesh_rev: int = -1


static func invalidate_mesh_cache() -> void:
	_wedge_mesh = null
	_concave_mesh = null
	_mesh_scale_key = -1.0
	_concave_mesh_rev = -1
	_wedge_mesh_rev = -1


static func _ws():
	return _WorldSettings.get_active()


static func step_min() -> float:
	return _ws().step_height_min()


static func step_max() -> float:
	return _ws().step_height_max()


static func should_place_ramp(world_x: int, world_z: int, dir: Vector2i) -> bool:
	if _WorldBorder.should_force_ramp(world_x, world_z):
		return true
	var seed_val := world_x * 73856093 ^ world_z * 19349663 ^ dir.x * 83492791 ^ dir.y * 50331653
	var bucket: int = int(seed_val & 0x7fffffff) % 100
	return bucket < placement_chance


static func should_place_concave_prism(world_x: int, world_z: int, leg_x: int, leg_z: int) -> bool:
	var seed_val := world_x * 92837111 ^ world_z * 1234567 ^ leg_x * 44556677 ^ leg_z * 99112233
	return int(seed_val & 0x7fffffff) % 100 < maxi(placement_chance / 2, 12)


static func is_step_height(diff: float) -> bool:
	return diff >= step_min() and diff <= step_max()


static func candidate_dirs(_wx: float, _wz: float) -> Array:
	return DIRS.duplicate()


static func _ensure_mesh_scale() -> void:
	var s: float = _ws().voxel_scale
	if (
		_mesh_scale_key == s
		and _wedge_mesh != null
		and _wedge_mesh_rev == WEDGE_MESH_REV
		and _concave_mesh_rev == CONCAVE_MESH_REV
	):
		return
	_mesh_scale_key = s
	_wedge_mesh = null
	_concave_mesh = null
	_wedge_mesh_rev = WEDGE_MESH_REV
	_concave_mesh_rev = CONCAVE_MESH_REV


## Step wedge: half-block diagonal cut, cell-centered.
## Local y is in layer units from surface_y: 0 = column base, 1 = low walkable, 2 = high walkable toward +X.
static func get_wedge_mesh() -> ArrayMesh:
	_ensure_mesh_scale()
	if _wedge_mesh != null:
		return _wedge_mesh
	var s: float = _ws().voxel_scale
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad_uv(st,
		Vector3(-0.5, 1, -0.5) * s, Vector3(0.5, 2, -0.5) * s, Vector3(0.5, 2, 0.5) * s, Vector3(-0.5, 1, 0.5) * s,
		Vector3(0, 0.70710678, 0.70710678),
		Vector2(0, 0), Vector2(1, 1), Vector2(1, 1), Vector2(0, 0)
	)
	_add_quad_uv(st,
		Vector3(0.5, 0, -0.5) * s, Vector3(0.5, 2, -0.5) * s, Vector3(0.5, 2, 0.5) * s, Vector3(0.5, 0, 0.5) * s,
		Vector3.RIGHT,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
	)
	_add_quad_uv(st,
		Vector3(-0.5, 0, -0.5) * s, Vector3(-0.5, 1, -0.5) * s, Vector3(-0.5, 1, 0.5) * s, Vector3(-0.5, 0, 0.5) * s,
		Vector3.LEFT,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
	)
	_add_quad_uv(st,
		Vector3(-0.5, 0, -0.5) * s, Vector3(0.5, 0, -0.5) * s, Vector3(0.5, 0, 0.5) * s, Vector3(-0.5, 0, 0.5) * s,
		Vector3.DOWN,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	)
	_add_quad_uv(st,
		Vector3(-0.5, 0, -0.5) * s, Vector3(-0.5, 1, -0.5) * s, Vector3(0.5, 2, -0.5) * s, Vector3(0.5, 0, -0.5) * s,
		Vector3(0, 0, -1),
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
	)
	_add_quad_uv(st,
		Vector3(-0.5, 0, 0.5) * s, Vector3(-0.5, 1, 0.5) * s, Vector3(0.5, 2, 0.5) * s, Vector3(0.5, 0, 0.5) * s,
		Vector3(0, 0, 1),
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
	)
	_wedge_mesh = st.commit()
	return _wedge_mesh


## Concave L-corner filler: right angle at origin, legs along +X/+Z into the gap.
## Two leg faces flush against the exposed sides of the L's voxels; hypotenuse faces the void.
static func get_concave_corner_prism_mesh() -> ArrayMesh:
	_ensure_mesh_scale()
	if _concave_mesh != null:
		return _concave_mesh
	var s: float = _ws().voxel_scale
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c0 := Vector3.ZERO
	var a0 := Vector3(0.0, 0.0, s)
	var b0 := Vector3(s, 0.0, 0.0)
	var c1 := Vector3(0.0, s, 0.0)
	var a1 := Vector3(0.0, s, s)
	var b1 := Vector3(s, s, 0.0)
	_add_tri_uv(st, c0, b0, a0, Vector3.DOWN, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1))
	# Winding must face +Y so the walkable top renders (was inverted).
	_add_tri_uv(st, c1, b1, a1, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1))
	_add_quad_uv(st, a0, c0, c1, a1, Vector3(-1, 0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_add_quad_uv(st, b0, c0, c1, b1, Vector3(0, 0, -1), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_add_quad_uv(st, b0, a0, a1, b1, Vector3(0.70710678, 0.0, 0.70710678), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	_concave_mesh = st.commit()
	return _concave_mesh


static func _add_tri_uv(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2
) -> void:
	st.set_normal(normal)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)


static func _add_quad_uv(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2
) -> void:
	_add_tri_uv(st, a, b, c, normal, uv_a, uv_b, uv_c)
	_add_tri_uv(st, a, c, d, normal, uv_a, uv_c, uv_d)


static func ramp_direction_at(world: InfiniteNoiseWorld, wx: int, wz: int) -> Vector2i:
	if world == null:
		return Vector2i.ZERO
	var self_h: float = world.get_surface_height(float(wx), float(wz))
	for dir in candidate_dirs(float(wx), float(wz)):
		var d: Vector2i = dir
		var nh: float = world.get_surface_height(float(wx + d.x), float(wz + d.y))
		if is_step_height(nh - self_h) and should_place_ramp(wx, wz, d):
			return d
	return Vector2i.ZERO


static func axis_t(wx: float, wz: float, dir: Vector2i) -> float:
	var frac_x: float = wx - floorf(wx)
	var frac_z: float = wz - floorf(wz)
	if dir.x > 0:
		return frac_x
	if dir.x < 0:
		return 1.0 - frac_x
	if dir.y > 0:
		return frac_z
	if dir.y < 0:
		return 1.0 - frac_z
	return 0.0


static func voxel_top_y(surface_y: float) -> float:
	return surface_y + _ws().layer_height()


static func surface_height_on_ramp(wx: float, wz: float, base_h: float, dir: Vector2i) -> float:
	var layer: float = _ws().layer_height()
	return voxel_top_y(base_h) + clampf(axis_t(wx, wz, dir), 0.0, 1.0) * layer


static func walkable_height_from_entry(
	world: InfiniteNoiseWorld, wx: float, wz: float, entry: Dictionary
) -> float:
	if world == null:
		return _ws().layer_height()
	var tile_x: int = floori(wx)
	var tile_z: int = floori(wz)
	var base: float = world.get_surface_height(float(tile_x), float(tile_z))
	if entry.is_empty():
		return voxel_top_y(base)
	if entry.get("concave", false):
		var ref_h: float = float(entry.get("surface_h", base))
		return voxel_top_y(ref_h)
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	var dir2: Vector2i = entry.get("dir2", Vector2i.ZERO)
	if entry.get("corner", false) and dir != Vector2i.ZERO and dir2 != Vector2i.ZERO:
		var layer: float = _ws().layer_height()
		var t: float = maxf(axis_t(wx, wz, dir), axis_t(wx, wz, dir2))
		return voxel_top_y(base) + t * layer
	if dir != Vector2i.ZERO and dir2 == Vector2i.ZERO:
		return surface_height_on_ramp(wx, wz, base, dir)
	if entry.get("side", false) and dir != Vector2i.ZERO:
		return surface_height_on_ramp(wx, wz, base, entry.get("dir2", dir))
	return voxel_top_y(base)


static func walkable_height(
	world: InfiniteNoiseWorld, wx: float, wz: float, known_dir: Vector2i = Vector2i.ZERO
) -> float:
	if world == null:
		return _ws().layer_height()
	if known_dir != Vector2i.ZERO:
		return walkable_height_from_entry(world, wx, wz, {"dir": known_dir})
	var tile_x: int = floori(wx)
	var tile_z: int = floori(wz)
	var dir: Vector2i = ramp_direction_at(world, tile_x, tile_z)
	if dir != Vector2i.ZERO:
		return surface_height_on_ramp(wx, wz, world.get_surface_height(float(tile_x), float(tile_z)), dir)
	return voxel_top_y(world.get_surface_height(float(tile_x), float(tile_z)))


static func _ramp_origin(world_x: float, world_z: float, surface_y: float) -> Vector3:
	var ws = _ws()
	return Vector3(
		ws.column_to_world(world_x + 0.5),
		surface_y,
		ws.column_to_world(world_z + 0.5)
	)


static func wedge_transform(world_x: float, world_z: float, surface_y: float, dir: Vector2i) -> Transform3D:
	var yaw: float = 0.0
	if dir == Vector2i(1, 0):
		yaw = 0.0
	elif dir == Vector2i(-1, 0):
		yaw = PI
	elif dir == Vector2i(0, 1):
		yaw = -PI * 0.5
	elif dir == Vector2i(0, -1):
		yaw = PI * 0.5
	else:
		return Transform3D.IDENTITY.translated(_ramp_origin(world_x, world_z, surface_y))
	var layer: float = _ws().layer_height()
	var origin := _ramp_origin(world_x, world_z, surface_y)
	# Nudge wedge into the step face so it meets the high voxel interior, not just the outer lip.
	origin.x += float(dir.x) * layer * 0.2
	origin.z += float(dir.y) * layer * 0.2
	return Transform3D(Basis(Vector3.UP, yaw), origin)


static func concave_corner_prism_transform(
	world_x: float, world_z: float, surface_y: float, leg_x: int, leg_z: int
) -> Transform3D:
	var ws = _ws()
	var corner_x: float = world_x if leg_x > 0 else world_x + 1.0
	var corner_z: float = world_z if leg_z > 0 else world_z + 1.0
	var basis := Basis(
		Vector3(float(leg_x), 0.0, 0.0),
		Vector3.UP,
		Vector3(0.0, 0.0, float(leg_z))
	)
	var origin := Vector3(
		ws.column_to_world(corner_x),
		surface_y,
		ws.column_to_world(corner_z)
	)
	return Transform3D(basis, origin)
