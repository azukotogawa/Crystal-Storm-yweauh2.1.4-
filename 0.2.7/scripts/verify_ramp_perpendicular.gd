extends SceneTree
## Regression: adjacent landings with perpendicular ramp dirs must not both emit cardinals.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8


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

	var ax := 5
	var az := 5
	var bx := 5
	var bz := 4
	var h := 10.0
	# Pad neighborhood so only the intended single-step edges exist (defaults are 8.0).
	for x in range(3, 8):
		for z in range(2, 7):
			data.surface_map[x][z] = h
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND
	data.surface_map[ax - 1][az] = h - layer
	data.tile_map[ax - 1][az] = _VoxelTypes.GRASSLAND
	data.surface_map[bx][bz - 1] = h - layer
	data.tile_map[bx][bz - 1] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_a := 0
	var ramp_b := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if fc != FACE_RAMP and fc != FACE_RAMP_CORNER:
			continue
		if int(q.get("x", -1)) == ax and int(q.get("z", -1)) == az:
			ramp_a += 1
		if int(q.get("x", -1)) == bx and int(q.get("z", -1)) == bz:
			ramp_b += 1

	if ramp_a > 0 and ramp_b > 0:
		push_error("perpendicular adjacent landings must not both emit ramps (a=%d b=%d)" % [ramp_a, ramp_b])
		failed = true
	else:
		print("OK perpendicular adjacent ramps not connected")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp perpendicular tests FAILED")
		quit(1)
		return
	print("All ramp perpendicular tests OK")
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