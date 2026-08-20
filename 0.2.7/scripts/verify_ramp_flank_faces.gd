extends SceneTree
## Regression: same-height neighbors perpendicular to a cardinal ramp keep side faces toward it.


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
	data.surface_map[ramp_x][north_z] = h + layer
	data.tile_map[ramp_x][north_z] = _VoxelTypes.DIRT
	data.surface_map[ramp_x][south_z] = h + layer
	data.tile_map[ramp_x][south_z] = _VoxelTypes.STONE

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_count := 0
	var north_flank := 0
	var south_flank := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if int(q.get("x", -1)) == ramp_x and int(q.get("z", -1)) == ramp_z and fc == FACE_RAMP:
			ramp_count += 1
		if fc == FACE_POS_Z and int(q.get("x", -1)) == ramp_x and int(q.get("z", -1)) == north_z + 1:
			if int(q.get("type", -1)) == _VoxelTypes.DIRT:
				north_flank += 1
		if fc == FACE_NEG_Z and int(q.get("x", -1)) == ramp_x and int(q.get("z", -1)) == south_z:
			if int(q.get("type", -1)) == _VoxelTypes.STONE:
				south_flank += 1

	if ramp_count < 1:
		push_error("expected cardinal ramp on landing (%d,%d), got %d" % [ramp_x, ramp_z, ramp_count])
		failed = true
	else:
		print("OK cardinal ramp on landing")

	if north_flank < 1:
		push_error("north neighbor (%d,%d) must keep +Z flank toward ramp" % [ramp_x, north_z])
		failed = true
	else:
		print("OK north flank face toward ramp")

	if south_flank < 1:
		push_error("south neighbor (%d,%d) must keep -Z flank toward ramp" % [ramp_x, south_z])
		failed = true
	else:
		print("OK south flank face toward ramp")

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