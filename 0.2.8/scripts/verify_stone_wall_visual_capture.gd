extends SceneTree
## Boot main.tscn, place stone_wall + wood_wall, capture gameplay-camera screenshots.
## Usage: godot --path . -s scripts/verify_stone_wall_visual_capture.gd
## Do NOT pass --headless (screenshots go black).


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const OUT_DIR := "C:/users/cwith/weed/crystalstorm/.tmp_stone_wall_capture"

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
		if player and cm and feat_layer and editor and world and registry \
				and cm.chunks.size() > 0 \
				and registry.has_method("is_ready") and registry.is_ready():
			break
	if player == null or feat_layer == null:
		_fail("boot missing systems")
		_finish()
		return

	var crystal = get_first_node_in_group("crystal_manager")
	if crystal:
		crystal.set_process(false)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var px := 12
	var pz := 12
	var sy: float = world.get_surface_height(float(px), float(pz))
	player.voxel_position = Vector3(float(px) + 0.5, sy + 2.0, float(pz) + 0.5)
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()

	var cam = get_first_node_in_group("camera")
	if cam:
		cam.zoom_level = 16.0
		cam.size = 16.0
		if cam.has_method("_update_camera_transform"):
			cam._update_camera_transform()

	if feat_layer.has_method("_bind_terrain_placement_refresh"):
		feat_layer._bind_terrain_placement_refresh()

	var inv := _Inventory.new()
	inv.add_item("stone", 80)
	inv.add_item("wood", 40)

	var isolated := Vector2i(px + 2, pz)
	var line_x: Array[Vector2i] = [
		Vector2i(px + 4, pz), Vector2i(px + 5, pz), Vector2i(px + 6, pz), Vector2i(px + 7, pz)
	]
	var corner: Array[Vector2i] = [
		Vector2i(px + 2, pz + 3), Vector2i(px + 2, pz + 4), Vector2i(px + 2, pz + 5),
		Vector2i(px + 3, pz + 5), Vector2i(px + 4, pz + 5)
	]
	var wood_line: Array[Vector2i] = [
		Vector2i(px + 4, pz + 2), Vector2i(px + 5, pz + 2), Vector2i(px + 6, pz + 2)
	]
	var dig_cell := Vector2i(px + 9, pz)
	_TerrainEdits.dig(dig_cell.x, dig_cell.y, 1)
	var by_terrain := Vector2i(px + 10, pz)
	var gate_cell := Vector2i(px + 5, pz + 4)
	var by_gate := Vector2i(px + 6, pz + 4)
	var boundary: Array[Vector2i] = [
		Vector2i(14, pz + 8), Vector2i(15, pz + 8), Vector2i(16, pz + 8), Vector2i(17, pz + 8)
	]

	var all_stone: Array[Vector2i] = [isolated, by_terrain, by_gate]
	all_stone.append_array(line_x)
	all_stone.append_array(corner)
	all_stone.append_array(boundary)

	for c in all_stone:
		_FeatureRegistry.clear_feature(c.x, c.y)
		var y: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv, true):
			_fail("place stone %s: %s" % [str(c), editor.last_fail_reason])
		feat_layer.refresh_cell(c.x, c.y)
		if feat_layer.has_method("_refresh_wood_wall_neighbors"):
			feat_layer._refresh_wood_wall_neighbors(c.x, c.y)

	for c in wood_line:
		_FeatureRegistry.clear_feature(c.x, c.y)
		var y: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv, false):
			_fail("place wood %s: %s" % [str(c), editor.last_fail_reason])
		feat_layer.refresh_cell(c.x, c.y)
		if feat_layer.has_method("_refresh_wood_wall_neighbors"):
			feat_layer._refresh_wood_wall_neighbors(c.x, c.y)

	var gy: float = world.get_surface_height(float(gate_cell.x), float(gate_cell.y))
	if not editor.try_build_gate(Vector3(float(gate_cell.x) + 0.5, gy, float(gate_cell.y) + 0.5), inv):
		_fail("gate: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(gate_cell.x, gate_cell.y)

	for _j in 45:
		await process_frame

	var authored := 0
	for c in all_stone:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(c)
		if anchor == null:
			_fail("no stone anchor %s" % str(c))
			continue
		var vid := str(anchor.get_meta("building_visual_id", ""))
		if vid != "stone_wall":
			_fail("id %s at %s" % [vid, str(c)])
			continue
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("stone not authored at %s" % str(c))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
			_fail("stone path %s" % mesh.get_meta("authored_resource_path", ""))
			continue
		authored += 1
	_ok("authored stone walls=%d / %d" % [authored, all_stone.size()])
	if authored < all_stone.size():
		_fail("missing authored stone walls")

	var wood_ok := 0
	for c in wood_line:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(c)
		if anchor == null:
			_fail("no wood anchor %s" % str(c))
			continue
		if str(anchor.get_meta("building_visual_id", "")) != "wood_wall":
			_fail("wood id broken at %s" % str(c))
			continue
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or str(mesh.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
			_fail("wood authored bind lost at %s" % str(c))
			continue
		wood_ok += 1
	_ok("wood_wall still authored %d / %d" % [wood_ok, wood_line.size()])

	_frame_camera(player, cam, world, px + 5, pz + 1, 16.0)
	await _capture("overview_stone_and_wood")

	_frame_camera(player, cam, world, isolated.x, isolated.y, 9.0)
	await _capture("isolated_stone")

	_frame_camera(player, cam, world, px + 5, pz, 11.0)
	await _capture("stone_line")

	_frame_camera(player, cam, world, px + 5, pz + 2, 11.0)
	await _capture("stone_beside_wood")

	_frame_camera(player, cam, world, px + 3, pz + 5, 12.0)
	await _capture("stone_corner")

	_frame_camera(player, cam, world, gate_cell.x, gate_cell.y, 11.0)
	await _capture("beside_gate")

	_frame_camera(player, cam, world, by_terrain.x, by_terrain.y, 11.0)
	await _capture("beside_terrain")

	_frame_camera(player, cam, world, 15, pz + 8, 12.0)
	await _capture("chunk_boundary")

	var mid := line_x[1]
	_FeatureRegistry.clear_feature(mid.x, mid.y)
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	if feat_layer._nodes_by_cell.get(mid) != null:
		_fail("stale node after remove")
	else:
		_ok("remove cleared visual")
	_frame_camera(player, cam, world, px + 5, pz, 11.0)
	await _capture("after_remove")

	inv.add_item("stone", 4)
	var y2: float = world.get_surface_height(float(mid.x), float(mid.y))
	if not editor.try_build_wall(Vector3(float(mid.x) + 0.5, y2, float(mid.y) + 0.5), inv, true):
		_fail("rebuild: %s" % editor.last_fail_reason)
	feat_layer.refresh_cell(mid.x, mid.y)
	if feat_layer.has_method("_refresh_wood_wall_neighbors"):
		feat_layer._refresh_wood_wall_neighbors(mid.x, mid.y)
	for _k in 20:
		await process_frame
	var rebuilt: Node3D = feat_layer._nodes_by_cell.get(mid)
	if rebuilt == null or str(rebuilt.get_meta("building_visual_id", "")) != "stone_wall":
		_fail("rebuild lost stone_wall")
	else:
		var rm: MeshInstance3D = rebuilt.get_node_or_null("Mesh") as MeshInstance3D
		if rm == null or not bool(rm.get_meta("uses_authored_mesh", false)):
			_fail("rebuild not authored")
		else:
			_ok("rebuild authored")
	_frame_camera(player, cam, world, px + 5, pz, 11.0)
	await _capture("after_rebuild")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var a0: Node3D = feat_layer._nodes_by_cell.get(isolated)
	if a0 == null:
		_fail("stream repopulate lost isolated wall")
	else:
		var m0: MeshInstance3D = a0.get_node_or_null("Mesh") as MeshInstance3D
		if m0 == null or not bool(m0.get_meta("uses_authored_mesh", false)):
			_fail("stream lost authored bind")
		else:
			_ok("stream repopulate keeps authored mesh")
	_frame_camera(player, cam, world, isolated.x, isolated.y, 10.0)
	await _capture("after_stream_repopulate")

	_ok("captures written under %s" % OUT_DIR)
	_finish()


func _frame_camera(player, cam, world, wx: int, wz: int, zoom: float = 14.0) -> void:
	# Stand one cell southwest so the player cube does not hide the prop.
	var sy: float = world.get_surface_height(float(wx - 1), float(wz - 1))
	player.voxel_position = Vector3(float(wx) - 0.5, sy + 1.5, float(wz) - 0.5)
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
	if vp == null:
		_fail("no viewport for %s" % name)
		return
	var tex: Texture2D = vp.get_texture()
	if tex == null:
		_fail("no tex %s" % name)
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		_fail("empty image %s" % name)
		return
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("SHOT %s %dx%d" % [path, img.get_width(), img.get_height()])


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "STONE WALL VISUAL CAPTURE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "STONE WALL VISUAL CAPTURE FAILED")
