extends SceneTree
## Regression: cardinal ramp back support must not meet another cardinal landing side.

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 0
	_TerrainRamps.invalidate_mesh_cache()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i.ZERO, world)
	var cm := _ChunkManager.new()
	var layer: float = _WorldSettings.get_active().layer_height()
	var high := 10.0
	var low := high - layer
	_init_flat_maps(data, low)

	var ramp_a := Vector2i(6, 6)
	var dir_a := Vector2i(-1, 0)
	var ramp_b := Vector2i(6, 5)
	var dir_b := Vector2i(0, -1)
	_set_high(data, [
		ramp_a,
		Vector2i(7, 6), # Ramp A back support.
		Vector2i(6, 7), # Ramp A side; keeps the approach out of corner classification.
		ramp_b,
		Vector2i(7, 5), # Ramp B side/back support for its alternate local west step.
	], high)

	var valid_a := Vector2i(10, 10)
	var valid_dir_a := Vector2i(-1, 0)
	var valid_b := Vector2i(11, 9)
	var valid_dir_b := Vector2i(0, -1)
	_set_high(data, [
		valid_a,
		valid_b,
		Vector2i(11, 10), # Shared plateau support, not either ramp's landing.
		Vector2i(10, 9),
	], high)

	if not cm._cardinal_dir_is_topologically_valid(data, ramp_a.x, ramp_a.y, dir_a):
		_fail("Ramp A must be individually valid before inter-cardinal pruning")
	if not cm._cardinal_dir_is_topologically_valid(data, ramp_b.x, ramp_b.y, dir_b):
		_fail("Ramp B must be individually valid before inter-cardinal pruning")
	if cm._is_inner_corner_low_at(data, 5, 6) or cm._is_inner_corner_low_at(data, 6, 4):
		_fail("Back-to-side fixture must not rely on corner rejection")
	if ramp_a + dir_a == ramp_b or ramp_b + dir_b == ramp_a:
		_fail("Back-to-side fixture must not rely on approach landing rejection")
	if cm._has_opposing_plateau_across_valley(data, ramp_a.x, ramp_a.y, dir_a):
		_fail("Ramp A fixture must not rely on V-valley rejection")
	if cm._has_opposing_plateau_across_valley(data, ramp_b.x, ramp_b.y, dir_b):
		_fail("Ramp B fixture must not rely on V-valley rejection")

	var planned := {
		ramp_a: dir_a,
		ramp_b: dir_b,
	}
	cm._drop_opposing_cardinals(planned, data)
	if planned.has(ramp_a) and planned.has(ramp_b):
		_fail("Back-to-side cardinal pair must be rejected by inter-cardinal pruning")
	else:
		print("OK back-to-side pair rejected by inter-cardinal pruning")

	_register_forced_cardinal(ramp_a, dir_a)
	_register_forced_cardinal(ramp_b, dir_b)
	_register_forced_cardinal(valid_a, valid_dir_a)
	_register_forced_cardinal(valid_b, valid_dir_b)
	data.capture_worker_snapshot()
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var invalid_entries := _landing_entry_count(data, ramp_a, ramp_b)
	var invalid_faces := _ramp_face_count(quads, ramp_a, ramp_b)
	if invalid_entries > 1:
		_fail("Final ramp_map must not contain both back-to-side landings, got %d" % invalid_entries)
	elif invalid_faces > 1:
		_fail("Back-to-side pair must emit at most one FACE_RAMP, got %d" % invalid_faces)
	else:
		print("OK final back-to-side pair entries=%d faces=%d" % [invalid_entries, invalid_faces])

	var valid_entries := _landing_entry_count(data, valid_a, valid_b)
	var valid_faces := _ramp_face_count(quads, valid_a, valid_b)
	if valid_entries != 2 or valid_faces != 2:
		_fail("Valid perpendicular non-back-to-side pair must survive, entries=%d faces=%d" % [valid_entries, valid_faces])
	else:
		print("OK valid perpendicular non-back-to-side pair survives")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	if _failed:
		quit(1)
	else:
		print("Ramp back-to-side topology regression OK")
		quit(0)


func _register_forced_cardinal(cell: Vector2i, dir: Vector2i) -> void:
	_FeatureRegistry.register_feature(cell.x, cell.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": "cardinal_ramp",
		"player_built": true,
		"dir": dir,
	})


func _landing_entry_count(data: ChunkData, a: Vector2i, b: Vector2i) -> int:
	var count := 0
	for cell in [a, b]:
		var entry: Dictionary = data.get_ramp_entry(cell.x, cell.y)
		if not entry.is_empty() and not bool(entry.get("approach", false)):
			count += 1
	return count


func _ramp_face_count(quads: Array, a: Vector2i, b: Vector2i) -> int:
	var count := 0
	for q_variant in quads:
		var q: Dictionary = q_variant
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		var cell := Vector2i(int(q.get("x", -1)), int(q.get("z", -1)))
		if cell == a or cell == b:
			count += 1
	return count


func _init_flat_maps(data: ChunkData, height: float) -> void:
	data.surface_map.resize(_ChunkData.SIZE)
	data.tile_map.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data.surface_map[x] = []
		data.tile_map[x] = []
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = height
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND


func _set_high(data: ChunkData, cells: Array, height: float) -> void:
	for cell_v in cells:
		var cell: Vector2i = cell_v
		data.surface_map[cell.x][cell.y] = height
		data.tile_map[cell.x][cell.y] = _VoxelTypes.GRASSLAND


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
