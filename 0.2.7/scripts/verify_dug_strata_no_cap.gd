extends SceneTree
## Regression: dug strata mesh must not cap at natural height; micro-on must match micro-off.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const FACE_TOP := 0
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 4242
	var layer: float = _WorldSettings.get_active().layer_height()

	_TerrainEdits.reset()
	if not _check_single_layer_dig(world, layer):
		failed = true

	_TerrainEdits.reset()
	if not _check_multi_layer_dig_parity(world, layer, 8, 8, 2):
		failed = true

	_TerrainEdits.reset()
	world = null

	if failed:
		quit(1)
	print("OK dug strata no natural cap")
	quit(0)


func _check_single_layer_dig(world: InfiniteNoiseWorld, layer: float) -> bool:
	var dig_wx := 3
	var dig_wz := 5
	var natural_h: float = world.get_surface_height_worker(float(dig_wx), float(dig_wz), 0.0)
	if not _TerrainEdits.dig(dig_wx, dig_wz, 1):
		push_error("dig failed at (%d,%d)" % [dig_wx, dig_wz])
		return false

	var edited_h: float = world.get_surface_height_worker(
		float(dig_wx), float(dig_wz), _TerrainEdits.get_height_delta(dig_wx, dig_wz)
	)
	if edited_h >= natural_h - layer * 0.05:
		push_error("dig should lower surface natural=%.2f edited=%.2f" % [natural_h, edited_h])
		return false

	var coord := Vector2i(
		floori(float(dig_wx) / float(_ChunkData.SIZE)),
		floori(float(dig_wz) / float(_ChunkData.SIZE))
	)
	var lx := dig_wx - coord.x * _ChunkData.SIZE
	var lz := dig_wz - coord.y * _ChunkData.SIZE

	var data := _ChunkData.new(coord, world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)

	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	if not _dug_top_ok(mesh.get("quads", []), lx, lz, natural_h, edited_h, "micro-off"):
		return false
	print("OK dug mesh top at edited=%.2f (natural was %.2f)" % [edited_h, natural_h])

	_ChunkData.set_micro_enabled_for_benchmark(true)
	data.derive_micro_from_terrain_edits()
	if not data.has_micro_brick(lx, lz):
		push_error("micro brick missing on dug column (%d,%d)" % [lx, lz])
		return false

	var combined_mesh: Dictionary = cm._build_mesh(data)
	var combined: Array = combined_mesh.get("quads", [])
	var off_tops: Array = _top_ys_at_column(mesh.get("quads", []), lx, lz)
	var on_tops: Array = _top_ys_at_column(combined, lx, lz)
	if not _dug_top_ok(combined, lx, lz, natural_h, edited_h, "micro-on"):
		return false
	if not _arrays_equal(off_tops, on_tops):
		push_error("micro-on top Y mismatch single-layer off=%s on=%s" % [str(off_tops), str(on_tops)])
		return false
	var sides_off := _count_dig_sides(mesh.get("quads", []), lx, lz)
	var sides_on := _count_dig_sides(combined, lx, lz)
	if sides_off != sides_on:
		push_error("micro-on side count mismatch off=%d on=%d" % [sides_off, sides_on])
		return false
	print("OK micro-on single-layer parity tops=%s sides=%d" % [str(on_tops), sides_on])
	return true


func _check_multi_layer_dig_parity(
	world: InfiniteNoiseWorld,
	layer: float,
	dig_wx: int,
	dig_wz: int,
	layers: int
) -> bool:
	var natural_h: float = world.get_surface_height_worker(float(dig_wx), float(dig_wz), 0.0)
	if not _TerrainEdits.dig(dig_wx, dig_wz, layers):
		push_error("dig %d layers failed at (%d,%d)" % [layers, dig_wx, dig_wz])
		return false

	var edited_h: float = world.get_surface_height_worker(
		float(dig_wx), float(dig_wz), _TerrainEdits.get_height_delta(dig_wx, dig_wz)
	)
	if edited_h >= natural_h - float(layers) * layer * 0.95:
		push_error(
			"%d-layer dig should lower surface natural=%.2f edited=%.2f"
			% [layers, natural_h, edited_h]
		)
		return false

	var coord := Vector2i(
		floori(float(dig_wx) / float(_ChunkData.SIZE)),
		floori(float(dig_wz) / float(_ChunkData.SIZE))
	)
	var lx := dig_wx - coord.x * _ChunkData.SIZE
	var lz := dig_wz - coord.y * _ChunkData.SIZE

	var data := _ChunkData.new(coord, world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)

	var cm := _ChunkManager.new()
	_ChunkData.set_micro_enabled_for_benchmark(false)
	var off_mesh: Dictionary = cm._build_mesh(data)
	var off_quads: Array = off_mesh.get("quads", [])
	if not _dug_top_ok(off_quads, lx, lz, natural_h, edited_h, "micro-off-%dl" % layers):
		return false

	var off_tops: Array = _top_ys_at_column(off_quads, lx, lz)
	if off_tops.size() < 2:
		push_error(
			"micro-off %d-layer dig at (%d,%d) expected >=2 FACE_TOP ys got %s"
			% [layers, dig_wx, dig_wz, str(off_tops)]
		)
		return false

	_ChunkData.set_micro_enabled_for_benchmark(true)
	data.derive_micro_from_terrain_edits()
	if not data.has_micro_brick(lx, lz):
		push_error("micro brick missing on %d-layer dug column (%d,%d)" % [layers, lx, lz])
		return false

	var on_mesh: Dictionary = cm._build_mesh(data)
	var on_quads: Array = on_mesh.get("quads", [])
	if not _dug_top_ok(on_quads, lx, lz, natural_h, edited_h, "micro-on-%dl" % layers):
		return false

	var on_tops: Array = _top_ys_at_column(on_quads, lx, lz)
	if not _arrays_equal(off_tops, on_tops):
		push_error(
			"micro-on %d-layer top Y mismatch at (%d,%d) off=%s on=%s"
			% [layers, dig_wx, dig_wz, str(off_tops), str(on_tops)]
		)
		return false

	var off_sides := _count_dig_sides(off_quads, lx, lz)
	var on_sides := _count_dig_sides(on_quads, lx, lz)
	if off_sides != on_sides:
		push_error(
			"micro-on %d-layer side mismatch at (%d,%d) off=%d on=%d"
			% [layers, dig_wx, dig_wz, off_sides, on_sides]
		)
		return false

	print(
		"OK micro-on %d-layer dig parity at (%d,%d) tops=%s sides=%d"
		% [layers, dig_wx, dig_wz, str(on_tops), on_sides]
	)
	return true


func _top_ys_at_column(quads: Array, lx: int, lz: int) -> Array:
	var ys: Array = []
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_TOP:
			continue
		var qx: float = float(q.get("x", 0.0))
		var qz: float = float(q.get("z", 0.0))
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		if float(lx) >= qx and float(lx) < qx + dim_x and float(lz) >= qz and float(lz) < qz + dim_z:
			ys.append(float(q.get("y", -999.0)))
	ys.sort()
	return ys


func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true


func _dug_top_ok(quads: Array, lx: int, lz: int, natural_h: float, edited_h: float, label: String) -> bool:
	var cap_at_natural := false
	var top_at_edited := false
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_TOP:
			continue
		var qx: float = float(q.get("x", 0.0))
		var qz: float = float(q.get("z", 0.0))
		var qy: float = float(q.get("y", -999.0))
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		var covers_dig := float(lx) >= qx and float(lx) < qx + dim_x \
				and float(lz) >= qz and float(lz) < qz + dim_z
		if not covers_dig:
			continue
		if is_equal_approx(qy, natural_h):
			cap_at_natural = true
		if is_equal_approx(qy, edited_h):
			top_at_edited = true
	if cap_at_natural:
		push_error("%s: dug column still has FACE_TOP cap at natural_h=%.2f" % [label, natural_h])
		return false
	if not top_at_edited:
		push_error("%s: dug column missing FACE_TOP at edited_h=%.2f" % [label, edited_h])
		return false
	return true


func _count_dig_sides(quads: Array, lx: int, lz: int) -> int:
	var count := 0
	for q in quads:
		var fc: int = int(q.get("face_code", -1))
		if fc < FACE_NEG_X or fc > FACE_POS_Z:
			continue
		var qx: float = float(q.get("x", 0.0))
		var qz: float = float(q.get("z", 0.0))
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		if float(lx) >= qx and float(lx) < qx + dim_x and float(lz) >= qz and float(lz) < qz + dim_z:
			count += 1
	return count