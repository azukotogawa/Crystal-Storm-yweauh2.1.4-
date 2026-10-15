extends SceneTree

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 0

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i.ZERO, world)
	var cm := _ChunkManager.new()
	var low := Vector2i(6, 6)
	var da := Vector2i(1, 0)
	var db := Vector2i(0, 1)
	var layer: float = _WorldSettings.get_active().layer_height()
	_init_flat_maps(data, 10.0)
	_set_corner_supports(data, low, da, db, 10.0 + layer)
	_FeatureRegistry.register_feature(low.x, low.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": "corner_ramp",
		"player_built": true,
		"corner": true,
		"dir": da,
		"dir2": db,
	})

	data.capture_worker_snapshot()
	var case_a: Dictionary = cm._build_mesh(data)
	_expect_corner(data, case_a.get("quads", []), low, true, "case A valid supports")

	data.surface_map[low.x + da.x + db.x][low.y + da.y + db.y] = 10.0
	data.capture_worker_snapshot()
	var case_b: Dictionary = cm._build_mesh(data)
	_expect_corner(data, case_b.get("quads", []), low, false, "case B missing diagonal support")
	if _FeatureRegistry.get_feature(low.x, low.y).get("build_id", "") != "corner_ramp":
		_fail("case B must retain FeatureRegistry intent")
	if not data.get_ramp_entry(low.x, low.y).is_empty():
		_fail("case B must not expose a ramp entry to VoxelFloorProbe")

	data.surface_map[low.x + da.x + db.x][low.y + da.y + db.y] = 10.0 + layer
	data.capture_worker_snapshot()
	var case_c: Dictionary = cm._build_mesh(data)
	_expect_corner(data, case_c.get("quads", []), low, true, "case C restored support")

	_TerrainRamps.placement_chance = old_chance
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	if _failed:
		quit(1)
	else:
		print("Forced ramp topology regression OK")
		quit(0)


func _expect_corner(data: ChunkData, quads: Array, low: Vector2i, expected: bool, label: String) -> void:
	var has_entry: bool = data.is_ramp_corner(low.x, low.y)
	var ramp_faces := 0
	for q_variant in quads:
		var q: Dictionary = q_variant
		if int(q.get("x", -1)) != low.x or int(q.get("z", -1)) != low.y:
			continue
		var face: int = int(q.get("face_code", -1))
		if face == FACE_RAMP or face == FACE_RAMP_CORNER:
			ramp_faces += 1
	if expected:
		if not has_entry or ramp_faces != 1:
			_fail("%s: expected exactly one corner ramp, entry=%s faces=%d" % [label, has_entry, ramp_faces])
		else:
			print("OK %s" % label)
	elif has_entry or ramp_faces != 0:
		_fail("%s: stale forced ramp survived, entry=%s faces=%d" % [label, has_entry, ramp_faces])
	else:
		print("OK %s rejected stale feature")


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


func _set_corner_supports(data: ChunkData, low: Vector2i, da: Vector2i, db: Vector2i, high: float) -> void:
	data.surface_map[low.x + da.x][low.y + da.y] = high
	data.surface_map[low.x + db.x][low.y + db.y] = high
	data.surface_map[low.x + da.x + db.x][low.y + da.y + db.y] = high


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
