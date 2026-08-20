extends SceneTree
## P1 regression: concave diagonal gap emits textured interior floor at cell surface.


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

	var cm_src := (load("res://chunks/chunk_manager.gd") as GDScript).source_code
	if "_append_concave_interior_floor" not in cm_src:
		push_error("chunk_manager must emit concave interior floor tops")
		failed = true
	else:
		print("OK concave interior floor helper present")

	var layer: float = _WorldSettings.get_active().layer_height()
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
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var diagonal := 0
	var floor_tops := 0
	for q in quads:
		if int(q.get("x", -1)) != gx or int(q.get("z", -1)) != gz:
			continue
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP_SIDE:
			diagonal += 1
		elif fc == FACE_TOP and is_equal_approx(float(q.get("y", -1)), gap_h):
			floor_tops += 1

	if diagonal != 1:
		push_error("L-step gap must emit one diagonal prism, got %d" % diagonal)
		failed = true
	else:
		print("OK diagonal prism at (%d,%d)" % [gx, gz])

	if floor_tops < 2:
		push_error("gap floor needs >=2 TOP faces at y=%.2f, got %d" % [gap_h, floor_tops])
		failed = true
	else:
		print("OK interior floor tops=%d at y=%.2f" % [floor_tops, gap_h])

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		quit(1)
		return
	print("All ramp diagonal floor tests OK")
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