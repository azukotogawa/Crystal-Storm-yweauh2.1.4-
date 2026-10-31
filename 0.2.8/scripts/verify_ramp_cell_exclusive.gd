extends SceneTree


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
	_fill(data, 10.0)
	var hx := 6
	var hz := 5
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[5][5] = low_h
	for x in range(hx, hx + 3):
		for z in range(hz - 1, hz + 2):
			data.surface_map[x][z] = high_h
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var lid_on_ramp := 0
	var ramp_faces := 0
	for q in cm._build_mesh(data).get("quads", []):
		if not _covers(q, hx, hz):
			continue
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP:
			ramp_faces += 1
		elif fc == FACE_TOP:
			lid_on_ramp += 1
	if ramp_faces < 1:
		push_error("landing (%d,%d) missing FACE_RAMP" % [hx, hz])
		failed = true
	elif lid_on_ramp > 0:
		push_error("ramp landing (%d,%d) must not keep FACE_TOP lid, tops=%d" % [hx, hz, lid_on_ramp])
		failed = true
	else:
		print("OK ramp landing lid replaced by slope")
	var ax := 5
	var az := 5
	var approach_top := 0
	var approach_ramp := 0
	for q in cm._build_mesh(data).get("quads", []):
		if not _covers(q, ax, az):
			continue
		var fc := int(q.get("face_code", -1))
		if fc == FACE_RAMP:
			approach_ramp += 1
		elif fc == FACE_TOP:
			approach_top += 1
	if approach_ramp > 0:
		push_error("approach (%d,%d) must not be a second slope, ramps=%d" % [ax, az, approach_ramp])
		failed = true
	elif approach_top < 1:
		push_error("approach cell (%d,%d) must keep floor FACE_TOP, got %d" % [ax, az, approach_top])
		failed = true
	else:
		print("OK approach cell floor tops=%d" % approach_top)
	var data2 := _ChunkData.new(Vector2i(0, 0), world)
	data2.capture_worker_snapshot()
	_fill(data2, low_h)
	var cx := 6
	var cz := 6
	data2.surface_map[cx][cz] = low_h
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		data2.surface_map[cx + d.x][cz + d.y] = high_h
	var tops_at_base := 0
	var corner_prism := 0
	for q in cm._build_mesh(data2).get("quads", []):
		if not _covers(q, cx, cz):
			continue
		var fc := int(q.get("face_code", -1))
		if fc == 8:
			corner_prism += 1
		elif fc == FACE_TOP and absf(float(q.get("y", -1)) - low_h) <= TerrainLook.max_offset(layer) + 0.001:
			tops_at_base += 1
	if corner_prism > 0:
		push_error("isolated L without diagonal must not emit corner, got %d" % corner_prism)
		failed = true
	elif tops_at_base < 1:
		push_error("isolated L cell must keep floor FACE_TOP, tops=%d" % tops_at_base)
		failed = true
	else:
		print("OK isolated L is a floor, not a corner prism")

	if failed:
		quit(1)
	else:
		print("All ramp cell exclusive tests OK")
		quit(0)


func _covers(q: Dictionary, x: int, z: int) -> bool:
	var qx := int(q.get("x", -999))
	var qz := int(q.get("z", -999))
	var dx := maxi(1, int(round(float(q.get("dim_x", 1.0)))))
	var dz := maxi(1, int(round(float(q.get("dim_z", 1.0)))))
	return x >= qx and x < qx + dx and z >= qz and z < qz + dz


func _fill(data: ChunkData, h: float) -> void:
	data.surface_map.resize(_ChunkData.SIZE)
	data.tile_map.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data.surface_map[x] = []
		data.tile_map[x] = []
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = h
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND
