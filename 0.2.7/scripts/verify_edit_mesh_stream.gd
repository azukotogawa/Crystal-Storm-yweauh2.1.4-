extends SceneTree
## Live main.tscn: player-edit → mesh → stream consistency.
## Drives TerrainEditor try_dig / try_build (not surface-map stamps).
## Writes {SCRATCH}/edit_mesh_stream.json (or CRYSTALSTORM_EDIT_DUMP).

const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldState = preload("res://world/world_state.gd")


var _failed: int = 0
var _steps: Array = []
var _cells: Dictionary = {}
var _scratch: String = ""
var _windowed: bool = false
var _game: Node = null


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-9b036d757eb7/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	_windowed = DisplayServer.get_name() != "headless"
	print("EDIT_MESH_STREAM_START windowed=%s scratch=%s" % [str(_windowed), _scratch])

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	_game = packed.instantiate()
	root.add_child(_game)
	var compose = _game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 8:
		await process_frame

	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var editor = get_first_node_in_group("terrain_editor")
	var player = get_first_node_in_group("player")
	if cm == null or world == null or editor == null or player == null:
		_fail("missing world/chunk_manager/editor/player")
		_finish()
		return
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	if feat_layer and feat_layer.has_method("_bind_terrain_placement_refresh"):
		feat_layer._bind_terrain_placement_refresh()

	if "inventory" in player and player.inventory:
		player.inventory.add_item("stone", 64)
		player.inventory.add_item("wood", 64)
	var inv = player.inventory

	var origin := _find_dry_origin(world, cm)
	_cells = {
		"flat": origin + Vector2i(2, 2),
		"adjacent": origin + Vector2i(3, 2),
		"raised": origin + Vector2i(5, 2),
		"wall": origin + Vector2i(7, 2),
		"bridge": origin + Vector2i(9, 2),
		"gate": origin + Vector2i(11, 2),
		"boundary": _boundary_cell(origin),
	}
	print("EDIT_MESH_STREAM origin=%s cells=%s" % [str(origin), str(_cells)])

	# 1. flat break
	await _op_dig(editor, cm, "flat_break", _cells.flat)
	# 2. adjacent break
	await _op_dig(editor, cm, "adjacent_break", _cells.adjacent)
	# 3. dig under a raised column (place wall, then dig that column)
	await _op_build(editor, cm, inv, "raised_place", _cells.raised, &"stone_wall")
	await _op_dig(editor, cm, "dig_under_raised", _cells.raised)
	# 4. block placement
	await _op_build(editor, cm, inv, "wall_place", _cells.wall, &"stone_wall")
	# 5. bridge: trench then place
	await _op_dig(editor, cm, "bridge_trench", _cells.bridge)
	await _op_build(editor, cm, inv, "bridge_place", _cells.bridge, &"bridge")
	# 6. gate
	await _op_build(editor, cm, inv, "gate_place", _cells.gate, &"gate")
	# 7. remove/rebuild bridge
	await _op_remove(editor, cm, feat_layer, "bridge_remove", _cells.bridge)
	await _op_dig(editor, cm, "bridge_trench2", _cells.bridge)
	await _op_build(editor, cm, inv, "bridge_rebuild", _cells.bridge, &"bridge")
	# 8. remove/rebuild gate
	await _op_remove(editor, cm, feat_layer, "gate_remove", _cells.gate)
	await _op_build(editor, cm, inv, "gate_rebuild", _cells.gate, &"gate")
	# 9. chunk-boundary edit
	await _op_dig(editor, cm, "boundary_break", _cells.boundary)
	# 10. unload/reload the chunk that holds the wall (persistent overlay)
	await _op_unload_reload(cm, "unload_reload_wall", _cells.wall)

	_assert_sequence()
	_write_json("edit_mesh_stream.json")
	print("EDIT_MESH_STREAM failed=%d steps=%d" % [_failed, _steps.size()])
	_finish()


func _op_dig(editor, cm, name: String, cell: Vector2i) -> void:
	var world = get_first_node_in_group("world")
	var y: float = world.get_surface_height(float(cell.x), float(cell.y)) if world else 0.0
	var ok: bool = editor.try_dig(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5))
	if not ok:
		_fail("%s try_dig failed: %s" % [name, editor.last_fail_reason])
	await _idle(cm)
	await _record(name, cell, {"ok": ok, "kind": "dig"})


func _op_build(editor, cm, inv, name: String, cell: Vector2i, build_id: StringName) -> void:
	var world = get_first_node_in_group("world")
	var y: float = world.get_surface_height(float(cell.x), float(cell.y)) if world else 0.0
	var ok: bool = editor.try_build(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5), inv, build_id)
	if not ok:
		_fail("%s try_build %s failed: %s" % [name, str(build_id), editor.last_fail_reason])
	await _idle(cm)
	await _record(name, cell, {"ok": ok, "kind": "build", "build_id": str(build_id)})


func _op_remove(editor, cm, feat_layer, name: String, cell: Vector2i) -> void:
	var feat: Dictionary = _FeatureRegistry.get_feature(cell.x, cell.y)
	var raised: bool = bool(feat.get("raises_terrain", false)) and not bool(feat.get("is_bridge", false))
	_FeatureRegistry.clear_feature(cell.x, cell.y)
	_FeatureRegistry.clear_tile_override(cell.x, cell.y)
	var ws = _WorldState.get_active()
	var key := Vector2i(cell.x, cell.y)
	if ws.build_tile.has(key):
		ws.build_tile.erase(key)
		ws.bump(_WorldState.DOMAIN_TERRAIN)
	if raised and _TerrainEdits.get_height_delta(cell.x, cell.y) > 0.01:
		_TerrainEdits.dig(cell.x, cell.y, 1)
	if editor.has_method("_invalidate_and_rebuild"):
		editor._invalidate_and_rebuild(cell.x, cell.y)
	if feat_layer and feat_layer.has_method("refresh_cell"):
		feat_layer.refresh_cell(cell.x, cell.y)
		if feat_layer.has_method("_refresh_wood_wall_neighbors"):
			feat_layer._refresh_wood_wall_neighbors(cell.x, cell.y)
	await _idle(cm)
	await _record(name, cell, {"ok": true, "kind": "remove"})


func _op_unload_reload(cm, name: String, cell: Vector2i) -> void:
	var SIZE := 16
	var key := Vector2i(
		int(floor(float(cell.x) / float(SIZE))),
		int(floor(float(cell.y) / float(SIZE)))
	)
	var before_delta: float = _TerrainEdits.get_height_delta(cell.x, cell.y)
	var before_tile: int = _TerrainEdits.get_build_tile(cell.x, cell.y)
	var before_feat: Dictionary = _FeatureRegistry.get_feature(cell.x, cell.y)
	if not cm.chunks.has(key):
		_fail("%s chunk %s not resident" % [name, str(key)])
		await _record(name, cell, {"ok": false, "kind": "unload_reload", "error": "missing"})
		return
	cm._unload_chunk_view(key)
	if cm.chunks.has(key):
		_fail("%s unload left chunk resident" % name)
	cm.request_chunk(key, true)
	var waited := 0
	while waited < 180 and not cm.chunks.has(key):
		await process_frame
		waited += 1
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(120)
	# Feature visuals populate one chunk per frame after chunk_ready.
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	var appeared := 0
	while appeared < 30:
		await process_frame
		appeared += 1
		if feat_layer and feat_layer.has_method("get_anchor_at") \
				and feat_layer.get_anchor_at(cell.x, cell.y) != null:
			break
	if not cm.chunks.has(key):
		_fail("%s reload failed" % name)
	var after_delta: float = _TerrainEdits.get_height_delta(cell.x, cell.y)
	var after_tile: int = _TerrainEdits.get_build_tile(cell.x, cell.y)
	var after_feat: Dictionary = _FeatureRegistry.get_feature(cell.x, cell.y)
	if absf(after_delta - before_delta) > 0.01:
		_fail("%s height_delta lost %.2f → %.2f" % [name, before_delta, after_delta])
	if after_tile != before_tile:
		_fail("%s build_tile lost %d → %d" % [name, before_tile, after_tile])
	if str(before_feat.get("build_id", "")) != str(after_feat.get("build_id", "")):
		_fail("%s feature build_id lost" % name)
	await _record(name, cell, {
		"ok": cm.chunks.has(key),
		"kind": "unload_reload",
		"chunk": [key.x, key.y],
		"delta_before": before_delta,
		"delta_after": after_delta,
		"tile_before": before_tile,
		"tile_after": after_tile,
		"feat_before": str(before_feat.get("build_id", "")),
		"feat_after": str(after_feat.get("build_id", "")),
	})


func _idle(cm) -> void:
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(120)
	for _w in 4:
		await process_frame


func _record(name: String, cell: Vector2i, meta: Dictionary) -> void:
	var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, cell.x, cell.y)
	var extras: Dictionary = _mesh_extras(cell)
	var wo: Dictionary = _world_object_state(cell)
	var entry := {
		"op": name,
		"cell": [cell.x, cell.y],
		"meta": meta,
		"surface": snap.get("surface_height", 0.0),
		"walk": snap.get("walkable_height", 0.0),
		"height_delta": snap.get("height_delta", 0.0),
		"build_tile": snap.get("build_tile", -1),
		"build_id": snap.get("build_id", ""),
		"visual_id": snap.get("visual_id", ""),
		"feature": snap.get("feature", {}),
		"faces": snap.get("column_face_codes", []),
		"covered": snap.get("column_mesh_covered", false),
		"disc": snap.get("discrepancies", []),
		"neighbors": snap.get("neighbors", {}),
		"collision_kind": snap.get("collision_kind", ""),
		"collision_exists": snap.get("collision_exists", false),
		"yaw": snap.get("orientation_yaw", 0.0),
		"visual_yaw": snap.get("visual_yaw", 0.0),
		"structure_path": snap.get("structure_path", ""),
		"structure_count": snap.get("structure_count", 0),
		"streamed": snap.get("streamed", false),
		"chunk": snap.get("chunk", []),
		"chunk_view_path": snap.get("chunk_view_path", ""),
		"origin": snap.get("origin", ""),
		"column_source": extras.get("column_source", snap.get("column_source", "")),
		"mesh_source": extras.get("mesh_source", ""),
		"quad_count": extras.get("quad_count", 0),
		"view_id": extras.get("view_id", ""),
		"world_object": wo,
	}
	_steps.append(entry)
	var disc_s := str(entry.get("disc", []))
	print("STEP %s cell=%s covered=%s faces=%s disc=%s build=%s src=%s/%s" % [
		name, str(cell), str(entry.covered), str(entry.faces), disc_s,
		str(entry.build_id), str(entry.column_source), str(entry.mesh_source)
	])
	if _windowed:
		await _shot(name, cell)


func _mesh_extras(cell: Vector2i) -> Dictionary:
	var cm = get_first_node_in_group("chunk_manager")
	var SIZE := 16
	var key := Vector2i(
		int(floor(float(cell.x) / float(SIZE))),
		int(floor(float(cell.y) / float(SIZE)))
	)
	var out := {"column_source": "", "mesh_source": "", "quad_count": 0, "view_id": ""}
	if cm == null or not cm.chunks.has(key):
		return out
	var view = cm.chunks[key]
	if view == null:
		return out
	out["view_id"] = str(view.get_instance_id())
	var md: Dictionary = view.mesh_data if "mesh_data" in view else {}
	out["column_source"] = str(md.get("column_source", ""))
	out["mesh_source"] = str(md.get("mesh_source", ""))
	out["quad_count"] = (md.get("quads", []) as Array).size()
	return out


func _world_object_state(cell: Vector2i) -> Dictionary:
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	var out := {"present": false, "id": "", "yaw": 0.0, "mesh_yaw": 0.0, "path": ""}
	if feat_layer == null or not ("_nodes_by_cell" in feat_layer):
		return out
	var anchor = feat_layer._nodes_by_cell.get(Vector2i(cell.x, cell.y))
	if anchor == null or not is_instance_valid(anchor):
		return out
	out["present"] = true
	out["id"] = str(anchor.get_meta("building_visual_id", ""))
	if "yaw" in anchor:
		out["yaw"] = float(anchor.yaw)
	if anchor is Node and (anchor as Node).is_inside_tree():
		out["path"] = str((anchor as Node).get_path())
	var mesh: MeshInstance3D = (anchor as Node).get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		out["mesh_yaw"] = mesh.rotation.y
		out["authored"] = str(mesh.get_meta("authored_resource_path", ""))
	return out


func _assert_sequence() -> void:
	var by_op := {}
	for s_v in _steps:
		var s: Dictionary = s_v
		by_op[str(s.op)] = s
	# Terrain edits: cell + orthogonal neighbors stay mesh-covered.
	for op in ["flat_break", "adjacent_break", "dig_under_raised", "wall_place", "boundary_break"]:
		if not by_op.has(op):
			_fail("missing step %s" % op)
			continue
		_assert_covered(by_op[op], true)
	# Structures keep identity + WorldObject after place/rebuild.
	for op in ["bridge_place", "bridge_rebuild", "gate_place", "gate_rebuild", "wall_place"]:
		if not by_op.has(op):
			_fail("missing step %s" % op)
			continue
		_assert_structure(by_op[op])
	# Remove must drop WorldObject.
	for op in ["bridge_remove", "gate_remove"]:
		if not by_op.has(op):
			_fail("missing step %s" % op)
			continue
		var rem: Dictionary = by_op[op]
		if str(rem.get("build_id", "")) != "":
			_fail("%s still has build_id %s" % [op, rem.get("build_id")])
		if int(rem.get("structure_count", 0)) != 0:
			_fail("%s WorldObject still present" % op)
		else:
			_ok("%s cleared WorldObject" % op)
	# Unload/reload overlays + mesh.
	if by_op.has("unload_reload_wall"):
		var u: Dictionary = by_op["unload_reload_wall"]
		if str(u.get("build_id", "")) != "stone_wall":
			_fail("reload lost stone_wall feature")
		else:
			_ok("reload kept stone_wall overlay")
		_assert_covered(u, false)
		_assert_structure(u)
	# Rebuild identity matches first place.
	if by_op.has("bridge_place") and by_op.has("bridge_rebuild"):
		var a: Dictionary = by_op["bridge_place"]
		var b: Dictionary = by_op["bridge_rebuild"]
		if str(a.get("visual_id")) != str(b.get("visual_id")) or str(b.get("visual_id")) != "bridge":
			_fail("bridge identity changed across rebuild")
		elif absf(float(a.get("yaw", 0.0)) - float(b.get("yaw", 0.0))) > 0.05:
			_fail("bridge yaw changed across rebuild")
		else:
			_ok("bridge identity+yaw survived rebuild")
	if by_op.has("gate_place") and by_op.has("gate_rebuild"):
		var ga: Dictionary = by_op["gate_place"]
		var gb: Dictionary = by_op["gate_rebuild"]
		if str(gb.get("visual_id")) != "gate":
			_fail("gate identity lost on rebuild")
		elif absf(float(ga.get("yaw", 0.0)) - float(gb.get("yaw", 0.0))) > 0.05:
			_fail("gate yaw changed across rebuild")
		else:
			_ok("gate identity+yaw survived rebuild")


func _assert_covered(step: Dictionary, check_neighbors: bool) -> void:
	var op := str(step.get("op", ""))
	var disc: Array = step.get("disc", [])
	var holes: Array = []
	for d in disc:
		var ds := str(d)
		if ds.begins_with("MESH_HOLE"):
			holes.append(ds)
		# Ramp leftover is not this P0; ignore RAMP_VISUAL on edit cells.
		elif ds.begins_with("RAMP_VISUAL"):
			continue
		elif ds.begins_with("HEIGHT") and bool(step.get("has_ramp", false)):
			continue
	if not bool(step.get("covered", false)):
		_fail("%s edited cell not mesh-covered faces=%s disc=%s" % [
			op, str(step.get("faces", [])), str(disc)
		])
	elif not holes.is_empty():
		_fail("%s MESH_HOLE %s" % [op, str(holes)])
	else:
		_ok("%s cell covered faces=%s" % [op, str(step.get("faces", []))])
	if not check_neighbors:
		return
	var neigh: Dictionary = step.get("neighbors", {})
	for label in ["n", "e", "s", "w"]:
		var n: Dictionary = neigh.get(label, {})
		if n.is_empty():
			continue
		if not bool(n.get("covered", false)):
			_fail("%s neighbor %s uncovered faces=%s cell=%s" % [
				op, label, str(n.get("faces", [])), str(n.get("cell", []))
			])


func _assert_structure(step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	var want := str((step.get("meta", {}) as Dictionary).get("build_id", step.get("build_id", "")))
	if want.is_empty():
		want = str(step.get("build_id", ""))
	if str(step.get("visual_id", "")) != want and str(step.get("build_id", "")) != want:
		_fail("%s visual_id=%s want=%s" % [op, step.get("visual_id"), want])
	elif int(step.get("structure_count", 0)) != 1:
		_fail("%s WorldObject count=%s" % [op, str(step.get("structure_count"))])
	else:
		var wo: Dictionary = step.get("world_object", {})
		if wo.get("present", false) and absf(float(wo.get("yaw", 0.0)) - float(wo.get("mesh_yaw", 0.0))) > 0.05:
			_fail("%s WorldObject yaw %.3f != mesh %.3f" % [
				op, float(wo.get("yaw", 0.0)), float(wo.get("mesh_yaw", 0.0))
			])
		else:
			_ok("%s identity=%s yaw=%.3f" % [op, want, float(step.get("yaw", 0.0))])
	for d in step.get("disc", []):
		var ds := str(d)
		if ds.begins_with("ID:") or ds.begins_with("VISUAL_COUNT") or ds.begins_with("NODE:") or ds.begins_with("YAW:"):
			_fail("%s F4 %s" % [op, ds])


func _write_json(fname: String) -> void:
	var path := _scratch.path_join(fname)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("cannot write %s" % path)
		return
	f.store_string(JSON.stringify({
		"failed": _failed,
		"cells": _vec_dict(_cells),
		"steps": _steps,
	}, "\t"))
	f.close()
	print("WROTE %s" % path)


func _vec_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var v: Vector2i = d[k]
		out[str(k)] = [v.x, v.y]
	return out


func _find_dry_origin(world, cm) -> Vector2i:
	if world == null:
		return Vector2i(8, 8)
	for oz in range(8, 40, 4):
		for ox in range(8, 40, 4):
			var wet := false
			for dx in range(0, 16):
				for dz in range(0, 8):
					var tile: int = int(world.get_tile_type(float(ox + dx), float(oz + dz)))
					if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3, _VoxelTypes.RIVER, _VoxelTypes.WATER]:
						wet = true
						break
					if cm and not _ActionTargeting._is_solid_column(world, cm, ox + dx, oz + dz):
						wet = true
						break
				if wet:
					break
			if not wet:
				return Vector2i(ox, oz)
	return Vector2i(8, 8)


func _boundary_cell(origin: Vector2i) -> Vector2i:
	# First column of the next chunk east of origin, same dry row.
	var SIZE := 16
	var chunk_x: int = int(floor(float(origin.x + 2) / float(SIZE)))
	var wx: int = (chunk_x + 1) * SIZE
	return Vector2i(wx, origin.y + 2)


func _shot(name: String, cell: Vector2i) -> void:
	var insp = _game.get_node_or_null("LiveWorldInspector") if _game else null
	if insp:
		insp.panel_open = true
		insp.pin_cell = cell
	_look(cell.x, cell.y)
	for _i in 4:
		await process_frame
	if insp:
		insp.pin_cell = cell
	await process_frame
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _scratch.path_join("edit_%s_%d_%d.png" % [name, cell.x, cell.y])
	img.save_png(path)
	print("SHOT %s" % path)


func _look(wx: int, wz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(wx) + 0.5
	player.voxel_position.z = float(wz) - 2.2
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()
	var cam = player.get("camera")
	if cam == null:
		return
	cam.set("use_smoothing", false)
	cam.set("_scroll_lead", Vector3.ZERO)
	if cam.has_method("get_offset_from_rotation"):
		cam.set("follow_target", player.global_position)
		cam.global_position = player.global_position + cam.get_offset_from_rotation()
	if "zoom_level" in cam:
		cam.zoom_level = 14.0
		cam.size = 14.0


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All edit mesh stream tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "EDIT MESH STREAM FAILED")
