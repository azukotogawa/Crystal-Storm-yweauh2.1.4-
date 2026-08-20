extends SceneTree
## Boot main.tscn, stamp a ruin landmark beside walls/gate, capture gameplay shots.
## Usage: godot --path . -s scripts/verify_ruin_pillar_visual_capture.gd
## Do NOT pass --headless.


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const RUIN_MESH_PATH := "res://assets/structures/ruin_pillar/ruin_pillar.obj"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const GATE_MESH_PATH := "res://assets/structures/gate/gate.obj"
const BRIDGE_MESH_PATH := "res://assets/structures/bridge/bridge.obj"
const OUT_DIR := "C:/users/cwith/weed/crystalstorm/.tmp_ruin_pillar_capture"

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
	if player == null or feat_layer == null:
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
		if "ruin_guardian_count" in lwd:
			lwd.ruin_guardian_count = 0
	var em = get_first_node_in_group("entity_manager")
	if em:
		em.set_process(false)
	for _boot in 40:
		await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if feat_layer.has_method("_bind_terrain_placement_refresh"):
		feat_layer._bind_terrain_placement_refresh()

	var inv := _Inventory.new()
	inv.add_item("wood", 40)
	inv.add_item("stone", 20)

	var px := 12
	var pz := 12
	_frame_camera(player, get_first_node_in_group("camera"), world, px + 4, pz + 1, 16.0)
	var center := Vector2i(px + 4, pz)
	var edge := Vector2i(px + 6, pz)
	var wood_c := Vector2i(px + 2, pz)
	var stone_c := Vector2i(px + 7, pz)
	var gate_c := Vector2i(px + 4, pz + 2)
	var bridge_c := Vector2i(px + 2, pz + 2)

	_FeatureRegistry.register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": center, "name": "Capture Ruin"
	})
	_FeatureRegistry.register_feature(edge.x, edge.y, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": center, "name": "Capture Ruin"
	})
	feat_layer.refresh_cell(center.x, center.y)
	feat_layer.refresh_cell(edge.x, edge.y)
	_place_wall(editor, feat_layer, world, inv, wood_c, false)
	_place_wall(editor, feat_layer, world, inv, stone_c, true)
	_place_gate(editor, feat_layer, world, inv, gate_c)
	_place_bridge(editor, feat_layer, inv, bridge_c)
	for _j in 45:
		await process_frame
	for n in get_nodes_in_group("crystal_enemy"):
		n.visible = false
	for n in get_nodes_in_group("world_entity"):
		n.visible = false

	var a: Node3D = feat_layer._nodes_by_cell.get(center)
	if a == null or str(a.get_meta("building_visual_id", "")) != "ruin_pillar":
		_fail("center ruin missing")
	elif str((a.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
		_fail("center not authored")
	else:
		_ok("authored ruin at center")
	if feat_layer._nodes_by_cell.get(edge) != null:
		_fail("edge got a pillar")
	else:
		_ok("edge has no pillar")
	_assert_id(feat_layer, wood_c, "wood_wall", WOOD_MESH_PATH)
	_assert_id(feat_layer, stone_c, "stone_wall", STONE_MESH_PATH)
	_assert_id(feat_layer, gate_c, "gate", GATE_MESH_PATH)
	_assert_id(feat_layer, bridge_c, "bridge", BRIDGE_MESH_PATH)

	var cam = get_first_node_in_group("camera")
	_frame_camera(player, cam, world, center.x, center.y, 10.0)
	await _capture("isolated_ruin")
	_frame_camera(player, cam, world, px + 4, pz + 1, 13.0)
	await _capture("ruin_beside_walls_gate")
	_frame_camera(player, cam, world, wood_c.x, wood_c.y, 10.0)
	await _capture("beside_wood")
	_frame_camera(player, cam, world, stone_c.x, stone_c.y, 10.0)
	await _capture("beside_stone")

	feat_layer.refresh_cell(center.x, center.y)
	await process_frame
	var again: Node3D = feat_layer._nodes_by_cell.get(center)
	if again == null or str((again.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
		_fail("refresh lost authored ruin")
	else:
		_ok("refresh keeps authored ruin")
	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var streamed: Node3D = feat_layer._nodes_by_cell.get(center)
	if streamed == null or str((streamed.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
		_fail("stream lost authored ruin")
	else:
		_ok("stream keeps authored ruin")
	_frame_camera(player, cam, world, center.x, center.y, 10.0)
	await _capture("after_stream_repopulate")
	_ok("captures written under %s" % OUT_DIR)
	_finish()


func _place_wall(editor, feat_layer, world, inv, c: Vector2i, stone: bool) -> void:
	_FeatureRegistry.clear_feature(c.x, c.y)
	var y: float = world.get_surface_height(float(c.x), float(c.y))
	if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv, stone):
		_fail("place wall %s: %s" % [str(c), editor.last_fail_reason])
	feat_layer.refresh_cell(c.x, c.y)


func _place_gate(editor, feat_layer, world, inv, c: Vector2i) -> void:
	_FeatureRegistry.clear_feature(c.x, c.y)
	var y: float = world.get_surface_height(float(c.x), float(c.y))
	if not editor.try_build_gate(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv):
		_fail("place gate %s: %s" % [str(c), editor.last_fail_reason])
	feat_layer.refresh_cell(c.x, c.y)


func _place_bridge(editor, feat_layer, inv, c: Vector2i) -> void:
	_FeatureRegistry.clear_feature(c.x, c.y)
	_TerrainEdits.dig(c.x, c.y, 1)
	if not editor.try_build_bridge(Vector3(float(c.x) + 0.5, 0.0, float(c.y) + 0.5), inv):
		_fail("place bridge %s: %s" % [str(c), editor.last_fail_reason])
	feat_layer.refresh_cell(c.x, c.y)


func _assert_id(feat_layer, c: Vector2i, id: String, path: String) -> void:
	var a: Node3D = feat_layer._nodes_by_cell.get(c)
	if a == null or str(a.get_meta("building_visual_id", "")) != id:
		_fail("%s missing at %s" % [id, str(c)])
		return
	if str((a.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != path:
		_fail("%s authored bind lost" % id)
	else:
		_ok("%s still authored" % id)


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
	if vp == null or vp.get_texture() == null:
		_fail("no viewport for %s" % name)
		return
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		_fail("empty image %s" % name)
		return
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("SHOT %s/%s.png %dx%d" % [OUT_DIR, name, img.get_width(), img.get_height()])


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "RUIN PILLAR VISUAL CAPTURE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "RUIN PILLAR VISUAL CAPTURE FAILED")
