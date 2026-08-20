extends SceneTree
## Live main scene: place bridges over digs; assert authored mesh bind.
## Also places wood/stone/gate to prove no authored-path regression.
## Usage: godot --path . -s scripts/verify_bridge_live_place.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const BRIDGE_MESH_PATH := "res://assets/structures/bridge/bridge.obj"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const GATE_MESH_PATH := "res://assets/structures/gate/gate.obj"

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


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
	for _i in 200:
		await process_frame
		var cm = get_first_node_in_group("chunk_manager")
		var feat = get_first_node_in_group("feature_visual_layer")
		var editor = get_first_node_in_group("terrain_editor")
		var world = get_first_node_in_group("world")
		if cm and feat and editor and world and cm.chunks.size() > 0:
			break
	await process_frame
	await process_frame

	var editor = get_first_node_in_group("terrain_editor")
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	var world = get_first_node_in_group("world")
	var player = get_first_node_in_group("player")
	if editor == null or feat_layer == null or world == null:
		_fail("boot missing systems")
		_finish()
		return
	if feat_layer.has_method("_bind_terrain_placement_refresh"):
		feat_layer._bind_terrain_placement_refresh()

	var px := 10
	var pz := 10
	if player and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		px = int(floor(pv.x))
		pz = int(floor(pv.z))

	var inv := _Inventory.new()
	inv.add_item("wood", 50)
	inv.add_item("stone", 10)

	var bridges: Array[Vector2i] = []
	for i in 4:
		bridges.append(Vector2i(px + 2 + i, pz))
	bridges.append(Vector2i(px + 2, pz + 1))
	bridges.append(Vector2i(px + 2, pz + 2))
	var wood_cell := Vector2i(px + 7, pz)
	var stone_cell := Vector2i(px + 8, pz)
	var gate_cell := Vector2i(px + 6, pz + 2)

	for c in bridges:
		_FeatureRegistry.clear_feature(c.x, c.y)
		_TerrainEdits.dig(c.x, c.y, 1)
		if not editor.try_build_bridge(Vector3(float(c.x) + 0.5, 0.0, float(c.y) + 0.5), inv):
			_fail("place bridge %s: %s" % [str(c), editor.last_fail_reason])
		else:
			feat_layer.refresh_cell(c.x, c.y)

	var yw: float = world.get_surface_height(float(wood_cell.x), float(wood_cell.y))
	if editor.try_build_wall(Vector3(float(wood_cell.x) + 0.5, yw, float(wood_cell.y) + 0.5), inv, false):
		feat_layer.refresh_cell(wood_cell.x, wood_cell.y)
	else:
		_fail("wood: %s" % editor.last_fail_reason)
	var ys: float = world.get_surface_height(float(stone_cell.x), float(stone_cell.y))
	if editor.try_build_wall(Vector3(float(stone_cell.x) + 0.5, ys, float(stone_cell.y) + 0.5), inv, true):
		feat_layer.refresh_cell(stone_cell.x, stone_cell.y)
	else:
		_fail("stone: %s" % editor.last_fail_reason)
	var yg: float = world.get_surface_height(float(gate_cell.x), float(gate_cell.y))
	if editor.try_build_gate(Vector3(float(gate_cell.x) + 0.5, yg, float(gate_cell.y) + 0.5), inv):
		feat_layer.refresh_cell(gate_cell.x, gate_cell.y)
	else:
		_fail("gate: %s" % editor.last_fail_reason)

	await process_frame
	await process_frame

	var n := 0
	for c in bridges:
		var a: Node3D = feat_layer._nodes_by_cell.get(c)
		if a == null or str(a.get_meta("building_visual_id", "")) != "bridge":
			_fail("bridge id broken at %s" % str(c))
			continue
		var m: MeshInstance3D = a.get_node_or_null("Mesh") as MeshInstance3D
		if m == null or str(m.get_meta("authored_resource_path", "")) != BRIDGE_MESH_PATH:
			_fail("bridge not authored at %s" % str(c))
			continue
		n += 1
	_ok("placed %d bridges with authored mesh" % n)
	if n < 6:
		_fail("expected at least 6 authored bridges, got %d" % n)

	_assert_path(feat_layer, wood_cell, "wood_wall", WOOD_MESH_PATH)
	_assert_path(feat_layer, stone_cell, "stone_wall", STONE_MESH_PATH)
	_assert_path(feat_layer, gate_cell, "gate", GATE_MESH_PATH)

	var reg = get_first_node_in_group("game_visual_registry")
	if reg and reg.has_authored_building_mesh("bridge") and reg.has_authored_building_mesh("gate"):
		_ok("registry has authored bridge and gate")
	else:
		_fail("registry missing authored bridge/gate")
	_ok("arrangements: line, corner, near-wood, near-stone, near-gate")
	_finish()


func _assert_path(feat_layer, c: Vector2i, id: String, path: String) -> void:
	var a: Node3D = feat_layer._nodes_by_cell.get(c)
	if a == null or str(a.get_meta("building_visual_id", "")) != id:
		_fail("%s missing" % id)
		return
	if str((a.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != path:
		_fail("%s authored bind regressed" % id)
	else:
		_ok("%s still authored" % id)


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All bridge live place tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "BRIDGE LIVE PLACE FAILED")
