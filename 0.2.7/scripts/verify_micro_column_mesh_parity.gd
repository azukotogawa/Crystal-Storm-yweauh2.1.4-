extends SceneTree
## Table-driven micro-on vs micro-off per-column mesh quad parity.


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _MicroCliffDetector = preload("res://helpers/micro_cliff_detector.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 4242

	var fixtures: Array = [
		{"name": "dig1_3_5", "wx": 3, "wz": 5, "dig": 1, "build": false},
		{"name": "dig2_8_8", "wx": 8, "wz": 8, "dig": 2, "build": false},
		{"name": "dig1_10_2", "wx": 10, "wz": 2, "dig": 1, "build": false},
		{"name": "build_12_14", "wx": 12, "wz": 14, "dig": 0, "build": true},
	]

	var failed := false
	for fix in fixtures:
		if not _run_fixture(world, fix):
			failed = true

	if not _run_cliff_fixture(world):
		failed = true

	_TerrainEdits.reset()
	if failed:
		quit(1)
	print("All micro column mesh parity tests OK")
	quit(0)


func _run_fixture(world: InfiniteNoiseWorld, fix: Dictionary) -> bool:
	_TerrainEdits.reset()
	var wx: int = int(fix.wx)
	var wz: int = int(fix.wz)
	if int(fix.dig) > 0:
		if not _TerrainEdits.dig(wx, wz, int(fix.dig)):
			push_error("%s: dig failed" % fix.name)
			return false
	if bool(fix.build):
		if not _TerrainEdits.build_wall(wx, wz, _VoxelTypes.STONE):
			push_error("%s: build_wall failed" % fix.name)
			return false

	var coord := Vector2i(
		floori(float(wx) / float(_ChunkData.SIZE)),
		floori(float(wz) / float(_ChunkData.SIZE))
	)
	var lx: int = wx - coord.x * _ChunkData.SIZE
	var lz: int = wz - coord.y * _ChunkData.SIZE

	var off_quads: Array = _build_column_mesh(world, coord, false, func(data: ChunkData) -> void:
		pass
	)
	var on_quads: Array = _build_column_mesh(world, coord, true, func(data: ChunkData) -> void:
		data.derive_micro_from_terrain_edits()
		if not data.has_micro_brick(lx, lz):
			push_error("%s: expected micro brick at local (%d,%d)" % [fix.name, lx, lz])
	)

	var off_sig: Array = _column_quad_signatures(off_quads, lx, lz)
	var on_sig: Array = _column_quad_signatures(on_quads, lx, lz)
	if not _signatures_equal(off_sig, on_sig):
		push_error("%s: quad mismatch off=%d on=%d" % [fix.name, off_sig.size(), on_sig.size()])
		return false

	print("OK parity %s column (%d,%d) quads=%d" % [fix.name, lx, lz, on_sig.size()])
	return true


func _run_cliff_fixture(world: InfiniteNoiseWorld) -> bool:
	_TerrainEdits.reset()
	var scout := _ChunkData.new(Vector2i(0, 0), world)
	scout.capture_worker_snapshot()
	scout._compute_column_maps(true)

	var layer_h: float = _WorldSettings.get_active().layer_height()
	var threshold: float = layer_h * _MicroCliffDetector.CLIFF_HEIGHT_RATIO
	var cliff_cell := Vector2i(-1, -1)
	for lx in _ChunkData.SIZE:
		for lz in _ChunkData.SIZE:
			if _MicroCliffDetector._is_cliff_column(scout, lx, lz, threshold):
				cliff_cell = Vector2i(lx, lz)
				break
		if cliff_cell.x >= 0:
			break
	if cliff_cell.x < 0:
		push_error("cliff fixture: no natural cliff column on seed 4242")
		return false

	var off_quads: Array = _build_column_mesh(world, Vector2i(0, 0), false, func(_data: ChunkData) -> void:
		pass
	)
	var on_quads: Array = _build_column_mesh(world, Vector2i(0, 0), true, func(data: ChunkData) -> void:
		data.update_dirty_column_maps([cliff_cell])
		if not data.has_micro_brick(cliff_cell.x, cliff_cell.y):
			push_error("cliff fixture: micro brick not allocated at (%d,%d)" % [cliff_cell.x, cliff_cell.y])
	)

	var off_sig: Array = _column_quad_signatures(off_quads, cliff_cell.x, cliff_cell.y)
	var on_sig: Array = _column_quad_signatures(on_quads, cliff_cell.x, cliff_cell.y)
	if not _signatures_equal(off_sig, on_sig):
		push_error(
			"cliff parity mismatch at (%d,%d) off=%d on=%d"
			% [cliff_cell.x, cliff_cell.y, off_sig.size(), on_sig.size()]
		)
		return false

	print("OK parity cliff column (%d,%d) quads=%d" % [cliff_cell.x, cliff_cell.y, on_sig.size()])
	return true


func _build_column_mesh(
	world: InfiniteNoiseWorld,
	coord: Vector2i,
	micro_on: bool,
	prep: Callable
) -> Array:
	var data := _ChunkData.new(coord, world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	_ChunkData.set_micro_enabled_for_benchmark(micro_on)
	prep.call(data)
	var cm := _ChunkManager.new()
	return cm._build_mesh(data).get("quads", [])


func _column_quad_signatures(quads: Array, lx: int, lz: int) -> Array:
	var sigs: Array = []
	for q in quads:
		if not _quad_covers_column(q, lx, lz):
			continue
		sigs.append(_column_local_signature(q, lx, lz))
	sigs.sort()
	return sigs


func _quad_covers_column(q: Dictionary, lx: int, lz: int) -> bool:
	var qx: float = float(q.get("x", 0.0))
	var qz: float = float(q.get("z", 0.0))
	var dim_x: float = float(q.get("dim_x", 1.0))
	var dim_z: float = float(q.get("dim_z", 1.0))
	return float(lx) >= qx and float(lx) < qx + dim_x and float(lz) >= qz and float(lz) < qz + dim_z


func _column_local_signature(q: Dictionary, lx: int, lz: int) -> String:
	## Normalize greedy merges to the column-local 1×1 slice (macro vs micro parity).
	return "%d|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%d" % [
		int(q.get("face_code", -1)),
		float(lx),
		float(q.get("y", 0.0)),
		float(lz),
		1.0,
		float(q.get("dim_y", 1.0)),
		1.0,
		int(q.get("type", 0)),
	]


func _signatures_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]) != str(b[i]):
			return false
	return true