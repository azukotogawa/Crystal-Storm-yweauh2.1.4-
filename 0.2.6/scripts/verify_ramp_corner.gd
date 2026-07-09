extends SceneTree
## Regression: L-shaped step corners must not emit corner prisms (cardinal + concave only).


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_TOP := 0
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

	var cx := 6
	var cz := 6
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[cx][cz] = low_h
	data.tile_map[cx][cz] = _VoxelTypes.GRASSLAND
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		data.surface_map[cx + d.x][cz + d.y] = high_h
		data.tile_map[cx + d.x][cz + d.y] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var corner := 0
	var cardinal_at_cell := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if int(q.get("x", -1)) != cx or int(q.get("z", -1)) != cz:
			continue
		if fc == FACE_RAMP_CORNER:
			corner += 1
		elif fc == FACE_RAMP:
			cardinal_at_cell += 1

	if corner > 0:
		push_error("L-step low cell must not emit corner prism, got %d" % corner)
		failed = true
	else:
		print("OK no corner prism on L-step low cell")

	if cardinal_at_cell > 0:
		push_error("L-step low cell must not get cardinal wedge, got %d" % cardinal_at_cell)
		failed = true
	else:
		print("OK no cardinal wedge on L-step low cell")

	if data.is_ramp_corner(cx, cz):
		push_error("ramp_map must not mark corner at (%d,%d)" % [cx, cz])
		failed = true
	else:
		print("OK ramp_map no corner flag")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp corner tests FAILED")
		quit(1)
		return
	print("All ramp corner tests OK")
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