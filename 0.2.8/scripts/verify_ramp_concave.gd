extends SceneTree


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
	if "WEDGE_MESH_REV := 8" not in ramp_src:
		push_error("terrain_ramps must use the one-cell landing wedge rev 8")
		failed = true
	else:
		print("OK wedge mesh rev 8 (one-cell landing)")
	if "CORNER_STEP_MESH_REV := 3" not in ramp_src:
		push_error("terrain_ramps must use the triangle corner top rev 3")
		failed = true
	else:
		print("OK corner step mesh rev 3 (triangle top)")
	if "s * 2.0" in ramp_src or "flat shelf" in ramp_src:
		push_error("model B shelf / 2-layer corner prism must stay out")
		failed = true
	else:
		print("OK no wedge shelf or 2-layer corner prism")

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
	var gap_floor := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP_SIDE:
			diagonal += 1
		if int(q.get("x", -1)) != gx or int(q.get("z", -1)) != gz:
			continue
		if fc == FACE_TOP:
			var y: float = float(q.get("y", -999.0))
			if y > gap_h + layer * 0.25:
				support_tops += 1
			elif is_equal_approx(y, gap_h):
				gap_floor += 1

	if diagonal != 0:
		push_error("L-gap must not emit FACE_RAMP_SIDE compound prism, got %d" % diagonal)
		failed = true
	else:
		print("OK no concave compound prism")

	if support_tops != 0:
		push_error("L-gap must not stack mid-height FACE_TOPs, got %d" % support_tops)
		failed = true
	else:
		print("OK no stacked support tops")

	if gap_floor < 1:
		push_error("L-gap must keep its own floor FACE_TOP at gap_h, got %d" % gap_floor)
		failed = true
	else:
		print("OK gap floor tops=%d" % gap_floor)

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
