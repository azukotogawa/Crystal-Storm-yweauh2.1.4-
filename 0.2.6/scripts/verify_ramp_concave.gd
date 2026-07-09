extends SceneTree
## Regression: diagonal concave ramps emit support fill + prism mesh; wedge stays in-column.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_TOP := 0
const FACE_RAMP_SIDE := 9


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()

	var ramp_src := (load("res://helpers/terrain_ramps.gd") as GDScript).source_code
	if "CONCAVE_MESH_REV := 3" not in ramp_src:
		push_error("terrain_ramps must use concave mesh rev 3")
		failed = true
	else:
		print("OK concave mesh rev 3")
	if "WEDGE_MESH_REV := 6" not in ramp_src:
		push_error("terrain_ramps must use landing-anchored wedge rev 6")
		failed = true
	else:
		print("OK wedge mesh rev 6")
	if "CORNER_STEP_MESH_REV := 1" not in ramp_src:
		push_error("terrain_ramps must define corner step mesh rev 1")
		failed = true
	else:
		print("OK corner step mesh rev 1")

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
	var support_tops := 0
	var side_walls := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP_SIDE:
			diagonal += 1
		elif fc == FACE_TOP and int(q.get("x", -1)) == gx and int(q.get("z", -1)) == gz:
			var y: float = float(q.get("y", -999.0))
			if y > gap_h + layer * 0.25 and y <= high_h + 0.01:
				support_tops += 1
		elif fc in [3, 4, 5, 6] and int(q.get("x", -1)) == gx and int(q.get("z", -1)) == gz:
			side_walls += 1

	if diagonal < 1:
		push_error("concave L-corner must emit diagonal prism, got %d" % diagonal)
		failed = true
	else:
		print("OK concave diagonal prisms=%d" % diagonal)

	if support_tops < 2:
		push_error("concave gap needs stacked support tops, got %d" % support_tops)
		failed = true
	else:
		print("OK concave support tops=%d" % support_tops)

	if side_walls < 2:
		push_error("concave gap needs inner side-wall fill, got %d" % side_walls)
		failed = true
	else:
		print("OK concave side walls=%d" % side_walls)

	var dir := Vector2i(1, 0)
	var xform := _TerrainRamps.wedge_transform(float(gx), float(gz), gap_h, dir)
	var origin_y: float = xform.origin.y
	var expected_y: float = gap_h + layer
	if absf(origin_y - expected_y) > 0.01:
		push_error("wedge origin must anchor at low walkable %.2f, got %.2f" % [expected_y, origin_y])
		failed = true
	else:
		print("OK wedge in-column origin_y=%.2f" % origin_y)

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