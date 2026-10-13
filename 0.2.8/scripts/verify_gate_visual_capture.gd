extends SceneTree
## Boot main.tscn, place gates beside wood/stone walls, capture gameplay-camera shots.
## Usage: godot --path . -s scripts/verify_gate_visual_capture.gd
## Do NOT pass --headless (screenshots go black).


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const GATE_MESH_PATH := "res://assets/structures/gate/gate.obj"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const OUT_DIR := "C:/users/cwith/weed/crystalstorm/.tmp_gate_capture"

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
	_frame_camera(player, get_first_node_in_group("camera"), world, px + 4, pz + 1, 16.0)

	if feat_layer.has_method("_bind_terrain_placement_refresh"):
		feat_layer._bind_terrain_placement_refresh()

	var inv := _Inventory.new()
	inv.add_item("wood", 80)
	inv.add_item("stone", 40)

	var isolated := Vector2i(px + 2, pz)
	# Wood line with a gate in the middle
	var wood_line: Array[Vector2i] = [
		Vector2i(px + 4, pz), Vector2i(px + 6, pz), Vector2i(px + 7, pz)
	]
	var gate_in_wood := Vector2i(px + 5, pz)
	# Stone line with a gate
	var stone_line: Array[Vector2i] = [
		Vector2i(px + 4, pz + 3), Vector2i(px + 6, pz + 3)
	]
	var gate_in_stone := Vector2i(px + 5, pz + 3)
	# Isolated pair of gates (NS run so yaw flips)
	var ns_gates: Array[Vector2i] = [
		Vector2i(px + 9, pz), Vector2i(px + 9, pz + 1), Vector2i(px + 9, pz + 2)
	]
	var boundary: Array[Vector2i] = [
		Vector2i(15, pz + 8), Vector2i(16, pz + 8)
	]

	for c in wood_line:
		_place_wall(editor, feat_layer, world, inv, c, false)
	for c in stone_line:
		_place_wall(editor, feat_layer, world, inv, c, true)
	for c in [isolated, gate_in_wood, gate_in_stone]:
		_place_gate(editor, feat_layer, world, inv, c)
	for c in ns_gates:
		_place_gate(editor, feat_layer, world, inv, c)
	for c in boundary:
		_place_gate(editor, feat_layer, world, inv, c)

	for _j in 45:
		await process_frame

	var authored := 0
	var all_gates: Array[Vector2i] = [isolated, gate_in_wood, gate_in_stone]
	all_gates.append_array(ns_gates)
	all_gates.append_array(boundary)
	for c in all_gates:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(c)
		if anchor == null or str(anchor.get_meta("building_visual_id", "")) != "gate":
			_fail("gate missing/wrong at %s" % str(c))
			continue
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or str(mesh.get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
			_fail("gate not authored at %s" % str(c))
			continue
		authored += 1
	_ok("authored gates=%d / %d" % [authored, all_gates.size()])

	_assert_wall(feat_layer, wood_line[0], "wood_wall", WOOD_MESH_PATH)
	_assert_wall(feat_layer, stone_line[0], "stone_wall", STONE_MESH_PATH)

	var cam = get_first_node_in_group("camera")
	_frame_camera(player, cam, world, px + 5, pz + 1, 16.0)
	await _capture("overview_gate_and_walls")

	_frame_camera(player, cam, world, isolated.x, isolated.y, 10.0)
	await _capture("isolated_gate")

	_frame_camera(player, cam, world, gate_in_wood.x, gate_in_wood.y, 11.0)
	await _capture("gate_in_wood_line")

	_frame_camera(player, cam, world, gate_in_stone.x, gate_in_stone.y, 11.0)
	await _capture("gate_in_stone_line")

	_frame_camera(player, cam, world, px + 9, pz + 1, 11.0)
	await _capture("gate_ns_run")

	_frame_camera(player, cam, world, 15, pz + 8, 12.0)
	await _capture("chunk_boundary")

	_FeatureRegistry.clear_feature(isolated.x, isolated.y)
	feat_layer.refresh_cell(isolated.x, isolated.y)
	await process_frame
	if feat_layer._nodes_by_cell.get(isolated) != null:
		_fail("stale node after remove")
	else:
		_ok("remove cleared visual")
	_frame_camera(player, cam, world, isolated.x, isolated.y, 10.0)
	await _capture("after_remove")

	inv.add_item("wood", 4)
	_place_gate(editor, feat_layer, world, inv, isolated)
	for _k in 20:
		await process_frame
	var rebuilt: Node3D = feat_layer._nodes_by_cell.get(isolated)
	if rebuilt == null or str((rebuilt.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
		_fail("rebuild not authored gate")
	else:
		_ok("rebuild authored")
	_frame_camera(player, cam, world, isolated.x, isolated.y, 10.0)
	await _capture("after_rebuild")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var a0: Node3D = feat_layer._nodes_by_cell.get(isolated)
	if a0 == null or str((a0.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
		_fail("stream lost authored gate")
	else:
		_ok("stream repopulate keeps authored gate")
	_frame_camera(player, cam, world, isolated.x, isolated.y, 10.0)
	await _capture("after_stream_repopulate")

	_ok("captures written under %s" % OUT_DIR)
	_finish()


func _place_gate(editor, feat_layer, world, inv, c: Vector2i) -> void:
	_FeatureRegistry.clear_feature(c.x, c.y)
	var y: float = world.get_surface_height(float(c.x), float(c.y))
	if not editor.try_build_gate(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv):
		_fail("place gate %s: %s" % [str(c), editor.last_fail_reason])
	feat_layer.refresh_cell(c.x, c.y)
	if feat_layer.has_method("_refresh_wood_wall_neighbors"):
		feat_layer._refresh_wood_wall_neighbors(c.x, c.y)


func _place_wall(editor, feat_layer, world, inv, c: Vector2i, stone: bool) -> void:
	_FeatureRegistry.clear_feature(c.x, c.y)
	var y: float = world.get_surface_height(float(c.x), float(c.y))
	if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv, stone):
		_fail("place wall %s: %s" % [str(c), editor.last_fail_reason])
	feat_layer.refresh_cell(c.x, c.y)
	if feat_layer.has_method("_refresh_wood_wall_neighbors"):
		feat_layer._refresh_wood_wall_neighbors(c.x, c.y)


func _assert_wall(feat_layer, c: Vector2i, id: String, path: String) -> void:
	var a: Node3D = feat_layer._nodes_by_cell.get(c)
	if a == null or str(a.get_meta("building_visual_id", "")) != id:
		_fail("%s missing at %s" % [id, str(c)])
		return
	var m: MeshInstance3D = a.get_node_or_null("Mesh") as MeshInstance3D
	if m == null or str(m.get_meta("authored_resource_path", "")) != path:
		_fail("%s authored bind lost at %s" % [id, str(c)])
	else:
		_ok("%s still authored at %s" % [id, str(c)])


func _frame_camera(player, cam, world, wx: int, wz: int, zoom: float = 14.0) -> void:
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
		_ProbeExit.finish_tree(self, 0, "GATE VISUAL CAPTURE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "GATE VISUAL CAPTURE FAILED")
