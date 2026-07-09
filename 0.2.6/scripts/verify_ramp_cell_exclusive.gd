extends SceneTree
## Ramp landing cell must not emit terrain box faces in the wedge layer (only ramp mesh).


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_TOP := 0
const FACE_RAMP := 7


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()
	_TerrainRamps.placement_chance = 100
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	for x in _ChunkData.SIZE:
		data.surface_map.append([]); data.tile_map.append([])
		data.surface_map[x].resize(_ChunkData.SIZE); data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = 8.0; data.tile_map[x][z] = _VoxelTypes.GRASSLAND
	var hx := 6; var hz := 5
	var low_h := 10.0
	data.surface_map[5][5] = low_h
	data.surface_map[hx][hz] = low_h + layer
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var terrain_on_ramp := 0
	for q in cm._build_mesh(data).get("quads", []):
		if int(q.get("x", -1)) != hx or int(q.get("z", -1)) != hz:
			continue
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP:
			continue
		if fc == FACE_TOP:
			terrain_on_ramp += 1
		elif fc in [3, 4, 5, 6]:
			terrain_on_ramp += 1
	if terrain_on_ramp > 0:
		push_error("ramp cell (%d,%d) has %d terrain box faces besides ramp" % [hx, hz, terrain_on_ramp])
		failed = true
	else:
		print("OK ramp cell exclusive mesh")
	var ax := 5
	var az := 5
	var terrain_on_approach := 0
	for q in cm._build_mesh(data).get("quads", []):
		if int(q.get("x", -1)) != ax or int(q.get("z", -1)) != az:
			continue
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP:
			continue
		if fc == FACE_TOP or fc in [3, 4, 5, 6]:
			terrain_on_approach += 1
	if terrain_on_approach > 0:
		push_error("approach cell (%d,%d) has %d terrain box faces under ramp" % [ax, az, terrain_on_approach])
		failed = true
	else:
		print("OK approach cell has no terrain box under ramp")
	# Corner L-step low cell: flat FACE_TOP at base must not coexist with corner prism.
	var data2 := _ChunkData.new(Vector2i(0, 0), world)
	data2.capture_worker_snapshot()
	for x in _ChunkData.SIZE:
		data2.surface_map.append([]); data2.tile_map.append([])
		data2.surface_map[x].resize(_ChunkData.SIZE); data2.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data2.surface_map[x][z] = 8.0; data2.tile_map[x][z] = _VoxelTypes.GRASSLAND
	var cx := 6; var cz := 6
	data2.surface_map[cx][cz] = low_h
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		data2.surface_map[cx + d.x][cz + d.y] = low_h + layer
	var tops_at_base := 0
	var corner_prism := 0
	for q in cm._build_mesh(data2).get("quads", []):
		if int(q.get("x", -1)) != cx or int(q.get("z", -1)) != cz:
			continue
		var fc := int(q.get("face_code", -1))
		if fc == 8:
			corner_prism += 1
		elif fc == FACE_TOP and is_equal_approx(float(q.get("y", -1)), low_h):
			tops_at_base += 1
	if corner_prism < 1:
		push_error("corner prism missing")
		failed = true
	elif tops_at_base > 0:
		push_error("corner cell has flat top at base y=%.2f (block under prism), tops=%d" % [low_h, tops_at_base])
		failed = true
	else:
		print("OK corner cell no flat base top under prism")

	if failed:
		quit(1)
	else:
		print("All ramp cell exclusive tests OK")
		quit(0)