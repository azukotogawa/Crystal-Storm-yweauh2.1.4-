extends SceneTree
## P1 regression: player-built walls suppress ramp placement on wall cells and neighbors.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var cm_src := (load("res://chunks/chunk_manager.gd") as GDScript).source_code
	if "_has_player_build_at" not in cm_src:
		push_error("chunk_manager must gate ramps on player builds")
		failed = true
	else:
		print("OK ramp build gate present")

	_TerrainEdits.reset()
	var layer: float = _WorldSettings.get_active().layer_height()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_init_maps(data)

	var landing_x := 6
	var landing_z := 6
	var low_x := 7
	var low_z := 6
	var base_h := 10.0
	data.surface_map[landing_x][landing_z] = base_h + layer
	data.surface_map[low_x][low_z] = base_h
	data.tile_map[landing_x][landing_z] = _VoxelTypes.STONE
	data.tile_map[low_x][low_z] = _VoxelTypes.STONE

	if not _TerrainEdits.build_wall(landing_x, landing_z, _VoxelTypes.STONE):
		push_error("build_wall failed on landing cell")
		failed = true
	else:
		print("OK built wall at (%d,%d)" % [landing_x, landing_z])

	data.capture_worker_snapshot()
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	cm._build_mesh(data)

	if data.has_ramp(landing_x, landing_z):
		push_error("ramp emitted on player-built landing cell")
		failed = true
	else:
		print("OK no ramp on built landing")

	if data.has_ramp(low_x, low_z):
		push_error("ramp emitted on approach cell beside built wall")
		failed = true
	else:
		print("OK no ramp on approach beside wall")

	_TerrainEdits.reset()
	if failed:
		quit(1)
	print("All ramp wall exclusion tests OK")
	quit(0)


func _init_maps(data: _ChunkData) -> void:
	data.surface_map.resize(_ChunkData.SIZE)
	data.tile_map.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data.surface_map[x] = []
		data.tile_map[x] = []
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = 10.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND