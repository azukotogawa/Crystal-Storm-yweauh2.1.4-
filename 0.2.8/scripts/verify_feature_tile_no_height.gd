extends SceneTree


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")


func _init() -> void:
	var failed := false
	var src := (load("res://chunks/chunk_data.gd") as GDScript).source_code
	if "elif feat_t >= 0 and absf(hdelta) > 0.01:" in src:
		push_error("feature tile overrides must apply when hdelta==0")
		failed = true
	elif src.count("elif feat_t >= 0:") < 1:
		push_error("_rebuild_dirty_column must apply feat_t without height gate")
		failed = true
	else:
		print("OK feature tile override not gated on height_delta")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()

	var world: InfiniteNoiseWorld = _InfiniteNoiseWorld.new()
	world.world_seed = 3
	var data := _ChunkData.new(Vector2i.ZERO, world)
	data.capture_worker_snapshot()
	data.ensure_column_maps()
	var lx := 4
	var lz := 4
	data._worker_height_delta[lx][lz] = 0.0
	data._worker_build_tile[lx][lz] = -1
	data._worker_feature_tile[lx][lz] = _VoxelTypes.RIVER
	data.tile_map[lx][lz] = _VoxelTypes.GRASSLAND
	data._rebuild_dirty_column(lx, lz, null)
	var got: int = int(data.tile_map[lx][lz])
	if got != _VoxelTypes.RIVER:
		push_error("zero-hdelta feature override must retile to RIVER, got %d" % got)
		failed = true
	else:
		print("OK zero-hdelta retile tile=%d" % got)

	data.tile_map[5][5] = _VoxelTypes.GRASSLAND
	data._worker_feature_tile[5][5] = -1
	data._worker_build_tile[5][5] = _VoxelTypes.STONE
	data._worker_height_delta[5][5] = 0.0
	data._has_baked_base = true
	data._baked_base_surface.resize(_ChunkData.SIZE)
	data._baked_base_tile.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data._baked_base_surface[x] = []
		data._baked_base_tile[x] = []
		data._baked_base_surface[x].resize(_ChunkData.SIZE)
		data._baked_base_tile[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data._baked_base_surface[x][z] = 10.0
			data._baked_base_tile[x][z] = _VoxelTypes.GRASSLAND
	data._rebuild_dirty_column(5, 5, null)
	if int(data.tile_map[5][5]) == _VoxelTypes.STONE:
		push_error("build_tile without height must not retile floor")
		failed = true
	else:
		print("OK build_tile without raise keeps floor tile=%d" % int(data.tile_map[5][5]))

	data._worker_build_tile[6][6] = -1
	data._worker_height_delta[6][6] = 0.0
	data._worker_feature_tile[6][6] = _VoxelTypes.WATER
	data.tile_map[6][6] = _VoxelTypes.GRASSLAND
	data._rebuild_dirty_column(6, 6, null)
	if int(data.tile_map[6][6]) != _VoxelTypes.WATER:
		push_error("baked zero-hdelta feature override must retile to WATER, got %d" % int(data.tile_map[6][6]))
		failed = true
	else:
		print("OK baked zero-hdelta retile to WATER")

	if failed:
		quit(1)
	print("All feature-tile-no-height tests OK")
	quit(0)
