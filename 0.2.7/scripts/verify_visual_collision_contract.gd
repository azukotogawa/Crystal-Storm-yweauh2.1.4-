extends SceneTree
## Shared visual / collision contract: face codes, incremental clip, WorldObject, coords.

const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _StructureOrientation = preload("res://helpers/structure_orientation.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

var _failed: int = 0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(m: String) -> void:
	_failed += 1
	push_error(m)
	print("FAIL: %s" % m)


func _ok(m: String) -> void:
	print("OK %s" % m)


func _run() -> void:
	_test_coords()
	_test_face_codes()
	_test_clip()
	_test_world_object()
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Visual collision contract FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All visual collision contract tests OK")


func _test_coords() -> void:
	var vs: float = _WorldVisualCoords.voxel_scale()
	var p: Vector3 = _WorldVisualCoords.cell_center(3, 10.0, 4)
	if absf(p.x - (3.5 * vs)) > 0.001 or absf(p.z - (4.5 * vs)) > 0.001:
		_fail("cell_center not scaled by voxel_scale")
	else:
		_ok("cell_center uses voxel_scale=%.2f" % vs)
	var a: AABB = _WorldVisualCoords.cell_aabb(3, 8.0, 4, 10.0)
	if absf(a.size.x - vs) > 0.001 or absf(a.size.z - vs) > 0.001:
		_fail("cell_aabb XZ must be voxel_scale, got %s" % a.size)
	else:
		_ok("cell_aabb XZ=%.2f" % a.size.x)
	if _WorldVisualCoords.FACE_TOP != 0 or _WorldVisualCoords.FACE_POS_X != 4:
		_fail("face code contract drifted")
	else:
		_ok("face codes match shader contract")


func _test_face_codes() -> void:
	var world = load("res://world/InfiniteNoiseWorld.gd").new(42)
	root.add_child(world)
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])
	var bad := 0
	var tops := 0
	var sides := 0
	for q_v in quads:
		var q: Dictionary = q_v
		var fc: int = int(q.get("face_code", -1))
		var dy: float = float(q.get("dim_y", 1.0))
		# Y-greedy surface slabs must be FACE_TOP, never a side code on a 1-layer top box.
		if fc == _WorldVisualCoords.FACE_POS_X or fc == _WorldVisualCoords.FACE_POS_Z:
			if float(q.get("dim_x", 1.0)) > 1.01 and float(q.get("dim_z", 1.0)) > 1.01 and dy >= 0.99:
				bad += 1
		if fc == _WorldVisualCoords.FACE_TOP:
			tops += 1
		elif fc >= _WorldVisualCoords.FACE_NEG_X and fc <= _WorldVisualCoords.FACE_POS_Z:
			sides += 1
	if bad > 0:
		_fail("surface slabs stamped with side face_codes (%d)" % bad)
	elif tops < 1:
		_fail("mesh missing FACE_TOP quads")
	else:
		_ok("mesh face codes tops=%d sides=%d bad_slabs=%d" % [tops, sides, bad])
	cm.free()


func _test_clip() -> void:
	var cm := _ChunkManager.new()
	var slab := {
		"x": 0, "y": 8.0, "z": 0,
		"dim_x": 16.0, "dim_y": 1.0, "dim_z": 16.0,
		"uv_w": 16.0, "uv_h": 16.0,
		"type": _VoxelTypes.GRASSLAND, "face_code": _ChunkManager.FACE_TOP,
	}
	var hole := Rect2i(6, 6, 5, 5)
	var kept: Array = cm._clip_quad_outside_rect(slab, hole)
	var covered := {}
	for k_v in kept:
		var k: Dictionary = k_v
		var x0 := int(k.x)
		var z0 := int(k.z)
		var dx := int(round(float(k.dim_x)))
		var dz := int(round(float(k.dim_z)))
		for x in range(x0, x0 + dx):
			for z in range(z0, z0 + dz):
				covered[Vector2i(x, z)] = true
	var missing := 0
	var leaked := 0
	for x in 16:
		for z in 16:
			var inside := x >= 6 and x < 11 and z >= 6 and z < 11
			if inside and covered.has(Vector2i(x, z)):
				leaked += 1
			if not inside and not covered.has(Vector2i(x, z)):
				missing += 1
	if missing > 0 or leaked > 0:
		_fail("clip coverage missing=%d leaked=%d kept=%d" % [missing, leaked, kept.size()])
	else:
		_ok("clip keeps exterior kept=%d" % kept.size())
	cm.free()


func _test_world_object() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	_FeatureRegistry.register_feature(2, 3, 0, {
		"build_id": "gate",
		"is_passage": true,
		"player_built": true,
	})
	_StructureOrientation.persist_yaw(2, 3)
	var feat: Dictionary = _FeatureRegistry.get_feature(2, 3)
	if not feat.has("yaw"):
		_fail("structure yaw not stored on feature")
	else:
		_ok("structure yaw stored %.2f" % float(feat.yaw))
	var packed: PackedScene = load("res://scenes/world_object.tscn")
	if packed == null:
		_fail("world_object.tscn missing")
		return
	var obj = packed.instantiate()
	root.add_child(obj)
	if not obj.has_method("bind"):
		_fail("WorldObject missing bind")
	else:
		obj.bind(2, 3, "gate", feat, null, null, null, null, Vector3(1, 2, 1), 0.0)
		if str(obj.get_meta("building_visual_id", "")) != "gate":
			_fail("WorldObject visual id")
		elif obj.get_node_or_null("Mesh") == null:
			_fail("WorldObject missing Mesh")
		elif obj.get_node_or_null("GameplayBounds/CollisionShape3D") == null:
			_fail("WorldObject missing gameplay bounds")
		else:
			_ok("WorldObject scene bind path=%s" % obj.name)
	obj.queue_free()
