extends SceneTree


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7
const FACE_POS_Z := 6
const FACE_NEG_Z := 5


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

	var ramp_x := 6
	var ramp_z := 5
	var north_z := 4
	var south_z := 6
	var low_x := 5
	var h := 10.0
	data.surface_map[low_x][ramp_z] = h
	data.tile_map[low_x][ramp_z] = _VoxelTypes.GRASSLAND
	data.surface_map[ramp_x][ramp_z] = h + layer
	data.tile_map[ramp_x][ramp_z] = _VoxelTypes.GRASSLAND
	data.surface_map[ramp_x + 1][ramp_z] = h + layer
	data.tile_map[ramp_x + 1][ramp_z] = _VoxelTypes.GRASSLAND
	data.surface_map[ramp_x][north_z] = h + layer
	data.tile_map[ramp_x][north_z] = _VoxelTypes.DIRT
	data.surface_map[ramp_x][south_z] = h + layer
	data.tile_map[ramp_x][south_z] = _VoxelTypes.STONE

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	data.surface_map[ramp_x][south_z] = h
	data.tile_map[ramp_x][south_z] = _VoxelTypes.STONE
	quads = cm._build_mesh(data).get("quads", [])

	var ramp_count := 0
	var same_height_internal := 0
	var exposed_flank := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if int(q.get("x", -1)) == ramp_x and int(q.get("z", -1)) == ramp_z and fc == FACE_RAMP:
			ramp_count += 1
			exposed_flank = int(q.get("flank_a", 0)) + int(q.get("flank_b", 0))
		if fc == FACE_POS_Z and int(q.get("x", -1)) == ramp_x and int(q.get("z", -1)) == north_z:
			same_height_internal += 1

	if ramp_count < 1:
		push_error("expected cardinal ramp on landing (%d,%d), got %d" % [ramp_x, ramp_z, ramp_count])
		failed = true
	else:
		print("OK cardinal ramp on landing")

	if same_height_internal < 1:
		push_error("same-height north neighbor must emit +Z face into the ramp cut, got %d" % same_height_internal)
		failed = true
	else:
		print("OK same-height north face fills ramp cut n=%d" % same_height_internal)

	if exposed_flank < 1:
		push_error("lower south neighbor must expose a ramp-cut flank")
		failed = true
	else:
		print("OK exposed south ramp-cut flank=%d" % exposed_flank)

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp flank face tests FAILED")
		quit(1)
		return
	print("All ramp flank face tests OK")
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