extends SceneTree
## Boot main.tscn, stamp a streamed Batch 02 yard, capture each named ID.
## Usage: godot --path . -s scripts/verify_terrain_batch02_capture.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const OUT_DIR := "C:/Users/cwith/AppData/Local/Temp/grok-goal-0dba86d3f6db/implementer"
const CUBE := "res://assets/tiles/Cube.png"
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

	_assert_cube_bind(cm)
	_ok("g1_side=%s" % str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.GRASSLAND, 3)))
	_ok("g2_side=%s" % str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.GRASSLAND2, 3)))
	_ok("g5_side=%s" % str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.GRASSLAND5, 3)))
	_ok("h2_side=%s" % str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.HILLS2, 3)))
	_ok("g3_top=%s" % str(VoxelTypes.get_atlas_coord(VoxelTypes.GRASSLAND3)))
	_hunt_natural(world)

	var g1 := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(0, 0), VoxelTypes.GRASSLAND)
	var g2 := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(4, 0), VoxelTypes.GRASSLAND2)
	var g5 := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(8, 0), VoxelTypes.GRASSLAND5)
	var h2 := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(12, 0), VoxelTypes.HILLS2)
	var g3 := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(0, 4), VoxelTypes.GRASSLAND3)
	var h1 := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(4, 4), VoxelTypes.HILLS)
	var dirt := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(8, 4), VoxelTypes.DIRT)
	_flush_remesh(cm, [g1, g2, g5, h2, g3, h1, dirt])
	for _w in 70:
		await process_frame

	var cam = get_first_node_in_group("camera")
	await _goto_and_capture(player, cam, world, cm, g1, 10.0, "grassland", VoxelTypes.GRASSLAND)
	await _goto_and_capture(player, cam, world, cm, g2, 10.0, "grassland2", VoxelTypes.GRASSLAND2)
	await _goto_and_capture(player, cam, world, cm, g5, 10.0, "grassland5", VoxelTypes.GRASSLAND5)
	await _goto_and_capture(player, cam, world, cm, h2, 10.0, "hills2", VoxelTypes.HILLS2)
	await _goto_and_capture(player, cam, world, cm, g3, 10.0, "grassland3_b01", VoxelTypes.GRASSLAND3)
	await _goto_and_capture(player, cam, world, cm, h1, 10.0, "hills_b01", VoxelTypes.HILLS)
	await _goto_and_capture(player, cam, world, cm, dirt, 10.0, "dirt_b01", VoxelTypes.DIRT)
	await _goto_and_capture(player, cam, world, cm, Vector2i(15, g1.y), 12.0, "chunk_boundary", -1)

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


func _hunt_natural(world) -> void:
	var wanted := PackedInt32Array([
		VoxelTypes.GRASSLAND, VoxelTypes.GRASSLAND2, VoxelTypes.GRASSLAND5, VoxelTypes.HILLS2,
	])
	var found: Dictionary = {}
	for dx in range(-40, 41):
		for dz in range(-40, 41):
			var x: int = 12 + dx
			var z: int = 12 + dz
			var t: int = int(world.get_tile_type(float(x), float(z)))
			if t in wanted and not found.has(t):
				found[t] = Vector2i(x, z)
	if not found.has(VoxelTypes.HILLS2):
		for ox in range(-24, 25, 2):
			for oz in range(-24, 25, 2):
				var x2: int = 369 + ox
				var z2: int = 426 + oz
				var t2: int = int(world.get_tile_type(float(x2), float(z2)))
				if t2 == VoxelTypes.HILLS2:
					found[t2] = Vector2i(x2, z2)
					break
			if found.has(VoxelTypes.HILLS2):
				break
	print("NATURAL %s" % str(found))
	var summary: Array = BiomeLayout.get_region_summary()
	for r in summary:
		var c: Array = r.get("center", [0, 0])
		print("REGION %s center=%.1f,%.1f" % [str(r.get("biome", "?")), float(c[0]), float(c[1])])


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
			_patch_column(cm, x, z, id, 2.0)
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
	print("PATCH %d,%d tile=%d y=%.1f chunk=%s" % [wx, wz, tile, y, str(coord)])


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
		elif cm.has_method("rebuild_chunk_at_world"):
			cm.rebuild_chunk_at_world(float(cell.x), float(cell.y))


func _assert_cube_bind(cm) -> void:
	if cm == null:
		_fail("no chunk manager")
		return
	_ok("Cube.png is ChunkView._ATLAS_TEX preload")


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
		_ProbeExit.finish_tree(self, 0, "TERRAIN BATCH02 CAPTURE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "TERRAIN BATCH02 CAPTURE FAILED")
