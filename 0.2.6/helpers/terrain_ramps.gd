class_name TerrainRamps
extends RefCounted

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelPrimitiveMeshes = preload("res://helpers/voxel_primitive_meshes.gd")

const PLACEMENT_CHANCE := 28
static var placement_chance: int = PLACEMENT_CHANCE

const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

const PRIMITIVE_MESH_REV := 5


static func invalidate_mesh_cache() -> void:
	_VoxelPrimitiveMeshes.invalidate_cache()


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


static func get_cardinal_ramp_mesh(toward_low: Vector2i) -> ArrayMesh:
	return _VoxelPrimitiveMeshes.get_cardinal_ramp_mesh(toward_low)


static func get_corner_ramp_mesh(dir_a: Vector2i, dir_b: Vector2i) -> ArrayMesh:
	return _VoxelPrimitiveMeshes.get_corner_ramp_mesh(dir_a, dir_b)


static func get_concave_corner_prism_mesh(leg_x: int = 1, leg_z: int = 1) -> ArrayMesh:
	return _VoxelPrimitiveMeshes.get_concave_mesh(leg_x, leg_z)


static func get_half_cube_mesh() -> ArrayMesh:
	return _VoxelPrimitiveMeshes.get_half_cube_mesh()


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
	var t: float = clampf(axis_t(wx, wz, dir), 0.0, 1.0)
	return voxel_top_y(base_h) - t * layer


static func is_landing_ramp_entry(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	if entry.get("concave", false) or entry.get("corner", false) or entry.get("approach", false):
		return false
	return entry.get("dir", Vector2i.ZERO) != Vector2i.ZERO and entry.get("dir2", Vector2i.ZERO) == Vector2i.ZERO


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
		var arm_h: float = float(entry.get("surface_h", base))
		return arm_h + _ws().layer_height() * 0.5
	# Only landing cardinal ramps are sloped walkable surfaces.
	if not is_landing_ramp_entry(entry):
		return voxel_top_y(base)
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	return surface_height_on_ramp(wx, wz, base, dir)


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


static func voxel_transform(world_x: float, world_z: float, surface_y: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, _VoxelPrimitiveMeshes.voxel_origin(world_x, world_z, surface_y))


static func concave_corner_prism_transform(
	world_x: float, world_z: float, surface_y: float, _leg_x: int = 1, _leg_z: int = 1
) -> Transform3D:
	return voxel_transform(world_x, world_z, surface_y)


static func corner_ramp_legs(dir_a: Vector2i, dir_b: Vector2i) -> Vector2i:
	var leg_x: int = dir_a.x if dir_a.x != 0 else dir_b.x
	var leg_z: int = dir_b.y if dir_b.y != 0 else dir_a.y
	return Vector2i(leg_x, leg_z)