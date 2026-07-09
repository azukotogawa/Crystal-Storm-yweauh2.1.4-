extends SceneTree
## Regression: side cell with low on one axis and high on the opposite must not get a buried cardinal ramp.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7


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

	var side_x := 5
	var side_z := 5
	var low_west_x := 4
	var high_east_x := 6
	var h := 10.0
	data.surface_map[low_west_x][side_z] = h - layer
	data.tile_map[low_west_x][side_z] = _VoxelTypes.GRASSLAND
	data.surface_map[side_x][side_z] = h
	data.tile_map[side_x][side_z] = _VoxelTypes.GRASSLAND
	data.surface_map[high_east_x][side_z] = h + layer
	data.tile_map[high_east_x][side_z] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_on_side := 0
	var ramp_on_east := 0
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(q.get("x", -1)) == side_x and int(q.get("z", -1)) == side_z:
			ramp_on_side += 1
		if int(q.get("x", -1)) == high_east_x and int(q.get("z", -1)) == side_z:
			ramp_on_east += 1
			var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
			if dir != Vector2i(-1, 0):
				push_error("east landing ramp must point west toward side cell, got %s" % dir)
				failed = true

	if ramp_on_side > 0:
		push_error("side cell (%d,%d) must not emit buried cardinal ramp, got %d" % [side_x, side_z, ramp_on_side])
		failed = true
	else:
		print("OK no ramp on side cell")

	if data.has_ramp(side_x, side_z):
		push_error("ramp_map must not mark side cell")
		failed = true
	else:
		print("OK ramp_map no side cell")

	if ramp_on_east < 1:
		push_error("landing ramp must emit on east high cell (%d,%d), got %d" % [high_east_x, side_z, ramp_on_east])
		failed = true
	else:
		print("OK landing ramp on east high cell")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp side-cell tests FAILED")
		quit(1)
		return
	print("All ramp side-cell tests OK")
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