extends SceneTree
## Windowed: naturally generated ramps + real TerrainEdits.dig. Camera is truth.

const MAIN_SCENE := "res://scenes/main.tscn"
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")


var _failed: int = 0
var _scratch: String = ""


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


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961aca94c53e/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "no main")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_ProbeExit.finish_tree(self, 1, "start region not ready")
		return
	for _w in 10:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var editor = get_first_node_in_group("terrain_editor")
	if cm == null or world == null or editor == null:
		_ProbeExit.finish_tree(self, 1, "missing services")
		return
	var insp = game.get_node_or_null("LiveWorldInspector")
	if insp:
		insp.panel_open = true

	var found: Dictionary = _find_natural_ramps(cm)
	var cardinal: Vector2i = found.get("cardinal", Vector2i(-99999, 0))
	var corner: Vector2i = found.get("corner", Vector2i(-99999, 0))
	print("NATURAL_RAMPS cardinal=%s corner=%s" % [str(cardinal), str(corner)])
	if cardinal.x == -99999:
		_fail("no naturally generated cardinal ramp in resident chunks")
	else:
		_look(cardinal.x, cardinal.y)
		if insp:
			insp.pin_cell = cardinal
		for _f in 6:
			await process_frame
		var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, cardinal.x, cardinal.y)
		_shot("natural_cardinal_%d_%d" % [cardinal.x, cardinal.y])
		var faces: Array = snap.get("column_face_codes", [])
		var has7 := 7 in faces
		var geom: Dictionary = snap.get("surface_geom", {})
		print("NATURAL_CARDINAL cell=%s faces=%s has_ramp=%s covered=%s geom=%s disc=%s" % [
			str(cardinal), str(faces), str(snap.get("has_ramp")), str(snap.get("column_mesh_covered")),
			str(geom), str(snap.get("discrepancies"))
		])
		if not bool(snap.get("column_mesh_covered", false)):
			_fail("natural cardinal landing not mesh-covered")
		if not has7 and not bool(snap.get("has_ramp", false)):
			_fail("natural cardinal missing ramp identity")
		if int(geom.get("tri_count", 0)) <= 0:
			_fail("natural cardinal: ArrayMesh has no triangles in the landing column (F4 FACE_RAMP is not camera proof)")
		elif not bool(geom.get("is_slope", false)):
			_fail("natural cardinal: surface is not a slope y_span=%s" % str(geom.get("y_span")))
		var disc: PackedStringArray = snap.get("discrepancies", PackedStringArray())
		for dmsg in disc:
			if str(dmsg).begins_with("RAMP_RENDER"):
				_fail("natural cardinal %s" % dmsg)
		var dir: Vector2i = (snap.get("ramp", {}) as Dictionary).get("dir", Vector2i.ZERO)
		if dir == Vector2i.ZERO:
			dir = Vector2i(1, 0)
		var approach := cardinal + dir
		_look(approach.x, approach.y)
		await process_frame
		await process_frame
		var ap: Dictionary = _LiveWorldQuery.inspect_cell(self, approach.x, approach.y)
		_shot("natural_approach_%d_%d" % [approach.x, approach.y])
		if not bool(ap.get("column_mesh_covered", false)):
			_fail("natural approach floor missing at %s" % str(approach))
		else:
			print("OK natural approach %s faces=%s" % [str(approach), str(ap.get("column_face_codes"))])

	if corner.x != -99999:
		_look(corner.x, corner.y)
		if insp:
			insp.pin_cell = corner
		for _f2 in 6:
			await process_frame
		var csnap: Dictionary = _LiveWorldQuery.inspect_cell(self, corner.x, corner.y)
		_shot("natural_corner_%d_%d" % [corner.x, corner.y])
		var cgeom: Dictionary = csnap.get("surface_geom", {})
		print("NATURAL_CORNER cell=%s faces=%s has_ramp=%s covered=%s geom=%s" % [
			str(corner), str(csnap.get("column_face_codes")), str(csnap.get("has_ramp")),
			str(csnap.get("column_mesh_covered")), str(cgeom)
		])
		if not bool(csnap.get("column_mesh_covered", false)):
			_fail("natural corner not mesh-covered")
		if int(cgeom.get("tri_count", 0)) <= 0:
			_fail("natural corner: ArrayMesh has no triangles in the column")
		elif not bool(cgeom.get("is_slope", false)):
			_fail("natural corner: top is not a slope y_span=%s" % str(cgeom.get("y_span")))
		elif int(cgeom.get("unique_xz", 99)) > 4:
			_fail("natural corner: top is a square unique_xz=%s" % str(cgeom.get("unique_xz")))

	var player = get_first_node_in_group("player")
	var cam = player.get("camera") if player else null
	if cam != null:
		if bool(cam.get("edge_scroll_enabled")):
			_fail("camera edge_scroll must be off")
		else:
			print("OK camera edge_scroll disabled")
		cam.set("use_smoothing", false)
		if cam.has_method("snap_yaw_degrees"):
			cam.snap_yaw_degrees(45.0)
		Input.action_press("rotate_right")
		for _rq in 12:
			await process_frame
		Input.action_release("rotate_right")
		var yaw_now: float = float(cam.get("yaw_target_degrees"))
		if absf(yaw_now - 45.0) < 3.0:
			_fail("Q/E rotate_right did not change yaw (got %.2f)" % yaw_now)
		else:
			print("OK Q/E yaw now %.2f" % yaw_now)
		if cam.has_method("snap_yaw_degrees"):
			cam.snap_yaw_degrees(45.0)

	var build_cell := _pick_interior_solid(cm, world)
	if build_cell.x != -99999 and editor and player and player.get("inventory"):
		var inv = player.inventory
		inv.add_item("stone", 4)
		inv.add_item("wood", 4)
		var h0: float = _TerrainEdits.get_height_delta(build_cell.x, build_cell.y)
		_look(build_cell.x, build_cell.y)
		if insp:
			insp.pin_cell = build_cell
		for _bw in 4:
			await process_frame
		_shot("build_before_%d_%d" % [build_cell.x, build_cell.y])
		var pos := Vector3(float(build_cell.x) + 0.5, world.get_surface_height(float(build_cell.x), float(build_cell.y)), float(build_cell.y) + 0.5)
		if not editor.try_build(pos, inv, &"stone_wall"):
			_fail("stone_wall place failed: %s" % editor.last_fail_reason)
		else:
			if cm.has_method("await_rebuild_idle"):
				await cm.await_rebuild_idle(120)
			for _ba in 6:
				await process_frame
			_shot("build_wall_%d_%d" % [build_cell.x, build_cell.y])
			var h1: float = _TerrainEdits.get_height_delta(build_cell.x, build_cell.y)
			var feat: Dictionary = _FeatureRegistry.get_feature(build_cell.x, build_cell.y)
			print("BUILD_WALL cell=%s delta %.3f→%.3f feat=%s" % [str(build_cell), h0, h1, str(feat.get("build_id"))])
			if not is_equal_approx(h1, h0):
				_fail("wall placed a terrain voxel (height_delta changed)")
			elif str(feat.get("build_id")) != "stone_wall":
				_fail("wall WorldObject feature missing")
			if not editor.try_remove(pos, inv):
				_fail("LMB remove wall failed: %s" % editor.last_fail_reason)
			else:
				if cm.has_method("await_rebuild_idle"):
					await cm.await_rebuild_idle(120)
				for _br in 6:
					await process_frame
				_shot("build_removed_%d_%d" % [build_cell.x, build_cell.y])
				var h2: float = _TerrainEdits.get_height_delta(build_cell.x, build_cell.y)
				if not is_equal_approx(h2, h0):
					_fail("wall remove damaged supporting terrain")
				elif not _FeatureRegistry.get_feature(build_cell.x, build_cell.y).is_empty():
					_fail("wall feature still present after remove")
				else:
					print("OK wall place/remove no terrain voxel")
		# Gate + remove
		if editor.try_build_gate(pos, inv):
			if cm.has_method("await_rebuild_idle"):
				await cm.await_rebuild_idle(80)
			for _bg in 4:
				await process_frame
			_shot("build_gate_%d_%d" % [build_cell.x, build_cell.y])
			if not editor.try_remove(pos, inv):
				_fail("gate remove failed: %s" % editor.last_fail_reason)
			else:
				print("OK gate removed")
		else:
			_fail("gate place failed: %s" % editor.last_fail_reason)
		if editor.try_build_bridge(pos, inv):
			if cm.has_method("await_rebuild_idle"):
				await cm.await_rebuild_idle(80)
			for _bb in 4:
				await process_frame
			_shot("build_bridge_%d_%d" % [build_cell.x, build_cell.y])
			if not editor.try_remove(pos, inv):
				_fail("bridge remove failed: %s" % editor.last_fail_reason)
			else:
				print("OK bridge removed")
		else:
			_fail("bridge place failed: %s" % editor.last_fail_reason)
		var fill_cell := _pick_interior_solid(cm, world)
		if fill_cell.x != -99999:
			var fpos := Vector3(float(fill_cell.x) + 0.5, world.get_surface_height(float(fill_cell.x), float(fill_cell.y)), float(fill_cell.y) + 0.5)
			var fh0: float = world.get_surface_height(float(fill_cell.x), float(fill_cell.y))
			_look(fill_cell.x, fill_cell.y)
			if not editor.try_fill(fpos, inv):
				_fail("fill place failed: %s" % editor.last_fail_reason)
			else:
				if cm.has_method("await_rebuild_idle"):
					await cm.await_rebuild_idle(120)
				for _ff in 6:
					await process_frame
				_shot("fill_%d_%d" % [fill_cell.x, fill_cell.y])
				var fh1: float = world.get_surface_height(float(fill_cell.x), float(fill_cell.y))
				if fh1 <= fh0 + 0.1:
					_fail("fill did not raise terrain")
				else:
					print("OK fill raised %.2f→%.2f" % [fh0, fh1])

	# Dig immediately beside a generated cardinal ramp (exposed side lips).
	if cardinal.x != -99999:
		var rsnap: Dictionary = _LiveWorldQuery.inspect_cell(self, cardinal.x, cardinal.y)
		var rdir: Vector2i = (rsnap.get("ramp", {}) as Dictionary).get("dir", Vector2i(1, 0))
		if rdir == Vector2i.ZERO:
			rdir = Vector2i(1, 0)
		var beside := cardinal + Vector2i(-rdir.y, rdir.x)
		await _dig_and_check(cm, world, editor, insp, beside, "beside_ramp")
		_look(cardinal.x, cardinal.y)
		for _rb in 4:
			await process_frame
		var after_b: Dictionary = _LiveWorldQuery.inspect_cell(self, cardinal.x, cardinal.y)
		_shot("ramp_after_beside_dig_%d_%d" % [cardinal.x, cardinal.y])
		if not bool(after_b.get("column_mesh_covered", false)):
			_fail("cardinal landing uncovered after beside-dig")
		var bgeom: Dictionary = after_b.get("surface_geom", {})
		if int(bgeom.get("tri_count", 0)) <= 0:
			_fail("cardinal landing lost slope triangles after beside-dig")

	# Opposing-ramp prevention: 1-layer pit in a flat run must not grow a V.
	var pit := _pick_interior_solid(cm, world)
	if pit.x != -99999:
		await _dig_and_check(cm, world, editor, insp, pit, "valley_pit")
		var left := pit + Vector2i(-1, 0)
		var right := pit + Vector2i(1, 0)
		var ls: Dictionary = _LiveWorldQuery.inspect_cell(self, left.x, left.y)
		var rs: Dictionary = _LiveWorldQuery.inspect_cell(self, right.x, right.y)
		_look(pit.x, pit.y)
		await process_frame
		_shot("valley_pit_%d_%d" % [pit.x, pit.y])
		var ld: Vector2i = (ls.get("ramp", {}) as Dictionary).get("dir", Vector2i.ZERO)
		var rd: Vector2i = (rs.get("ramp", {}) as Dictionary).get("dir", Vector2i.ZERO)
		var v_left := bool(ls.get("has_ramp", false)) and ld == Vector2i(1, 0)
		var v_right := bool(rs.get("has_ramp", false)) and rd == Vector2i(-1, 0)
		if v_left and v_right:
			_fail("opposing V-ramps into pit at %s" % str(pit))
		else:
			print("OK no V-ramps into pit %s (L=%s R=%s)" % [str(pit), str(ld), str(rd)])

	# Two-layer dig: leftover mid-height tops must not remain.
	var deep := _pick_interior_solid(cm, world)
	if deep.x == -99999:
		_fail("no deep-dig cell")
	else:
		var dy0: float = world.get_surface_height(float(deep.x), float(deep.y))
		_look(deep.x, deep.y)
		if insp:
			insp.pin_cell = deep
		if not editor.try_dig(Vector3(float(deep.x) + 0.5, dy0, float(deep.y) + 0.5)):
			_fail("deep dig 1 failed: %s" % editor.last_fail_reason)
		else:
			if not editor.try_dig(Vector3(float(deep.x) + 0.5, dy0, float(deep.y) + 0.5)):
				_fail("deep dig 2 failed: %s" % editor.last_fail_reason)
			else:
				if cm.has_method("await_rebuild_idle"):
					await cm.await_rebuild_idle(180)
				for _dd in 8:
					await process_frame
				_look(deep.x, deep.y)
				_shot("dig_deep_after_%d_%d" % [deep.x, deep.y])
				var dsnap: Dictionary = _LiveWorldQuery.inspect_cell(self, deep.x, deep.y)
				var dy1: float = world.get_surface_height(float(deep.x), float(deep.y))
				print("DEEP_DIG cell=%s %.2f→%.2f faces=%s geom=%s" % [
					str(deep), dy0, dy1, str(dsnap.get("column_face_codes")), str(dsnap.get("surface_geom"))
				])
				if dy1 > dy0 - 3.5:
					_fail("deep dig did not lower two layers")
				if not bool(dsnap.get("column_mesh_covered", false)):
					_fail("deep dug cell uncovered")

	# Interior dig
	var interior := _pick_interior_solid(cm, world)
	if interior.x == -99999:
		_fail("no interior dig cell")
	else:
		await _dig_and_check(cm, world, editor, insp, interior, "interior")

	# Chunk-boundary dig (local x or z == 0 or SIZE-1 of a resident chunk)
	var edge := _pick_edge_solid(cm, world)
	if edge.x == -99999:
		_fail("no edge dig cell")
	else:
		await _dig_and_check(cm, world, editor, insp, edge, "edge")

	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "NATURAL RAMP DIG LIVE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "NATURAL RAMP DIG LIVE FAILED")


func _dig_and_check(cm, world, editor, insp, cell: Vector2i, tag: String) -> void:
	var neighbors: Array = [
		cell + Vector2i(2, 0), cell + Vector2i(-2, 0),
		cell + Vector2i(0, 2), cell + Vector2i(0, -2),
		cell + Vector2i(3, 3),
	]
	var before: Dictionary = {}
	for n in neighbors:
		var ns: Dictionary = _LiveWorldQuery.inspect_cell(self, n.x, n.y)
		before[n] = bool(ns.get("column_mesh_covered", false))
	_look(cell.x, cell.y)
	if insp:
		insp.pin_cell = cell
	for _b in 4:
		await process_frame
	_shot("dig_%s_before_%d_%d" % [tag, cell.x, cell.y])
	var y0: float = world.get_surface_height(float(cell.x), float(cell.y))
	if not editor.try_dig(Vector3(float(cell.x) + 0.5, y0, float(cell.y) + 0.5)):
		_fail("%s try_dig failed at %s: %s" % [tag, cell, editor.last_fail_reason])
		return
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(180)
	for _a in 8:
		await process_frame
	_look(cell.x, cell.y)
	await process_frame
	_shot("dig_%s_after_%d_%d" % [tag, cell.x, cell.y])
	var dug: Dictionary = _LiveWorldQuery.inspect_cell(self, cell.x, cell.y)
	if not bool(dug.get("column_mesh_covered", false)):
		_fail("%s dug cell itself uncovered %s" % [tag, cell])
	for n in neighbors:
		var ns2: Dictionary = _LiveWorldQuery.inspect_cell(self, n.x, n.y)
		var cov: bool = bool(ns2.get("column_mesh_covered", false))
		if bool(before.get(n, false)) and not cov:
			_fail("%s dig at %s uncovered neighbor %s faces=%s" % [
				tag, cell, n, str(ns2.get("column_face_codes"))
			])
			_look(n.x, n.y)
			await process_frame
			_shot("dig_%s_lost_%d_%d" % [tag, n.x, n.y])
	print("OK %s dig %s neighbors intact" % [tag, str(cell)])


func _find_natural_ramps(cm) -> Dictionary:
	var out := {"cardinal": Vector2i(-99999, 0), "corner": Vector2i(-99999, 0)}
	if cm == null:
		return out
	for key_v in cm.chunks.keys():
		var coord: Vector2i = key_v
		var view = cm.chunks[coord]
		if view == null or view.chunk_data == null:
			continue
		var data = view.chunk_data
		for rk in data.ramp_map.keys():
			var local: Vector2i = rk
			var entry: Dictionary = data.ramp_map[rk]
			var wx: int = coord.x * _ChunkData.SIZE + local.x
			var wz: int = coord.y * _ChunkData.SIZE + local.y
			if bool(entry.get("approach", false)):
				continue
			if _column_is_water(data, local.x, local.y):
				continue
			if bool(entry.get("corner", false)) and out.corner.x == -99999:
				out.corner = Vector2i(wx, wz)
			elif not bool(entry.get("corner", false)) and not bool(entry.get("side", false)) \
					and not bool(entry.get("concave", false)) and out.cardinal.x == -99999:
				out.cardinal = Vector2i(wx, wz)
			if out.cardinal.x != -99999 and out.corner.x != -99999:
				return out
	return out


func _column_is_water(data, lx: int, lz: int) -> bool:
	if data == null or data.tile_map.size() <= lx:
		return false
	if data.tile_map[lx] == null or data.tile_map[lx].size() <= lz:
		return false
	var vox: int = int(data.tile_map[lx][lz])
	return vox == _VoxelTypes.RIVER or vox == _VoxelTypes.WATER \
		or vox == _VoxelTypes.OCEAN or vox == _VoxelTypes.OCEAN2 or vox == _VoxelTypes.OCEAN3


func _pick_interior_solid(cm, world) -> Vector2i:
	for key_v in cm.chunks.keys():
		var coord: Vector2i = key_v
		for lx in range(4, _ChunkData.SIZE - 4):
			for lz in range(4, _ChunkData.SIZE - 4):
				var wx: int = coord.x * _ChunkData.SIZE + lx
				var wz: int = coord.y * _ChunkData.SIZE + lz
				if _ActionTargeting._is_solid_column(world, cm, wx, wz):
					return Vector2i(wx, wz)
	return Vector2i(-99999, 0)


func _pick_edge_solid(cm, world) -> Vector2i:
	for key_v in cm.chunks.keys():
		var coord: Vector2i = key_v
		for pair in [[0, 8], [15, 8], [8, 0], [8, 15]]:
			var wx: int = coord.x * _ChunkData.SIZE + int(pair[0])
			var wz: int = coord.y * _ChunkData.SIZE + int(pair[1])
			if _ActionTargeting._is_solid_column(world, cm, wx, wz):
				return Vector2i(wx, wz)
	return Vector2i(-99999, 0)


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


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(_scratch.path_join("%s.png" % name))
	print("SHOT %s" % _scratch.path_join("%s.png" % name))
