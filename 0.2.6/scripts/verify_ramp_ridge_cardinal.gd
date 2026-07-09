extends SceneTree
## Regression: ridge with low west + high north still emits a ramp (on the north landing), approach keeps terrain.


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

	var approach_x := 5
	var approach_z := 5
	var north_x := 5
	var north_z := 4
	var h := 10.0
	data.surface_map[approach_x - 1][approach_z] = h - layer
	data.tile_map[approach_x - 1][approach_z] = _VoxelTypes.GRASSLAND
	data.surface_map[approach_x][approach_z] = h
	data.tile_map[approach_x][approach_z] = _VoxelTypes.GRASSLAND
	data.surface_map[north_x][north_z] = h + layer
	data.tile_map[north_x][north_z] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_on_north := 0
	var top_on_approach := 0
	for q in quads:
		var qx := int(q.get("x", -1))
		var qz := int(q.get("z", -1))
		var fc := int(q.get("face_code", -1))
		if qx == north_x and qz == north_z and fc == FACE_RAMP:
			ramp_on_north += 1
			var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
			if dir != Vector2i(0, 1):
				push_error("north landing must slope south, got %s" % dir)
				failed = true
		if qx == approach_x and qz == approach_z and fc == FACE_TOP:
			top_on_approach += 1

	if ramp_on_north < 1:
		push_error("north landing (%d,%d) must emit cardinal ramp, got %d" % [north_x, north_z, ramp_on_north])
		failed = true
	else:
		print("OK north landing cardinal ramp")

	if top_on_approach < 1:
		push_error("approach (%d,%d) must keep terrain top" % [approach_x, approach_z])
		failed = true
	else:
		print("OK approach terrain preserved")

	if data.has_ramp(approach_x, approach_z):
		push_error("approach cell must not be ramp_map landing")
		failed = true
	else:
		print("OK approach not ramp cell")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp ridge cardinal tests FAILED")
		quit(1)
		return
	print("All ramp ridge cardinal tests OK")
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