extends SceneTree
## Regression: L-shaped step corners emit triangular prism (FACE_RAMP_CORNER), not cardinal wedge.


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
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])

	var corner := 0
	var cardinal_at_cell := 0
	var floor_tops := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if int(q.get("x", -1)) != cx or int(q.get("z", -1)) != cz:
			continue
		if fc == FACE_RAMP_CORNER:
			corner += 1
			if int(q.get("ramp_dir2_x", 0)) == 0 and int(q.get("ramp_dir2_z", 0)) == 0:
				push_error("corner ramp must set ramp_dir2")
				failed = true
		elif fc == FACE_RAMP:
			cardinal_at_cell += 1
		elif fc == FACE_TOP and float(q.get("y", -1.0)) == low_h:
			floor_tops += 1

	if corner < 1:
		push_error("L-step must emit corner prism at low cell, got corner=%d cardinal=%d" % [corner, cardinal_at_cell])
		failed = true
	else:
		print("OK step-corner prisms=%d" % corner)

	if cardinal_at_cell > 0:
		push_error("L-step low cell must not get cardinal wedge, got %d" % cardinal_at_cell)
		failed = true
	else:
		print("OK no cardinal wedge on corner cell")

	if floor_tops > 0:
		push_error("corner cell must not emit flat block at low_h under prism, tops=%d" % floor_tops)
		failed = true
	else:
		print("OK corner cell no flat base top under prism")

	if not data.is_ramp_corner(cx, cz):
		push_error("ramp_map must mark corner at (%d,%d)" % [cx, cz])
		failed = true
	else:
		print("OK ramp_map corner flag")

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