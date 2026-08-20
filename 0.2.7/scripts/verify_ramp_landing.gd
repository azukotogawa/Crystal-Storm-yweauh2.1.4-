extends SceneTree
## Regression: cardinal step ramps emit on landing (high) column, not the lower approach cell.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7


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

	var low_x := 5
	var low_z := 5
	var high_x := 6
	var high_z := 5
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[low_x][low_z] = low_h
	data.tile_map[low_x][low_z] = _VoxelTypes.GRASSLAND
	data.surface_map[high_x][high_z] = high_h
	data.tile_map[high_x][high_z] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_on_low := 0
	var ramp_on_high := 0
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(q.get("x", -1)) == low_x and int(q.get("z", -1)) == low_z:
			ramp_on_low += 1
		if int(q.get("x", -1)) == high_x and int(q.get("z", -1)) == high_z:
			ramp_on_high += 1
			var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
			if dir != Vector2i(-1, 0):
				push_error("landing ramp must point toward low neighbor, got %s" % dir)
				failed = true

	if ramp_on_low > 0:
		push_error("cardinal ramp must not emit on approach cell (%d,%d), got %d" % [low_x, low_z, ramp_on_low])
		failed = true
	else:
		print("OK no cardinal ramp on approach cell")

	if ramp_on_high < 1:
		push_error("cardinal ramp must emit on landing cell (%d,%d), got %d" % [high_x, high_z, ramp_on_high])
		failed = true
	else:
		print("OK landing ramp on high cell=%d" % ramp_on_high)

	if not data.has_ramp(high_x, high_z):
		push_error("ramp_map must mark landing cell")
		failed = true
	else:
		print("OK ramp_map landing cell")

	for step in [
		{"land": Vector2i(8, 8), "low": Vector2i(9, 8), "dir": Vector2i(1, 0)},
		{"land": Vector2i(8, 10), "low": Vector2i(7, 10), "dir": Vector2i(-1, 0)},
		{"land": Vector2i(10, 8), "low": Vector2i(10, 9), "dir": Vector2i(0, 1)},
		{"land": Vector2i(12, 8), "low": Vector2i(12, 7), "dir": Vector2i(0, -1)},
	]:
		var land: Vector2i = step.land
		var low: Vector2i = step.low
		var want: Vector2i = step.dir
		var fresh := _ChunkData.new(Vector2i(0, 0), world)
		fresh.capture_worker_snapshot()
		_init_maps(fresh)
		for x2 in _ChunkData.SIZE:
			for z2 in _ChunkData.SIZE:
				fresh.surface_map[x2][z2] = 10.0
		# Yard contract: landing stays; only the approach drops one layer.
		fresh.surface_map[low.x][low.y] = 10.0 - layer
		var q4: Array = cm._build_mesh(fresh).get("quads", [])
		var found := false
		for q2 in q4:
			if int(q2.get("face_code", -1)) != FACE_RAMP:
				continue
			if int(q2.get("x", -1)) != land.x or int(q2.get("z", -1)) != land.y:
				continue
			var got := Vector2i(int(q2.get("ramp_dir_x", 0)), int(q2.get("ramp_dir_z", 0)))
			if got != want:
				push_error("dir %s ramp dir want %s got %s" % [str(land), str(want), str(got)])
				failed = true
			found = true
		if not found:
			push_error("missing FACE_RAMP on landing %s dir %s" % [str(land), str(want)])
			failed = true
		else:
			print("OK FACE_RAMP landing %s dir %s" % [str(land), str(want)])

	# Live south failure: landing is also one layer below a perpendicular ridge.
	# Side-entry corner pick + approach-block used to consume the landing
	# (ramp_map.approach=true, faces=[]). Cardinal FACE_RAMP must still emit.
	var terrace := _ChunkData.new(Vector2i(0, 0), world)
	terrace.capture_worker_snapshot()
	_init_maps(terrace)
	for x3 in _ChunkData.SIZE:
		for z3 in _ChunkData.SIZE:
			terrace.surface_map[x3][z3] = 10.0
	var t_land := Vector2i(10, 8)
	var t_low := Vector2i(10, 9)
	var t_ridge := Vector2i(11, 8)
	terrace.surface_map[t_land.x][t_land.y] = 10.0
	terrace.surface_map[t_low.x][t_low.y] = 10.0 - layer
	terrace.surface_map[t_ridge.x][t_ridge.y] = 10.0 + layer
	var tq: Array = cm._build_mesh(terrace).get("quads", [])
	var t_found := false
	var t_entry: Dictionary = terrace.get_ramp_entry(t_land.x, t_land.y)
	for tq_v in tq:
		var tqd: Dictionary = tq_v
		if int(tqd.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(tqd.get("x", -1)) != t_land.x or int(tqd.get("z", -1)) != t_land.y:
			continue
		var tdir := Vector2i(int(tqd.get("ramp_dir_x", 0)), int(tqd.get("ramp_dir_z", 0)))
		if tdir != Vector2i(0, 1):
			push_error("terrace landing dir want (0, 1) got %s" % str(tdir))
			failed = true
		t_found = true
	if not t_found:
		push_error("terrace landing missing FACE_RAMP (entry=%s)" % str(t_entry))
		failed = true
	elif bool(t_entry.get("approach", false)):
		push_error("terrace landing consumed as approach %s" % str(t_entry))
		failed = true
	else:
		print("OK terrace landing FACE_RAMP not stolen as approach")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp landing tests FAILED")
		quit(1)
		return
	print("All ramp landing tests OK")
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