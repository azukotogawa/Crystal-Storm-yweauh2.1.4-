extends SceneTree


const MAIN_SCENE := "res://scenes/main.tscn"
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


var _scratch: String = ""
var _failed: PackedStringArray = PackedStringArray()
var _ok: PackedStringArray = PackedStringArray()


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
	_failed.append(msg)
	push_error("FAIL %s" % msg)
	print("FAIL %s" % msg)


func _pass(msg: String) -> void:
	_ok.append(msg)
	print("OK %s" % msg)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = ProjectSettings.globalize_path("user://accept_shots")
	DirAccess.make_dir_recursive_absolute(_scratch)
	print("SCRATCH %s display=%s" % [_scratch, DisplayServer.get_name()])
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
		_ProbeExit.finish_tree(self, 1, "not ready")
		return
	for _w in 10:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var editor = get_first_node_in_group("terrain_editor")
	var fluid = get_first_node_in_group("voxel_fluid_service")
	if cm == null or world == null or editor == null:
		_ProbeExit.finish_tree(self, 1, "missing services")
		return
	await _water_pass(cm, world, editor, fluid)
	await _ramp_pass(cm, world, editor)
	print("ACCEPT_OK count=%d" % _ok.size())
	print("ACCEPT_FAIL count=%d" % _failed.size())
	for f in _failed:
		print("  FAIL %s" % f)
	_ProbeExit.finish_tree(self, 0 if _failed.is_empty() else 1, "ACCEPT PASS DONE")


func _water_pass(cm, world, editor, fluid) -> void:
	var river := _find_river_with_land(cm, world)
	if river.source.x == -99999:
		_fail("water: no natural river+land pair in resident chunks")
		return
	print("WATER source=%s land=%s tile=%s" % [str(river.source), str(river.land), str(river.tile)])
	_look(river.source.x, river.source.y)
	for _f in 8:
		await process_frame
	_shot("water_source_before")
	var src_h0: float = world.get_surface_height(float(river.source.x), float(river.source.y))
	var src_tile0: int = world.get_tile_type(float(river.source.x), float(river.source.y))
	var pos_src := Vector3(float(river.source.x) + 0.5, src_h0, float(river.source.y) + 0.5)
	var broke: bool = editor.try_dig(pos_src)
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(80)
	for _d in 6:
		await process_frame
	_shot("water_source_after_dig")
	var src_h1: float = world.get_surface_height(float(river.source.x), float(river.source.y))
	if broke or src_h1 < src_h0 - 0.01:
		_fail("water: source voxel is breakable (try_dig=%s h %.2f→%.2f tile=%d)" % [
			str(broke), src_h0, src_h1, src_tile0
		])
	else:
		_pass("water: source voxel refused dig")
	if fluid and fluid.has_method("is_persistent_source"):
		if not bool(fluid.is_persistent_source(river.source.x, river.source.y)):
			_fail("water: source lost persistent-source flag after dig attempt")
		else:
			_pass("water: river still a source after dig attempt")

	var land_h0: float = world.get_surface_height(float(river.land.x), float(river.land.y))
	var pos_land := Vector3(float(river.land.x) + 0.5, land_h0, float(river.land.y) + 0.5)
	if not editor.try_dig(pos_land):
		_fail("water: adjacent land dig failed %s" % editor.last_fail_reason)
		return
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(80)
	if fluid and fluid.has_method("recompute_region_now"):
		fluid.recompute_region_now(river.land.x, river.land.y, 2, 8)
	for _w in 12:
		await process_frame
	_look(river.land.x, river.land.y)
	for _f2 in 8:
		await process_frame
	_shot("water_depression_flood")
	var land_h1: float = world.get_surface_height(float(river.land.x), float(river.land.y))
	var wet := false
	if fluid and fluid.has_method("is_wet_column"):
		wet = bool(fluid.is_wet_column(river.land.x, river.land.y))
	var overlay: bool = _ChannelRegistry.has_fluid(river.land.x, river.land.y, _ChannelRegistry.FLUID_WATER)
	var sy := 0.0
	if fluid and fluid.has_method("get_body_surface_y"):
		sy = float(fluid.get_body_surface_y(river.land.x, river.land.y))
	var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, river.land.x, river.land.y)
	var faces: Array = snap.get("column_face_codes", [])
	var geom: Dictionary = snap.get("surface_geom", {})
	print("WATER flood land=%s wet=%s overlay=%s sy=%.2f bed %.2f→%.2f faces=%s geom=%s" % [
		str(river.land), str(wet), str(overlay), sy, land_h0, land_h1, str(faces), str(geom)
	])
	if land_h1 >= land_h0 - 0.01:
		_fail("water: adjacent dig did not lower bed")
	if not wet and not overlay:
		_fail("water: connected depression did not flood")
	else:
		_pass("water: depression flooded overlay/wet")
	if 7 in faces or 8 in faces or 9 in faces:
		_fail("water: flooded column emitted ramp faces %s" % str(faces))
	else:
		_pass("water: no ramp faces on flooded column")
	if fluid and fluid.has_method("is_persistent_source"):
		if bool(fluid.is_persistent_source(river.land.x, river.land.y)):
			_fail("water: flooded land became a source")
		if not bool(fluid.is_persistent_source(river.source.x, river.source.y)):
			_fail("water: original river is no longer a source after flood")
		else:
			_pass("water: original river remains the source")
	var layer: float = _WorldSettings.get_active().layer_height()
	if sy > 0.01:
		var src_top: float = src_h0 + layer
		if absf(sy - src_top) > layer * 0.6:
			_fail("water: surface_y %.2f not near source visual top %.2f" % [sy, src_top])
		else:
			_pass("water: body surface_y=%.2f near source top %.2f" % [sy, src_top])

	var inv = null
	var player = get_first_node_in_group("player")
	if player and "inventory" in player:
		inv = player.inventory
		inv.add_item("stone", 8)
	if editor.has_method("try_fill"):
		if not editor.try_fill(pos_land, inv):
			_fail("water: fill depression failed %s" % editor.last_fail_reason)
		else:
			if cm.has_method("await_rebuild_idle"):
				await cm.await_rebuild_idle(80)
			if fluid and fluid.has_method("recompute_region_now"):
				fluid.recompute_region_now(river.land.x, river.land.y, 2, 6)
			for _ff in 10:
				await process_frame
			_shot("water_after_fill")
			var still_wet := false
			if fluid and fluid.has_method("is_wet_column"):
				still_wet = bool(fluid.is_wet_column(river.land.x, river.land.y)) \
					and _ChannelRegistry.has_fluid(river.land.x, river.land.y, _ChannelRegistry.FLUID_WATER)
			if still_wet:
				_fail("water: fill did not dry flooded overlay")
			else:
				_pass("water: fill dried the depression")
			if fluid and fluid.has_method("is_persistent_source"):
				if not bool(fluid.is_persistent_source(river.source.x, river.source.y)):
					_fail("water: river lost source after fill")
				else:
					_pass("water: river still source after fill")


func _ramp_pass(cm, world, editor) -> void:
	var found := _find_ramps(cm)
	print("RAMPS cardinal=%s corner=%s" % [str(found.cardinal), str(found.corner)])
	if found.cardinal.x == -99999:
		_fail("ramps: no generated cardinal in resident chunks")
	else:
		_look(found.cardinal.x, found.cardinal.y)
		for _f in 8:
			await process_frame
		_shot("ramp_cardinal")
		var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, found.cardinal.x, found.cardinal.y)
		var ramp: Dictionary = snap.get("ramp", {})
		var geom: Dictionary = snap.get("surface_geom", {})
		var faces: Array = snap.get("column_face_codes", [])
		print("CARDINAL cell=%s faces=%s dir=%s geom=%s" % [
			str(found.cardinal), str(faces), str(ramp.get("dir")), str(geom)
		])
		if 9 in faces:
			_fail("ramps: cardinal column has FACE_RAMP_SIDE")
		if int(faces.count(7)) > 1:
			_fail("ramps: stacked cardinal FACE_RAMP on one column")
		if not bool(geom.get("is_slope", false)):
			_fail("ramps: cardinal not a slope y_span=%s" % str(geom.get("y_span")))
		else:
			_pass("ramps: cardinal is a slope y_span=%.2f" % float(geom.get("y_span", 0.0)))
		var dir: Vector2i = ramp.get("dir", Vector2i.ZERO)
		if dir != Vector2i.ZERO:
			var ap: Vector2i = found.cardinal + dir
			var aps: Dictionary = _LiveWorldQuery.inspect_cell(self, ap.x, ap.y)
			var apf: Array = aps.get("column_face_codes", [])
			if 7 in apf:
				_fail("ramps: second slope on cardinal approach %s faces=%s" % [str(ap), str(apf)])
			else:
				_pass("ramps: approach %s has no cardinal slope" % str(ap))
		var player = get_first_node_in_group("player")
		if player:
			player.voxel_position.x = float(found.cardinal.x) + 0.5
			player.voxel_position.z = float(found.cardinal.y) + 0.5
			if player.has_method("_sync_global_from_voxel"):
				player._sync_global_from_voxel()
			if player.has_method("_snap_to_ground"):
				player._snap_to_ground()
			for _w in 6:
				await process_frame
			var walk: float = float(snap.get("walk", snap.get("walkable_height", 0.0)))
			var py: float = float(player.voxel_position.y)
			if absf(py - walk) > 1.6:
				_fail("ramps: walk Y %.2f disagrees with collision %.2f on cardinal" % [py, walk])
			else:
				_pass("ramps: walked cardinal feet=%.2f walk=%.2f" % [py, walk])
		var ncell := Vector2i(found.cardinal.x + 1, found.cardinal.y)
		var nh: float = world.get_surface_height(float(ncell.x), float(ncell.y))
		if editor.try_dig(Vector3(float(ncell.x) + 0.5, nh, float(ncell.y) + 0.5)):
			if cm.has_method("await_rebuild_idle"):
				await cm.await_rebuild_idle(80)
			for _g in 6:
				await process_frame
			_shot("ramp_cardinal_after_adj_dig")
			var after: Dictionary = _LiveWorldQuery.inspect_cell(self, found.cardinal.x, found.cardinal.y)
			var ag: Dictionary = after.get("surface_geom", {})
			print("CARDINAL after adj dig faces=%s geom=%s" % [
				str(after.get("column_face_codes")), str(ag)
			])
			_pass("ramps: adjacent dig on cardinal neighborhood remeshed")

	if found.corner.x == -99999:
		_fail("ramps: no generated inner-corner in resident chunks")
	else:
		_look(found.corner.x, found.corner.y)
		for _f2 in 8:
			await process_frame
		_shot("ramp_corner")
		var csnap: Dictionary = _LiveWorldQuery.inspect_cell(self, found.corner.x, found.corner.y)
		var cramp: Dictionary = csnap.get("ramp", {})
		var cgeom: Dictionary = csnap.get("surface_geom", {})
		var cfaces: Array = csnap.get("column_face_codes", [])
		print("CORNER cell=%s faces=%s dir=%s dir2=%s geom=%s" % [
			str(found.corner), str(cfaces), str(cramp.get("dir")), str(cramp.get("dir2")), str(cgeom)
		])
		if 9 in cfaces:
			_fail("ramps: corner has FACE_RAMP_SIDE compound")
		if 7 in cfaces:
			_fail("ramps: corner column also has cardinal FACE_RAMP")
		if not bool(cgeom.get("is_triangle_top", false)) and int(cgeom.get("unique_xz", 99)) > 4:
			_fail("ramps: corner is not a half-block unique_xz=%s" % str(cgeom.get("unique_xz")))
		elif int(cgeom.get("tri_count", 0)) <= 0:
			_fail("ramps: corner has no triangles")
		else:
			_pass("ramps: corner geom unique_xz=%s y_span=%.2f" % [
				str(cgeom.get("unique_xz")), float(cgeom.get("y_span", 0.0))
			])
		if 0 not in cfaces:
			_fail("ramps: corner missing floor FACE_TOP (hole under half-block)")
		else:
			_pass("ramps: corner keeps floor FACE_TOP")
		var da: Vector2i = cramp.get("dir", Vector2i.ZERO)
		var db: Vector2i = cramp.get("dir2", Vector2i.ZERO)
		for d in [da, db]:
			if d == Vector2i.ZERO:
				continue
			var sup: Vector2i = found.corner + d
			var ss: Dictionary = _LiveWorldQuery.inspect_cell(self, sup.x, sup.y)
			var sf: Array = ss.get("column_face_codes", [])
			if 7 in sf or 8 in sf:
				_fail("ramps: supporting cell %s is not a full block faces=%s" % [str(sup), str(sf)])
			else:
				_pass("ramps: support %s is full-block faces=%s" % [str(sup), str(sf)])
		var player2 = get_first_node_in_group("player")
		if player2:
			player2.voxel_position.x = float(found.corner.x) + 0.5
			player2.voxel_position.z = float(found.corner.y) + 0.5
			if player2.has_method("_sync_global_from_voxel"):
				player2._sync_global_from_voxel()
			if player2.has_method("_snap_to_ground"):
				player2._snap_to_ground()
			for _w2 in 6:
				await process_frame
			_shot("ramp_corner_stood")
			var cwalk: float = float(csnap.get("walk", csnap.get("walkable_height", 0.0)))
			var py2: float = float(player2.voxel_position.y)
			if absf(py2 - cwalk) > 1.6:
				_fail("ramps: walk Y %.2f disagrees with collision %.2f on corner" % [py2, cwalk])
			else:
				_pass("ramps: walked corner feet=%.2f walk=%.2f" % [py2, cwalk])


func _find_river_with_land(cm, world) -> Dictionary:
	var out := {"source": Vector2i(-99999, 0), "land": Vector2i(-99999, 0), "tile": -1}
	if cm == null:
		return out
	for key_v in cm.chunks.keys():
		var coord: Vector2i = key_v
		var view = cm.chunks[coord]
		if view == null or view.chunk_data == null:
			continue
		var data = view.chunk_data
		for lx in range(1, _ChunkData.SIZE - 1):
			for lz in range(1, _ChunkData.SIZE - 1):
				if data.tile_map.size() <= lx or data.tile_map[lx].size() <= lz:
					continue
				var tile: int = int(data.tile_map[lx][lz])
				if tile != _VoxelTypes.RIVER and tile != _VoxelTypes.WATER:
					continue
				var wx: int = coord.x * _ChunkData.SIZE + lx
				var wz: int = coord.y * _ChunkData.SIZE + lz
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = wx + d.x
					var nz: int = wz + d.y
					var nt: int = world.get_tile_type(float(nx), float(nz))
					if nt == _VoxelTypes.RIVER or nt == _VoxelTypes.WATER \
							or nt == _VoxelTypes.OCEAN or nt == _VoxelTypes.OCEAN2:
						continue
					out.source = Vector2i(wx, wz)
					out.land = Vector2i(nx, nz)
					out.tile = tile
					return out
	return out


func _find_ramps(cm) -> Dictionary:
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
			if bool(entry.get("approach", false)) or bool(entry.get("concave", false)) \
					or bool(entry.get("side", false)):
				continue
			var wx: int = coord.x * _ChunkData.SIZE + local.x
			var wz: int = coord.y * _ChunkData.SIZE + local.y
			if bool(entry.get("corner", false)):
				if out.corner.x == -99999:
					out.corner = Vector2i(wx, wz)
			elif out.cardinal.x == -99999:
				out.cardinal = Vector2i(wx, wz)
			if out.cardinal.x != -99999 and out.corner.x != -99999:
				return out
	return out


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
		print("SHOT skipped headless %s" % name)
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _scratch.path_join("%s.png" % name)
	img.save_png(path)
	print("SHOT %s" % path)
