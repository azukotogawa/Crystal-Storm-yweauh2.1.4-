extends SceneTree
## Regression: diagonal concave cell emits only the in-voxel prism (no support stack).


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _VoxelGeometryKind = preload("res://helpers/voxel_geometry_kind.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_TOP := 0
const FACE_POS_X := 4
const FACE_POS_Z := 6
const FACE_RAMP_SIDE := 9


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()

	var ramp_src := (load("res://helpers/terrain_ramps.gd") as GDScript).source_code
	var prim_src := (load("res://helpers/voxel_primitive_meshes.gd") as GDScript).source_code
	if "PRIMITIVE_MESH_REV := 5" not in ramp_src:
		push_error("terrain_ramps must reference primitive mesh rev 5")
		failed = true
	else:
		print("OK primitive mesh rev 5")
	if "MESH_REV := 11" not in prim_src:
		push_error("voxel_primitive_meshes must use MESH_REV 11 (oriented concave wedges)")
		failed = true
	else:
		print("OK voxel_primitive_meshes rev 11")

	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_init_maps(data)

	var gx := 5
	var gz := 5
	var high_h := 12.0
	var gap_h := high_h - layer * 2.0
	for ax in [gx - 1, gx, gx - 1]:
		for az in [gz, gz - 1, gz - 1]:
			if ax == gx and az == gz:
				data.surface_map[ax][az] = gap_h
			else:
				data.surface_map[ax][az] = high_h
			data.tile_map[ax][az] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])

	var diagonal := 0
	var substrate := 0
	var substrate_y := high_h - layer
	for q in quads:
		var fc := int(q.get("face_code", -1))
		var qx := int(q.get("x", -1))
		var qz := int(q.get("z", -1))
		if fc == FACE_RAMP_SIDE:
			if qx != gx or qz != gz:
				continue
			diagonal += 1
			if not is_equal_approx(float(q.get("y", -1)), high_h):
				push_error("concave prism must anchor at arm height %.2f, got %.2f" % [high_h, float(q.get("y", -1))])
				failed = true
		elif int(q.get("geometry_kind", -1)) == _VoxelGeometryKind.Kind.FULL_CUBE:
			var belongs := false
			match fc:
				FACE_POS_X:
					belongs = qx == gx + 1 and qz == gz
				FACE_POS_Z:
					belongs = qx == gx and qz == gz + 1
				_:
					belongs = qx == gx and qz == gz
			if not belongs:
				continue
			substrate += 1
			if not is_equal_approx(float(q.get("y", -1)), substrate_y):
				push_error("concave substrate must sit at %.2f, got %.2f" % [substrate_y, float(q.get("y", -1))])
				failed = true

	if diagonal != 1:
		push_error("concave gap must emit exactly one diagonal prism, got %d" % diagonal)
		failed = true
	else:
		print("OK concave diagonal prism at arm height")

	if substrate != 6:
		push_error("concave gap must emit six substrate faces underneath, got %d" % substrate)
		failed = true
	else:
		print("OK concave substrate cube underneath")

	var geo_kind: int = data.get_geometry_kind(gx, gz)
	if geo_kind != _VoxelGeometryKind.Kind.DIAGONAL_RAMP:
		push_error("concave gap geometry kind expected DIAGONAL_RAMP, got %d" % geo_kind)
		failed = true
	else:
		print("OK concave geometry kind")

	var entry: Dictionary = data.get_ramp_entry(gx, gz)
	var h_a: float = _TerrainRamps.walkable_height_from_entry(world, float(gx) + 0.2, float(gz) + 0.2, entry)
	var h_b: float = _TerrainRamps.walkable_height_from_entry(world, float(gx) + 0.8, float(gz) + 0.8, entry)
	if not is_equal_approx(h_a, h_b):
		push_error("concave must be flat walkable h_a=%.2f h_b=%.2f" % [h_a, h_b])
		failed = true
	else:
		print("OK concave not walkable slope")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp concave tests FAILED")
		quit(1)
		return
	print("All ramp concave tests OK")
	quit(0)


func _init_maps(data: ChunkData) -> void:
	data.surface_map.resize(_ChunkData.SIZE)
	data.tile_map.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data.surface_map[x] = []
		data.tile_map[x] = []
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = 8.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND