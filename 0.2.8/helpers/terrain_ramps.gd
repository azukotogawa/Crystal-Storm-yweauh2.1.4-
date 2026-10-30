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
static var _corner_step_mesh: ArrayMesh
static var _mesh_scale_key: float = -1.0
const CONCAVE_MESH_REV := 3
const WEDGE_MESH_REV := 9
const CURVE_STRIPS := 8
const EASE_SHOULDER := 0.22
const CORNER_STEP_MESH_REV := 3
static var _concave_mesh_rev: int = -1
static var _wedge_mesh_rev: int = -1
static var _corner_step_mesh_rev: int = -1


static func invalidate_mesh_cache() -> void:
	_wedge_mesh = null
	_concave_mesh = null
	_corner_step_mesh = null
	_mesh_scale_key = -1.0
	_concave_mesh_rev = -1
	_wedge_mesh_rev = -1
	_corner_step_mesh_rev = -1


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


static func should_place_corner(world_x: int, world_z: int) -> bool:
	if _WorldBorder.should_force_ramp(world_x, world_z):
		return true
	if placement_chance >= 100:
		return true
	var seed_val := world_x * 92837111 ^ world_z * 44556677 ^ 99112233
	var bucket: int = int(seed_val & 0x7fffffff) % 100
	return bucket < maxi(placement_chance / 4, 6)


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
		and _corner_step_mesh != null
		and _corner_step_mesh_rev == CORNER_STEP_MESH_REV
	):
		return
	_mesh_scale_key = s
	_wedge_mesh = null
	_concave_mesh = null
	_corner_step_mesh = null
	_wedge_mesh_rev = WEDGE_MESH_REV
	_concave_mesh_rev = CONCAVE_MESH_REV
	_corner_step_mesh_rev = CORNER_STEP_MESH_REV


static func get_wedge_mesh() -> ArrayMesh:
	_ensure_mesh_scale()
	if _wedge_mesh != null:
		return _wedge_mesh
	var s: float = _ws().voxel_scale
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -0.5 * s
	var z1 := 0.5 * s
	var descent := Vector2i(-1, 0)
	for i in CURVE_STRIPS:
		var t0 := curve_t(i, CURVE_STRIPS)
		var t1 := curve_t(i + 1, CURVE_STRIPS)
		var x_hi := lerpf(0.5 * s, -0.5 * s, t0)
		var x_lo := lerpf(0.5 * s, -0.5 * s, t1)
		var y_hi := -slope_ease(t0) * s
		var y_lo := -slope_ease(t1) * s
		var lo_nz := Vector3(x_lo, y_lo, z0)
		var lo_pz := Vector3(x_lo, y_lo, z1)
		var hi_pz := Vector3(x_hi, y_hi, z1)
		var hi_nz := Vector3(x_hi, y_hi, z0)
		var n_lo := slope_normal(t1, descent)
		var n_hi := slope_normal(t0, descent)
		_add_quad_smooth(st, lo_nz, lo_pz, hi_pz, hi_nz, n_lo, n_lo, n_hi, n_hi,
			Vector2(lo_nz.x, lo_nz.z), Vector2(lo_pz.x, lo_pz.z),
			Vector2(hi_pz.x, hi_pz.z), Vector2(hi_nz.x, hi_nz.z)
		)
	var fa := Vector3(-0.5 * s, -s, z0)
	var fb := Vector3(0.5 * s, -s, z0)
	var fc := Vector3(0.5 * s, -s, z1)
	var fd := Vector3(-0.5 * s, -s, z1)
	_add_quad_uv(st, fa, fb, fc, fd, Vector3.DOWN,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)
	)
	_wedge_mesh = st.commit()
	return _wedge_mesh


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


static func get_corner_step_mesh() -> ArrayMesh:
	_ensure_mesh_scale()
	if _corner_step_mesh != null:
		return _corner_step_mesh
	var s: float = _ws().voxel_scale
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low := Vector3.ZERO
	var high_x := Vector3(s, s, 0.0)
	var high_z := Vector3(0.0, s, s)
	_add_tri_uv(st, low, high_z, high_x, Vector3(-0.5, 0.707, -0.5).normalized(), Vector2(0, 0), Vector2(0, 1), Vector2(1, 0))
	_add_tri_uv(st, low, high_x, high_z, Vector3.DOWN, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1))
	_corner_step_mesh = st.commit()
	return _corner_step_mesh


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


static func _add_quad_smooth(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2
) -> void:
	_add_tri_smooth(st, a, b, c, na, nb, nc, uv_a, uv_b, uv_c)
	_add_tri_smooth(st, a, c, d, na, nc, nd, uv_a, uv_c, uv_d)


static func _add_tri_smooth(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3,
	na: Vector3, nb: Vector3, nc: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2
) -> void:
	st.set_normal(na)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uv_c)
	st.add_vertex(c)


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


static func curve_t(i: int, strips: int) -> float:
	var u := clampf(float(i) / float(maxi(strips, 1)), 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * u)


static func slope_ease(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	var w := EASE_SHOULDER
	var peak := 1.0 / (1.0 - w)
	var shoulder := peak * w * 0.5
	if u < w:
		return shoulder * (u / w - sin(PI * u / w) / PI)
	if u > 1.0 - w:
		var v := 1.0 - u
		return 1.0 - shoulder * (v / w - sin(PI * v / w) / PI)
	return shoulder + peak * (u - w)


static func slope_ease_deriv(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	var w := EASE_SHOULDER
	var peak := 1.0 / (1.0 - w)
	if u < w:
		return peak * 0.5 * (1.0 - cos(PI * u / w))
	if u > 1.0 - w:
		return peak * 0.5 * (1.0 - cos(PI * (1.0 - u) / w))
	return peak


static func slope_normal(t: float, dir: Vector2i) -> Vector3:
	var d := slope_ease_deriv(t)
	var n := Vector3(d * float(dir.x), 1.0, d * float(dir.y))
	if n.length_squared() < 0.000001:
		return Vector3.UP
	return n.normalized()


static func surface_height_on_ramp(wx: float, wz: float, base_h: float, dir: Vector2i) -> float:
	var layer: float = _ws().layer_height()
	var t: float = clampf(axis_t(wx, wz, dir), 0.0, 1.0)
	return voxel_top_y(base_h) - slope_ease(t) * layer


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
		var column_h: float = float(entry.get("surface_h", base))
		var layer: float = _ws().layer_height()
		var toward: float = clampf(axis_t(wx, wz, dir), 0.0, 1.0) + clampf(axis_t(wx, wz, dir2), 0.0, 1.0)
		if toward >= 1.0:
			return voxel_top_y(column_h) + layer
		return voxel_top_y(column_h)
	if entry.get("approach", false):
		return voxel_top_y(base)
	if dir != Vector2i.ZERO and dir2 == Vector2i.ZERO:
		var landing_surface_c: float = float(entry.get("surface_h", base))
		return surface_height_on_ramp(wx, wz, landing_surface_c, dir)
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
	var away := Vector2i(-dir.x, -dir.y)
	var yaw: float = 0.0
	if away == Vector2i(1, 0):
		yaw = 0.0
	elif away == Vector2i(-1, 0):
		yaw = PI
	elif away == Vector2i(0, 1):
		yaw = -PI * 0.5
	elif away == Vector2i(0, -1):
		yaw = PI * 0.5
	else:
		return Transform3D.IDENTITY.translated(_ramp_origin(world_x, world_z, surface_y))
	var origin := _ramp_origin(world_x, world_z, surface_y + _ws().layer_height())
	return Transform3D(Basis(Vector3.UP, yaw), origin)


static func concave_corner_prism_transform(
	world_x: float, world_z: float, surface_y: float, leg_x: int, leg_z: int
) -> Transform3D:
	return _corner_prism_transform(world_x, world_z, surface_y, leg_x, leg_z)


static func corner_ramp_legs(dir_a: Vector2i, dir_b: Vector2i) -> Vector2i:
	var leg_x: int = dir_a.x if dir_a.x != 0 else dir_b.x
	var leg_z: int = dir_b.y if dir_b.y != 0 else dir_a.y
	return Vector2i(leg_x, leg_z)


static func corner_ramp_transform(
	world_x: float, world_z: float, surface_y: float, dir_a: Vector2i, dir_b: Vector2i
) -> Transform3D:
	var legs := corner_ramp_legs(dir_a, dir_b)
	return _corner_prism_transform(world_x, world_z, surface_y, legs.x, legs.y)


static func _corner_prism_transform(
	world_x: float, world_z: float, surface_y: float, leg_x: int, leg_z: int
) -> Transform3D:
	var lx: int = 1 if leg_x >= 0 else -1
	var lz: int = 1 if leg_z >= 0 else -1
	var yaw := 0.0
	if lx < 0 and lz > 0:
		yaw = -PI * 0.5
	elif lx < 0 and lz < 0:
		yaw = PI
	elif lx > 0 and lz < 0:
		yaw = PI * 0.5
	var ws = _ws()
	var corner_x: float = world_x if lx > 0 else world_x + 1.0
	var corner_z: float = world_z if lz > 0 else world_z + 1.0
	var origin := Vector3(
		ws.column_to_world(corner_x),
		surface_y,
		ws.column_to_world(corner_z)
	)
	return Transform3D(Basis(Vector3.UP, yaw), origin)
