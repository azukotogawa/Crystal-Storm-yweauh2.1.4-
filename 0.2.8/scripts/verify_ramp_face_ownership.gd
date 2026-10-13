extends SceneTree
## Regression: ramp face ownership + cross-border sealing in _side_wall_spec().
## - Parallel cardinal landings must not emit interior seam faces.
## - Same-height full voxels beside a landing keep their exposed fill face.
## - A same-height cut across a chunk border still exposes the full voxel's face.

const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_TOP := 0
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6
const FACE_RAMP := 7

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var layer: float = _WorldSettings.get_active().layer_height()
	_test_parallel_pair_no_seam(layer)
	_test_cross_border_fill(layer)

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if _failed:
		print("Ramp face ownership tests FAILED")
		quit(1)
		return
	print("All ramp face ownership tests OK")
	quit(0)


func _mk_data() -> ChunkData:
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	return _ChunkData.new(Vector2i(0, 0), world)


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


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)


func _landing_entry(data: ChunkData, cell: Vector2i) -> Dictionary:
	var e: Dictionary = data.get_ramp_entry(cell.x, cell.y)
	if e.is_empty() or bool(e.get("approach", false)) or bool(e.get("corner", false)):
		return {}
	return e


func _has_side_quad(
	quads: Array, fc_wanted: int, owner: Vector2i, y_wanted: float
) -> bool:
	for q_v in quads:
		var q: Dictionary = q_v
		if int(q.get("face_code", -1)) != fc_wanted:
			continue
		if Vector2i(int(q.get("x", -999)), int(q.get("z", -999))) != owner:
			continue
		if absf(float(q.get("y", -1.0)) - y_wanted) > 0.01:
			continue
		if absf(float(q.get("dim_y", -1.0)) - 1.0) > 0.01:
			continue
		return true
	return false


func _seam_quads_between(quads: Array, a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	for q_v in quads:
		var q: Dictionary = q_v
		var fc := int(q.get("face_code", -1))
		if fc < FACE_NEG_X or fc > FACE_POS_Z:
			continue
		var qx := int(q.get("x", -999))
		var qz := int(q.get("z", -999))
		var dx := maxi(1, int(round(float(q.get("dim_x", 1.0)))))
		var dz := maxi(1, int(round(float(q.get("dim_z", 1.0)))))
		var cols: Array = []
		if fc == FACE_POS_X or fc == FACE_NEG_X:
			for cx in range(qx, qx + dx):
				cols.append(Vector2i(cx, qz))
		else:
			for cz in range(qz, qz + dz):
				cols.append(Vector2i(qx, cz))
		for c_v in cols:
			var c: Vector2i = c_v
			var n: Vector2i
			if fc == FACE_POS_X:
				n = c + Vector2i(1, 0)
			elif fc == FACE_NEG_X:
				n = c + Vector2i(-1, 0)
			elif fc == FACE_POS_Z:
				n = c + Vector2i(0, 1)
			else:
				n = c + Vector2i(0, -1)
			if (c == a and n == b) or (c == b and n == a):
				out.append(q)
				break
	return out


func _test_parallel_pair_no_seam(layer: float) -> void:
	print("--- parallel pair ---")
	var data := _mk_data()
	_fill(data, 10.0)
	for x in range(3, 10):
		for z in range(0, 6):
			data.surface_map[x][z] = 12.0
	data.capture_worker_snapshot()
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var pair_a := Vector2i(5, 5)
	var pair_b := Vector2i(6, 5)
	for cell in [pair_a, pair_b]:
		var e: Dictionary = _landing_entry(data, cell)
		if e.is_empty():
			_fail("expected parallel landing at %s" % str(cell))
			return
		if Vector2i(e.get("dir", Vector2i.ZERO)) != Vector2i(0, 1):
			_fail("landing %s must slope south, got %s" % [str(cell), str(e.get("dir"))])
		var has_face := false
		for q_v in quads:
			var q: Dictionary = q_v
			if int(q.get("face_code", -1)) != FACE_RAMP:
				continue
			if Vector2i(int(q.get("x", -9)), int(q.get("z", -9))) == cell:
				has_face = true
				break
		if not has_face:
			_fail("missing FACE_RAMP on landing %s" % str(cell))

	var seams := _seam_quads_between(quads, pair_a, pair_b)
	if not seams.is_empty():
		_fail("interior seam faces between parallel landings (%d,%d): got %d"
				% [pair_a.x, pair_a.y, seams.size()])
	else:
		print("OK parallel pair emits no interior seam faces")

	for fv in [Vector2i(4, 5), Vector2i(8, 5)]:
		var e2: Dictionary = data.get_ramp_entry(fv.x, fv.y)
		if not e2.is_empty() and not bool(e2.get("approach", false)):
			_fail("fixture assumes %s is a full voxel, found ramp entry %s" % [str(fv), str(e2)])
			return
	var flank_west := _has_side_quad(quads, FACE_POS_X, Vector2i(4, 5), 12.0)
	var flank_east := _has_side_quad(quads, FACE_NEG_X, Vector2i(8, 5), 12.0)
	if not flank_west or not flank_east:
		_fail("same-height full-voxel flanks lost their faces west=%s east=%s"
				% [str(flank_west), str(flank_east)])
	else:
		print("OK same-height full-voxel flank faces preserved")

	var top_kept := false
	for q_v in quads:
		var q: Dictionary = q_v
		if int(q.get("face_code", -1)) != FACE_TOP:
			continue
		var qx := int(q.get("x", -999))
		var qz := int(q.get("z", -999))
		if qx <= 6 and 6 < qx + maxi(1, int(round(float(q.get("dim_x", 1.0))))) \
				and qz <= 6 and 6 < qz + maxi(1, int(round(float(q.get("dim_z", 1.0))))) \
				and absf(float(q.get("y", -1.0)) - 10.0) < 0.01:
			top_kept = true
			break
	if not top_kept:
		_fail("approach (6,6) lost its terrain top")
	else:
		print("OK approach keeps terrain top")


func _test_cross_border_fill(layer: float) -> void:
	print("--- cross-border fill ---")
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100

	var data := _mk_data()
	_fill(data, 10.0)
	for z in range(0, 9):
		data.surface_map[15][z] = 12.0
	data.capture_worker_snapshot()
	_stamp_halo(data, {Vector2i(16, 5): 12.0})

	var spec: Dictionary = cm._side_wall_spec(data, 15, 5, 16, 5, Vector2i(1, 0))
	if spec.is_empty():
		_fail("cross-border same-height cut must expose the edge voxel's face")
	elif absf(float(spec.get("y", -1.0)) - 12.0) > 0.01:
		_fail("cross-border fill starts at neighbor base, got y=%s" % str(spec.get("y")))
	else:
		print("OK cross-border same-height cut fills the edge face")

	data.set_ramp_cardinal(15, 5, Vector2i(0, 1))
	var spec_owned: Dictionary = cm._side_wall_spec(data, 15, 5, 16, 5, Vector2i(1, 0))
	if not spec_owned.is_empty():
		_fail("ramp-owned column must skip an unprovable far cut")
	else:
		print("OK ramp-owned column skips when no far landing is provable")

	_test_cross_border_ownership(cm)


func _stamp_halo(data: ChunkData, heights: Dictionary) -> void:
	var dim: int = _ChunkData.SIZE + 2 * _ChunkData.HALO
	data._has_halo_surface = true
	data._halo_surface.resize(dim)
	for ix in dim:
		var col: Array = []
		col.resize(dim)
		col.fill(10.0)
		data._halo_surface[ix] = col
	for k_v in heights.keys():
		var cell: Vector2i = k_v
		data._halo_surface[cell.x + _ChunkData.HALO][cell.y + _ChunkData.HALO] = \
				float(heights[k_v])


## Cross-border ownership via deterministic far-landing evaluation:
## anti-parallel far slope seals the crossing gap; parallel stays unfilled.
func _test_cross_border_ownership(cm: ChunkManager) -> void:
	var data_x := _mk_data()
	_fill(data_x, 10.0)
	for z in range(0, 10):
		data_x.surface_map[15][z] = 12.0
	data_x.set_ramp_cardinal(15, 5, Vector2i(0, 1))
	data_x.capture_worker_snapshot()
	# Far cardinal slopes north (anti-parallel): step-down (16,4), back (16,6).
	_stamp_halo(data_x, {Vector2i(16, 5): 12.0, Vector2i(16, 6): 12.0})
	var spec_x: Dictionary = cm._side_wall_spec(data_x, 15, 5, 16, 5, Vector2i(1, 0))
	if spec_x.is_empty():
		_fail("cross-border anti-parallel cardinal must seal the crossing gap")
	else:
		print("OK cross-border anti-parallel seal emitted")

	var data_p := _mk_data()
	_fill(data_p, 10.0)
	for z in range(0, 10):
		data_p.surface_map[15][z] = 12.0
	data_p.set_ramp_cardinal(15, 5, Vector2i(0, 1))
	data_p.capture_worker_snapshot()
	# Far cardinal slopes south (parallel): step-down (16,6), back (16,4).
	_stamp_halo(data_p, {Vector2i(16, 5): 12.0, Vector2i(16, 4): 12.0})
	var spec_p: Dictionary = cm._side_wall_spec(data_p, 15, 5, 16, 5, Vector2i(1, 0))
	if not spec_p.is_empty():
		_fail("cross-border parallel cardinal must stay unfilled")
	else:
		print("OK cross-border parallel cardinal skipped")
