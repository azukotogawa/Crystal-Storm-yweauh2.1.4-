class_name TerrainRamps
extends RefCounted

const PLACEMENT_CHANCE := 38
const STEP_MIN := 0.85
const STEP_MAX := 1.35

const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

const _WorldBorder = preload("res://helpers/world_border.gd")

static var _wedge_mesh: ArrayMesh
static var _corner_mesh: ArrayMesh
const _WEDGE_MESH_VERSION := 4
const _CORNER_MESH_VERSION := 2


static func should_place_ramp(world_x: int, world_z: int, dir: Vector2i) -> bool:
	if _WorldBorder.should_force_ramp(world_x, world_z):
		return true
	var seed_val := world_x * 73856093 ^ world_z * 19349663 ^ dir.x * 83492791 ^ dir.y * 50331653
	var bucket: int = int(seed_val & 0x7fffffff) % 100
	return bucket < PLACEMENT_CHANCE


static func is_step_height(diff: float) -> bool:
	return diff >= STEP_MIN and diff <= STEP_MAX


static func candidate_dirs(_wx: float, _wz: float) -> Array:
	return DIRS.duplicate()


static func get_wedge_mesh() -> ArrayMesh:
	if _wedge_mesh != null and _wedge_mesh.get_meta("version", 0) == _WEDGE_MESH_VERSION:
		return _wedge_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cell-centered footprint (±0.5), rising toward +X. Origin is placed at the
	# column center (wx+0.5, surface_y, wz+0.5) to match greedy terrain boxes.
	_add_quad_uv(st,
		Vector3(-0.5, 1, -0.5), Vector3(0.5, 2, -0.5), Vector3(0.5, 2, 0.5), Vector3(-0.5, 1, 0.5),
		Vector3(0, 0.70710678, 0.70710678),
		Vector2(0, 0), Vector2(1, 1), Vector2(1, 1), Vector2(0, 0)
	)
	_add_quad_uv(st,
		Vector3(0.5, 1, -0.5), Vector3(0.5, 2, -0.5), Vector3(0.5, 2, 0.5), Vector3(0.5, 1, 0.5),
		Vector3.RIGHT,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)
	)
	_add_tri_uv(st,
		Vector3(-0.5, 1, -0.5), Vector3(0.5, 1, -0.5), Vector3(0.5, 2, -0.5),
		Vector3(0, 0, -1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)
	)
	_add_tri_uv(st,
		Vector3(-0.5, 1, 0.5), Vector3(0.5, 2, 0.5), Vector3(0.5, 1, 0.5),
		Vector3(0, 0, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)
	)
	_wedge_mesh = st.commit()
	_wedge_mesh.set_meta("version", _WEDGE_MESH_VERSION)
	return _wedge_mesh


static func get_corner_mesh() -> ArrayMesh:
	if _corner_mesh != null and _corner_mesh.get_meta("version", 0) == _CORNER_MESH_VERSION:
		return _corner_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cell-centered outer corner rising toward +X and +Z (low at NW).
	var p00 := Vector3(-0.5, 1, -0.5)
	var p10 := Vector3(0.5, 2, -0.5)
	var p01 := Vector3(-0.5, 2, 0.5)
	var p11 := Vector3(0.5, 2, 0.5)

	_add_tri_uv(st, p00, p10, p11, Vector3(0, 0.70710678, 0.70710678), Vector2(0, 0), Vector2(1, 1), Vector2(1, 1))
	_add_tri_uv(st, p00, p11, p01, Vector3(0, 0.70710678, 0.70710678), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
	_add_quad_uv(st, Vector3(0.5, 1, -0.5), p10, p11, Vector3(0.5, 1, 0.5), Vector3.RIGHT,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_add_tri_uv(st, p00, Vector3(-0.5, 1, 0.5), p01, Vector3(-1, 0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(0, 1))
	_add_tri_uv(st, p00, Vector3(0.5, 1, -0.5), p10, Vector3(0, 0, -1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_add_tri_uv(st, Vector3(-0.5, 1, 0.5), p11, p01, Vector3(0, 0, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))

	_corner_mesh = st.commit()
	_corner_mesh.set_meta("version", _CORNER_MESH_VERSION)
	return _corner_mesh


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
		var nx: int = wx + d.x
		var nz: int = wz + d.y
		var nh: float = world.get_surface_height(float(nx), float(nz))
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


static func surface_height_on_ramp(wx: float, wz: float, base_h: float, dir: Vector2i) -> float:
	return base_h + 1.0 + clampf(axis_t(wx, wz, dir), 0.0, 1.0)


static func surface_height_on_corner(
	wx: float, wz: float, base_h: float, dir_a: Vector2i, dir_b: Vector2i
) -> float:
	var t_a: float = clampf(axis_t(wx, wz, dir_a), 0.0, 1.0)
	var t_b: float = clampf(axis_t(wx, wz, dir_b), 0.0, 1.0)
	return base_h + 1.0 + maxf(t_a, t_b)


static func walkable_height_from_entry(
	world: InfiniteNoiseWorld, wx: float, wz: float, entry: Dictionary
) -> float:
	if world == null:
		return 1.0
	var tile_x: int = floori(wx)
	var tile_z: int = floori(wz)
	var base: float = world.get_surface_height(float(tile_x), float(tile_z))
	if entry.is_empty():
		return base + 1.0
	if entry.get("corner", false):
		return surface_height_on_corner(wx, wz, base, entry.get("dir", Vector2i.ZERO), entry.get("dir2", Vector2i.ZERO))
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	if dir != Vector2i.ZERO:
		return surface_height_on_ramp(wx, wz, base, dir)
	return base + 1.0


static func walkable_height(
	world: InfiniteNoiseWorld, wx: float, wz: float, known_dir: Vector2i = Vector2i.ZERO
) -> float:
	if world == null:
		return 1.0
	if known_dir != Vector2i.ZERO:
		return walkable_height_from_entry(world, wx, wz, {"corner": false, "dir": known_dir, "dir2": Vector2i.ZERO})
	var tile_x: int = floori(wx)
	var tile_z: int = floori(wz)
	var dir: Vector2i = ramp_direction_at(world, tile_x, tile_z)
	if dir != Vector2i.ZERO:
		return surface_height_on_ramp(wx, wz, world.get_surface_height(float(tile_x), float(tile_z)), dir)
	return world.get_surface_height(float(tile_x), float(tile_z)) + 1.0


static func wedge_transform(world_x: float, world_z: float, base_y: float, dir: Vector2i) -> Transform3D:
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
		return Transform3D.IDENTITY.translated(Vector3(world_x + 0.5, base_y, world_z + 0.5))

	var basis := Basis(Vector3.UP, yaw)
	return Transform3D(basis, Vector3(world_x + 0.5, base_y, world_z + 0.5))


static func corner_transform(
	world_x: float, world_z: float, base_y: float, dir_a: Vector2i, dir_b: Vector2i
) -> Transform3D:
	var x_dir: Vector2i = dir_a if dir_a.x != 0 else dir_b
	var z_dir: Vector2i = dir_b if dir_b.y != 0 else dir_a
	var sx: float = -1.0 if x_dir.x < 0 else 1.0
	var sz: float = -1.0 if z_dir.y < 0 else 1.0
	var basis := Basis(Vector3(sx, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, sz))
	return Transform3D(basis, Vector3(world_x + 0.5, base_y, world_z + 0.5))