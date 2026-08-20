extends SceneTree
## Usage: godot --path . -s scripts/verify_terrain_batch04_capture.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const OUT_DIR := "C:/Users/cwith/AppData/Local/Temp/grok-terrain-batch04"
const YARD := Vector2i(18, 18)

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "low")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("missing main scene")
		_finish()
		return
	var game = packed.instantiate()
	root.add_child(game)
	var player
	var cm
	var feat_layer
	var editor
	var world
	var registry
	for _i in 400:
		await process_frame
		player = get_first_node_in_group("player")
		cm = get_first_node_in_group("chunk_manager")
		feat_layer = get_first_node_in_group("feature_visual_layer")
		editor = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		registry = get_first_node_in_group("game_visual_registry")
		var load_ui = get_first_node_in_group("loading_screen")
		if player and cm and feat_layer and editor and world and registry \
				and cm.chunks.size() > 0 \
				and registry.has_method("is_ready") and registry.is_ready() \
				and (load_ui == null or not bool(load_ui.visible)):
			break
	if player == null or world == null:
		_fail("boot missing systems")
		_finish()
		return
	var load_ui = get_first_node_in_group("loading_screen")
	if load_ui:
		load_ui.visible = false
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal:
		crystal.set_process(false)
	var lwd = get_first_node_in_group("living_world_director")
	if lwd:
		lwd.set_process(false)
	_hide_devtools()
	if player:
		var hl = player.get_node_or_null("TargetHighlight")
		if hl:
			hl.visible = false
			hl.set_process(false)
	for _boot in 20:
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_ok("m2=%s side=%s" % [
		str(VoxelTypes.get_atlas_coord(VoxelTypes.MOUNTAIN2)),
		str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.MOUNTAIN2, 3)),
	])
	_ok("basin=%s snow=%s snow2=%s snow_side=%s" % [
		str(VoxelTypes.get_atlas_coord(VoxelTypes.BASIN)),
		str(VoxelTypes.get_atlas_coord(VoxelTypes.SNOW)),
		str(VoxelTypes.get_atlas_coord(VoxelTypes.SNOW2)),
		str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.SNOW, 3)),
	])
	_ok("stone=%s stone2=%s g4=%s" % [
		str(VoxelTypes.get_atlas_coord(VoxelTypes.STONE)),
		str(VoxelTypes.get_atlas_coord(VoxelTypes.STONE2)),
		str(VoxelTypes.get_atlas_coord(VoxelTypes.GRASSLAND4)),
	])
	if VoxelTypes.get_atlas_coord(VoxelTypes.MOUNTAIN2) == VoxelTypes.get_atlas_coord(VoxelTypes.STONE):
		_fail("MOUNTAIN2 shares STONE")
	if VoxelTypes.get_atlas_coord(VoxelTypes.MOUNTAIN3) == VoxelTypes.get_atlas_coord(VoxelTypes.MOUNTAIN2):
		_fail("MOUNTAIN3 unexpectedly shares MOUNTAIN2")
	if VoxelTypes.get_atlas_coord(VoxelTypes.GRASSLAND4) == VoxelTypes.get_atlas_coord(VoxelTypes.DIRT):
		_fail("B03 regression: GRASSLAND4 shares DIRT")

	var found: Dictionary = _hunt_natural(world)
	var yard: Vector2i = YARD
	if found.has(VoxelTypes.GRASSLAND4):
		var nat: Vector2i = found[VoxelTypes.GRASSLAND4]
		yard = Vector2i(nat.x + 2, nat.y)
		print("YARD_FROM_NATURAL %s" % str(yard))
	elif found.has(VoxelTypes.BASIN):
		var b: Vector2i = found[VoxelTypes.BASIN]
		yard = Vector2i(b.x + 2, b.y)
		print("YARD_FROM_BASIN %s" % str(yard))
	_frame_camera(player, get_first_node_in_group("camera"), world, yard.x, yard.y, 12.0)
	var ycoord := Vector2i(int(floor(float(yard.x) / 16.0)), int(floor(float(yard.y) / 16.0)))
	if cm and cm.has_method("request_chunk"):
		cm.request_chunk(ycoord, true)
	for _s in 150:
		await process_frame
		if cm and cm.chunks.has(ycoord):
			break

	var m2 := _stamp_patch(world, cm, feat_layer, yard + Vector2i(0, 0), VoxelTypes.MOUNTAIN2)
	var basin := _stamp_patch(world, cm, feat_layer, yard + Vector2i(4, 0), VoxelTypes.BASIN)
	var snow := _stamp_patch(world, cm, feat_layer, yard + Vector2i(8, 0), VoxelTypes.SNOW)
	var snow2 := _stamp_patch(world, cm, feat_layer, yard + Vector2i(12, 0), VoxelTypes.SNOW2)
	var stone := _stamp_patch(world, cm, feat_layer, yard + Vector2i(0, 4), VoxelTypes.STONE)
	var g4 := _stamp_patch(world, cm, feat_layer, yard + Vector2i(4, 4), VoxelTypes.GRASSLAND4)
	_flush_remesh(cm, [m2, basin, snow, snow2, stone, g4])
	for _w in 90:
		await process_frame

	var cam = get_first_node_in_group("camera")
	await _goto_and_capture(player, cam, world, cm, m2, 10.0, "mountain2", VoxelTypes.MOUNTAIN2)
	await _goto_and_capture(player, cam, world, cm, basin, 10.0, "basin", VoxelTypes.BASIN)
	await _goto_and_capture(player, cam, world, cm, snow, 10.0, "snow", VoxelTypes.SNOW)
	await _goto_and_capture(player, cam, world, cm, snow2, 10.0, "snow2", VoxelTypes.SNOW2)
	await _goto_and_capture(player, cam, world, cm, stone, 10.0, "stone_b01", VoxelTypes.STONE)
	await _goto_and_capture(player, cam, world, cm, g4, 10.0, "grassland4_b03", VoxelTypes.GRASSLAND4)
	await _goto_and_capture(player, cam, world, cm, Vector2i(yard.x - 3, yard.y), 12.0, "chunk_boundary", -1)

	_ok("captures written under %s" % OUT_DIR)
	_finish()


func _hide_devtools() -> void:
	var insp = get_first_node_in_group("live_world_inspector")
	if insp:
		insp.panel_open = false
		insp.visible = false
		insp.set_process(false)
		insp.set_process_unhandled_input(false)
		for ch in insp.get_children():
			if ch is CanvasItem or ch is Control:
				ch.visible = false
	var overlay = get_first_node_in_group("game_overlay")
	if overlay:
		if "_toast" in overlay and overlay._toast:
			overlay._toast.visible = false
		if "_opening_toast_shown" in overlay:
			overlay._opening_toast_shown = true


func _hunt_natural(world) -> Dictionary:
	var wanted := PackedInt32Array([
		VoxelTypes.MOUNTAIN2, VoxelTypes.BASIN, VoxelTypes.SNOW, VoxelTypes.SNOW2,
		VoxelTypes.GRASSLAND4, VoxelTypes.STONE,
	])
	var found: Dictionary = {}
	for dx in range(-48, 49):
		for dz in range(-48, 49):
			var x: int = 12 + dx
			var z: int = 12 + dz
			var t: int = int(world.get_tile_type(float(x), float(z)))
			if t in wanted and not found.has(t):
				found[t] = Vector2i(x, z)
	if not found.has(VoxelTypes.MOUNTAIN2):
		for ox in range(-24, 25, 4):
			for oz in range(-24, 25, 4):
				var x2: int = -306 + ox
				var z2: int = 22 + oz
				var t2: int = int(world.get_tile_type(float(x2), float(z2)))
				if t2 == VoxelTypes.MOUNTAIN2:
					found[t2] = Vector2i(x2, z2)
					break
			if found.has(VoxelTypes.MOUNTAIN2):
				break
	print("NATURAL %s" % str(found))
	return found


func _stamp_patch(world, cm, feat_layer, origin: Vector2i, id: int) -> Vector2i:
	var center := origin + Vector2i(1, 1)
	for dx in range(0, 3):
		for dz in range(0, 3):
			var x: int = origin.x + dx
			var z: int = origin.y + dz
			_FeatureRegistry.clear_feature(x, z)
			_FeatureRegistry.set_tile_override(x, z, id)
			if world and world.has_method("invalidate_column_cache"):
				world.invalidate_column_cache(x, z)
			if feat_layer and feat_layer.has_method("refresh_cell"):
				feat_layer.refresh_cell(x, z)
			_patch_column(cm, x, z, id, 4.0)
	return center


func _patch_column(cm, wx: int, wz: int, tile: int, dy: float) -> void:
	if cm == null or not ("chunks" in cm):
		return
	var coord := Vector2i(int(floor(float(wx) / 16.0)), int(floor(float(wz) / 16.0)))
	if not cm.chunks.has(coord):
		print("PATCH_MISS chunk %s cell=%d,%d" % [str(coord), wx, wz])
		return
	var view = cm.chunks[coord]
	if view == null or view.chunk_data == null:
		return
	var data = view.chunk_data
	var lx: int = wx - coord.x * 16
	var lz: int = wz - coord.y * 16
	if not data.has_method("patch_local_column"):
		return
	var y: float = data.get_surface_y(lx, lz) + dy
	data.patch_local_column(lx, lz, y, tile)
	print("PATCH %d,%d tile=%d y=%.1f" % [wx, wz, tile, y])


func _flush_remesh(cm, cells: Array) -> void:
	if cm == null:
		return
	var seen: Dictionary = {}
	for c in cells:
		var cell: Vector2i = c
		var key := "%d,%d" % [cell.x, cell.y]
		if seen.has(key):
			continue
		seen[key] = true
		if cm.has_method("remesh_resident_maps_at_world"):
			cm.remesh_resident_maps_at_world(float(cell.x), float(cell.y))


func _goto_and_capture(player, cam, world, cm, cell: Vector2i, zoom: float, name: String, expect_id: int = -1) -> void:
	if expect_id >= 0:
		var got: int = world.get_tile_type(float(cell.x), float(cell.y))
		print("SHOT_ID %s want=%d got=%d cell=%s" % [name, expect_id, got, str(cell)])
		if got != expect_id:
			_fail("%s landed on id=%d want=%d at %s" % [name, got, expect_id, str(cell)])
	_frame_camera(player, cam, world, cell.x, cell.y, zoom)
	var coord := Vector2i(int(floor(float(cell.x) / 16.0)), int(floor(float(cell.y) / 16.0)))
	if cm and cm.has_method("request_chunk"):
		cm.request_chunk(coord, true)
	for _i in 80:
		await process_frame
		if cm and cm.chunks.has(coord):
			break
	for _j in 16:
		await process_frame
	await _capture(name)


func _frame_camera(player, cam, world, wx: int, wz: int, zoom: float = 10.0) -> void:
	var sy: float = world.get_surface_height(float(wx), float(wz))
	player.voxel_position = Vector3(float(wx) + 0.5, sy + 1.2, float(wz) + 0.5)
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if cam:
		cam.zoom_level = zoom
		cam.size = zoom
		cam.follow_target = player.global_position
		cam.global_position = player.global_position + cam.get_offset_from_rotation()
		cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	if vp == null or vp.get_texture() == null:
		_fail("no viewport %s" % name)
		return
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		_fail("empty %s" % name)
		return
	var path := OUT_DIR.path_join("%s.png" % name)
	img.save_png(path)
	print("SHOT %s %dx%d" % [path, img.get_width(), img.get_height()])


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "TERRAIN BATCH04 CAPTURE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "TERRAIN BATCH04 CAPTURE FAILED")
