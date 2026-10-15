extends SceneTree

const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
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
	var keys := [
		"wx", "wz", "chunk", "voxel_id", "visual_id", "surface_height", "walkable_height",
		"collision_bounds", "mesh_bounds", "orientation_yaw", "material", "owning_chunk",
		"origin", "package_ready", "streamed", "has_crystal", "is_water",
		"chunk_lifecycle", "column_source",
		"has_ramp", "node_path",
		"gameplay_coord", "visual_coord", "rendered_aabb", "collision_exists",
		"interactable", "terrain_layer", "discrepancies",
		"neighbors", "water_sim", "mesh_current", "collision_current", "column_face_codes",
	]
	var world = load("res://world/InfiniteNoiseWorld.gd").new(21)
	root.add_child(world)
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	_TerrainEdits.build_wall(4, 5, 20)
	var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, 4, 5, world, null, null)
	if not bool(snap.get("ok", false)):
		_fail("inspect_cell failed")
		_finish()
		return
	var missing: PackedStringArray = PackedStringArray()
	for k in keys:
		if not snap.has(k):
			missing.append(k)
	if not missing.is_empty():
		_fail("missing keys %s" % ",".join(missing))
	else:
		_ok("inspect_cell keys present wx=%s tile=%s origin=%s" % [
			str(snap.wx), str(snap.voxel_id), str(snap.origin)
		])
	if float(snap.get("height_delta", 0.0)) == 0.0:
		_fail("live edit height_delta not visible")
	else:
		_ok("live edit visible height_delta=%.2f" % float(snap.height_delta))
	if int(snap.get("wx", -1)) != 4 or int(snap.get("wz", -1)) != 5:
		_fail("cell coords")
	else:
		_ok("cell coords match")

	var script := load("res://ui/live_world_inspector.gd")
	if script == null:
		_fail("inspector script missing")
	else:
		var layer := CanvasLayer.new()
		layer.set_script(script)
		root.add_child(layer)
		await process_frame
		if not layer.has_method("_on_toggle"):
			_fail("inspector missing toggles")
		else:
			var expected_toggles := [
				"collision_shapes", "voxel_boundaries", "chunk_boundaries", "mesh_bounds",
				"walkable_surface", "terrain_height", "feature_anchors", "water_cells",
				"crystal_cells", "stream_bake_state",
			]
			var tog: Dictionary = layer.toggles if "toggles" in layer else {}
			var miss_t := 0
			for t in expected_toggles:
				if not tog.has(t):
					miss_t += 1
			if miss_t > 0:
				_fail("toggle set incomplete")
			else:
				_ok("inspector toggles present")
		if FileAccess.file_exists("res://LIVE_WORLD_ARCHITECTURE_AUDIT.md"):
			_ok("architecture audit present")
		else:
			_fail("architecture audit missing")
		layer.panel_open = true
		layer.pin_cell = Vector2i(4, 5)
		var status_a := str(layer._status.text) if layer._status else ""
		if status_a != "PINNED 4,5":
			_fail("pin did not refresh before the next frame: %s" % status_a)
		elif int(layer.last_snapshot.get("wx", -1)) != 4 or int(layer.last_snapshot.get("wz", -1)) != 5:
			_fail("pin snapshot mismatch %s" % str(layer.last_snapshot.get("wx")))
		else:
			_ok("pin refreshes label immediately")
		layer.pin_cell = Vector2i(6, 5)
		var status_b := str(layer._status.text) if layer._status else ""
		if status_b != "PINNED 6,5":
			_fail("pin leftover from previous cell: %s" % status_b)
		elif layer._shown_cell != Vector2i(6, 5):
			_fail("shown cell leftover %s" % str(layer._shown_cell))
		else:
			_ok("pin replace drops previous cell before next frame")
		await process_frame
		var status_c := str(layer._status.text) if layer._status else ""
		if status_c != "PINNED 6,5":
			_fail("process frame reverted pin to %s" % status_c)
		else:
			_ok("pin holds across the next process frame")

	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Live world inspector FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All live world inspector tests OK")
