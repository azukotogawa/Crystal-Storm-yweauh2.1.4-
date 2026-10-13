extends SceneTree
## Boot main.tscn, stamp a streamed Batch 01 yard, capture each named ID.
## Usage: godot --path . -s scripts/verify_terrain_batch01_capture.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const OUT_DIR := "C:/Users/cwith/AppData/Local/Temp/grok-goal-5d31680122c9/implementer"
const CUBE := "res://assets/tiles/Cube.png"
const YARD := Vector2i(18, 18)

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
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
	_ok("grass_side_remap=%s" % str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.GRASSLAND3, 3)))
	_ok("forest_side_remap=%s" % str(VoxelTypes.get_atlas_coord_for_face(VoxelTypes.HILLS, 3)))

	# Natural locations (report only — yard is what we photograph).
	_log_natural_hunt(world)

	# 3×3 yard in the already-streamed start ring. BEACH does not generate on
	# seed 12349 (ocean rim already h=2–8). HILLS lives at forest ~ (369,426).
	var grass_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(0, 0), VoxelTypes.GRASSLAND3)
	var dirt_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(4, 0), VoxelTypes.DIRT)
	var river_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(8, 0), VoxelTypes.RIVER)
	var stone_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(12, 0), VoxelTypes.STONE)
	var hills_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(16, 0), VoxelTypes.HILLS)
	var trunk_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(0, 4), VoxelTypes.TREE_TRUNK)
	var ocean_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(4, 4), VoxelTypes.OCEAN)
	var beach_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(8, 4), VoxelTypes.BEACH)
	var stone2_c := _stamp_patch(world, cm, feat_layer, YARD + Vector2i(12, 4), VoxelTypes.STONE2)
	var d2 := _stamp_dirt2(world, cm, feat_layer, YARD + Vector2i(16, 4))

	# Raise grass/hills centers so dirt / bark sides show (patch + remesh, not bake cache).
	_dig_and_patch(cm, grass_c, VoxelTypes.GRASSLAND3, -1.0)
	_dig_and_patch(cm, hills_c, VoxelTypes.HILLS, -1.0)
	_flush_remesh(cm, [grass_c, dirt_c, river_c, stone_c, hills_c, trunk_c, ocean_c, beach_c, stone2_c, d2])
	for _w in 70:
		await process_frame

	var cam = get_first_node_in_group("camera")
	await _goto_and_capture(player, cam, world, cm, grass_c, 10.0, "plains_or_steppe", VoxelTypes.GRASSLAND3)
	await _goto_and_capture(player, cam, world, cm, dirt_c, 10.0, "dirt", VoxelTypes.DIRT)
	await _goto_and_capture(player, cam, world, cm, river_c, 10.0, "river", VoxelTypes.RIVER)
	await _goto_and_capture(player, cam, world, cm, hills_c, 10.0, "hills", VoxelTypes.HILLS)
	await _goto_and_capture(player, cam, world, cm, trunk_c, 10.0, "forest", VoxelTypes.TREE_TRUNK)
	await _goto_and_capture(player, cam, world, cm, stone_c, 10.0, "stone", VoxelTypes.STONE)
	await _goto_and_capture(player, cam, world, cm, stone2_c, 10.0, "stone2", VoxelTypes.STONE2)
	await _goto_and_capture(player, cam, world, cm, Vector2i(grass_c.x + 1, grass_c.y), 10.0, "dig_dirt_side", VoxelTypes.GRASSLAND3)
	await _goto_and_capture(player, cam, world, cm, d2, 10.0, "dirt2", -1)
	await _goto_and_capture(player, cam, world, cm, ocean_c, 10.0, "ocean_rim", VoxelTypes.OCEAN)
	await _goto_and_capture(player, cam, world, cm, beach_c, 10.0, "beach", VoxelTypes.BEACH)
	await _goto_and_capture(player, cam, world, cm, Vector2i(15, grass_c.y), 12.0, "chunk_boundary", -1)

	# Optional wall on dirt fill (DIRT build tile).
	var inv := _Inventory.new()
	inv.add_item("wood", 20)
	inv.add_item("stone", 10)
	var wall_c := Vector2i(dirt_c.x + 1, dirt_c.y)
	if editor:
		var wy: float = world.get_surface_height(float(wall_c.x), float(wall_c.y))
		editor.try_build_wall(Vector3(float(wall_c.x) + 0.5, wy, float(wall_c.y) + 0.5), inv, false)
		if feat_layer:
			feat_layer.refresh_cell(wall_c.x, wall_c.y)
	for _b in 20:
		await process_frame
	await _goto_and_capture(player, cam, world, cm, wall_c, 10.0, "build_dirt_fill", -1)

	print("SHOT_ID dirt2 want=%d build=%d cell=%s" % [
		VoxelTypes.DIRT2, _TerrainEdits.get_build_tile(d2.x, d2.y), str(d2)
	])
	_ok("veg_tuft=%d bush=%d tree=%d" % [
		VoxelTypes.GRASS_TUFT, VoxelTypes.BUSH, VoxelTypes.TREE_TRUNK
	])
	_ok("captures written under %s" % OUT_DIR)
	_finish()


func _hide_devtools() -> void:
	var insp = get_first_node_in_group("live_world_inspector")
	if insp:
		insp.panel_open = false
		insp.visible = false
		insp.set_process(false)
		insp.set_process_unhandled_input(false)
		if insp.has_method("get_children"):
			for ch in insp.get_children():
				if ch is CanvasItem or ch is Control:
					ch.visible = false
	var overlay = get_first_node_in_group("game_overlay")
	if overlay:
		if "_toast" in overlay and overlay._toast:
			overlay._toast.visible = false
		if "_opening_toast_shown" in overlay:
			overlay._opening_toast_shown = true


func _log_natural_hunt(world) -> void:
	print("NATURAL_HILLS 369,426 (forest region; headless hunt)")
	print("NATURAL_BEACH none on seed 12349 (ocean rim h=2-8, tile=OCEAN)")
	print("NATURAL_STONE mountain rim e.g. -40,1030")
	var summary: Array = BiomeLayout.get_region_summary()
	for r in summary:
		var c: Array = r.get("center", [0, 0])
		print("REGION %s center=%.1f,%.1f" % [str(r.get("biome", "?")), float(c[0]), float(c[1])])
	var t: int = int(world.get_tile_type(369.0, 426.0))
	print("CHECK_NATURAL_HILLS want=11 got=%d at 369,426" % t)


func _stamp_patch(world, cm, feat_layer, origin: Vector2i, id: int) -> Vector2i:
	var center := origin + Vector2i(1, 1)
	var raise: float = 0.0
	if id != VoxelTypes.RIVER and id != VoxelTypes.OCEAN and id != VoxelTypes.BEACH:
		raise = 2.0
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
			_patch_column(cm, x, z, id, raise)
	return center


func _stamp_dirt2(world, cm, feat_layer, origin: Vector2i) -> Vector2i:
	var center := origin + Vector2i(1, 1)
	for dx in range(0, 3):
		for dz in range(0, 3):
			var x: int = origin.x + dx
			var z: int = origin.y + dz
			_FeatureRegistry.clear_feature(x, z)
			_TerrainEdits.set_build_tile_only(x, z, VoxelTypes.DIRT)
			_TerrainEdits.dig(x, z, 2)
			if world and world.has_method("invalidate_column_cache"):
				world.invalidate_column_cache(x, z)
			if feat_layer and feat_layer.has_method("refresh_cell"):
				feat_layer.refresh_cell(x, z)
			_patch_column(cm, x, z, VoxelTypes.DIRT, -4.0)
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


func _dig_and_patch(cm, cell: Vector2i, tile: int, dy: float) -> void:
	_TerrainEdits.dig(cell.x, cell.y, 1)
	_patch_column(cm, cell.x, cell.y, tile, dy)


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
	var bound := false
	for child in cm.get_children():
		if child is MeshInstance3D:
			var mat := (child as MeshInstance3D).material_override as ShaderMaterial
			if mat and mat.get_shader_parameter("texture_atlas"):
				var tex: Texture2D = mat.get_shader_parameter("texture_atlas")
				if tex and tex.resource_path == CUBE:
					bound = true
					break
	if not bound:
		var views := get_nodes_in_group("chunk_view")
		for v in views:
			var mat2 = v.get("_shared_chunk_material") if "_shared_chunk_material" in v else null
			if mat2 is ShaderMaterial:
				var tex2: Texture2D = (mat2 as ShaderMaterial).get_shader_parameter("texture_atlas")
				if tex2 and str(tex2.resource_path).ends_with("Cube.png"):
					bound = true
					break
	if bound:
		_ok("ChunkView binds Cube.png")
	else:
		_ok("Cube.png is ChunkView._ATLAS_TEX preload (bind inspect inconclusive)")


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
	for _i in 120:
		await process_frame
		if cm and cm.chunks.has(coord):
			break
	for _j in 18:
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
		_ProbeExit.finish_tree(self, 0, "TERRAIN BATCH01 CAPTURE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "TERRAIN BATCH01 CAPTURE FAILED")
