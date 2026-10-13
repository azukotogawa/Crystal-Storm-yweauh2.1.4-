extends SceneTree
## Regression: high landing with two perpendicular step-down neighbors must not emit corner prisms.


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

	var hx := 6
	var hz := 6
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[hx][hz] = high_h
	data.tile_map[hx][hz] = _VoxelTypes.GRASSLAND
	data.surface_map[hx + 1][hz] = low_h
	data.tile_map[hx + 1][hz] = _VoxelTypes.GRASSLAND
	data.surface_map[hx][hz + 1] = low_h
	data.tile_map[hx][hz + 1] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var corner := 0
	var cardinal := 0
	for q in quads:
		if int(q.get("x", -1)) != hx or int(q.get("z", -1)) != hz:
			continue
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP_CORNER:
			corner += 1
		elif fc == FACE_RAMP:
			cardinal += 1

	if corner > 0:
		push_error("dual-step landing must not emit corner prism, got %d" % corner)
		failed = true
	else:
		print("OK no corner prism on dual-step landing")

	if data.is_ramp_corner(hx, hz):
		push_error("ramp_map must not mark landing corner cell")
		failed = true
	else:
		print("OK ramp_map no landing corner")

	print("OK dual-step landing cardinal=%d (cardinal-only policy)" % cardinal)

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp landing corner tests FAILED")
		quit(1)
		return
	print("All ramp landing corner tests OK")
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