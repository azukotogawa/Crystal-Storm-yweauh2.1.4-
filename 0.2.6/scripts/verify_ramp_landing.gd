extends SceneTree
## Regression: cardinal landing ramp only on high column; low column keeps full terrain.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7
const FACE_TOP := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()

	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_init_maps(data)

	var low_x := 5
	var low_z := 5
	var high_x := 6
	var high_z := 5
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[low_x][low_z] = low_h
	data.tile_map[low_x][low_z] = _VoxelTypes.GRASSLAND
	data.surface_map[high_x][high_z] = high_h
	data.tile_map[high_x][high_z] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_on_low := 0
	var ramp_on_high := 0
	var terrain_top_on_low := 0
	for q in quads:
		if int(q.get("x", -1)) == low_x and int(q.get("z", -1)) == low_z:
			if int(q.get("face_code", -1)) == FACE_RAMP:
				ramp_on_low += 1
			elif int(q.get("face_code", -1)) == FACE_TOP:
				terrain_top_on_low += 1
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(q.get("x", -1)) == high_x and int(q.get("z", -1)) == high_z:
			ramp_on_high += 1
			var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
			if dir != Vector2i(-1, 0):
				push_error("landing ramp must point toward low neighbor, got %s" % dir)
				failed = true

	if ramp_on_low > 0:
		push_error("low cell (%d,%d) must not emit approach wedge, got %d" % [low_x, low_z, ramp_on_low])
		failed = true
	else:
		print("OK no ramp mesh on low cell")

	if terrain_top_on_low < 1:
		push_error("low cell (%d,%d) must keep terrain top face" % [low_x, low_z])
		failed = true
	else:
		print("OK low cell terrain top preserved")

	if data.has_ramp(low_x, low_z):
		push_error("ramp_map must not mark low approach cell")
		failed = true
	else:
		print("OK ramp_map no approach cell")

	if ramp_on_high < 1:
		push_error("cardinal ramp must emit on landing cell (%d,%d), got %d" % [high_x, high_z, ramp_on_high])
		failed = true
	else:
		print("OK landing ramp on high cell=%d" % ramp_on_high)

	if not data.has_ramp(high_x, high_z):
		push_error("ramp_map must mark landing cell")
		failed = true
	else:
		print("OK ramp_map landing cell")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp landing tests FAILED")
		quit(1)
		return
	print("All ramp landing tests OK")
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