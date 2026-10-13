extends SceneTree
## Live main scene: place gates in mixed arrangements; assert authored mesh bind.
## Also places wood_wall + stone_wall to prove no authored-path regression.
## Usage: godot --path . -s scripts/verify_gate_live_place.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const GATE_MESH_PATH := "res://assets/structures/gate/gate.obj"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"

var _failed: int = 0
var _lines: PackedStringArray = []


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	_lines.append("FAIL: %s" % msg)
	push_error(msg)


func _ok(msg: String) -> void:
	_lines.append("OK: %s" % msg)
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
	inv.add_item("stone", 20)

	var placements: Array[Vector2i] = []
	for i in 4:
		placements.append(Vector2i(px + 2 + i, pz))
	placements.append(Vector2i(px + 2, pz + 1))
	placements.append(Vector2i(px + 2, pz + 2))
	placements.append(Vector2i(px + 4, pz + 1))
	var wood_cell := Vector2i(px + 6, pz)
	var stone_cell := Vector2i(px + 7, pz)
	var bridge_cell := Vector2i(px + 5, pz + 3)
	_TerrainEdits.dig(bridge_cell.x, bridge_cell.y, 1)

	for c in placements:
		_FeatureRegistry.clear_feature(c.x, c.y)
		var y: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_gate(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv):
			_fail("place gate %s: %s" % [str(c), editor.last_fail_reason])
		else:
			feat_layer.refresh_cell(c.x, c.y)

	_FeatureRegistry.clear_feature(wood_cell.x, wood_cell.y)
	var yw: float = world.get_surface_height(float(wood_cell.x), float(wood_cell.y))
	if not editor.try_build_wall(Vector3(float(wood_cell.x) + 0.5, yw, float(wood_cell.y) + 0.5), inv, false):
		_fail("wood place: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(wood_cell.x, wood_cell.y)

	_FeatureRegistry.clear_feature(stone_cell.x, stone_cell.y)
	var ys: float = world.get_surface_height(float(stone_cell.x), float(stone_cell.y))
	if not editor.try_build_wall(Vector3(float(stone_cell.x) + 0.5, ys, float(stone_cell.y) + 0.5), inv, true):
		_fail("stone place: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(stone_cell.x, stone_cell.y)

	if not editor.try_build_bridge(Vector3(float(bridge_cell.x) + 0.5, 0.0, float(bridge_cell.y) + 0.5), inv):
		_fail("bridge: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(bridge_cell.x, bridge_cell.y)

	# Gate next to wood and stone
	var near_wood := Vector2i(wood_cell.x, wood_cell.y + 1)
	var y2: float = world.get_surface_height(float(near_wood.x), float(near_wood.y))
	if editor.try_build_gate(Vector3(float(near_wood.x) + 0.5, y2, float(near_wood.y) + 0.5), inv):
		feat_layer.refresh_cell(near_wood.x, near_wood.y)
		placements.append(near_wood)
	else:
		_fail("near-wood gate: %s" % editor.last_fail_reason)

	await process_frame
	await process_frame

	var gate_count := 0
	for c in placements:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(c)
		if anchor == null:
			_fail("no anchor %s" % str(c))
			continue
		if str(anchor.get_meta("building_visual_id", "")) != "gate":
			_fail("id not gate at %s (%s)" % [str(c), anchor.get_meta("building_visual_id", "")])
			continue
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("not authored at %s" % str(c))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
			_fail("path meta wrong at %s" % str(c))
			continue
		if mesh.mesh == null or mesh.material_override == null:
			_fail("mesh/material null at %s" % str(c))
			continue
		gate_count += 1

	_ok("placed %d gates with authored mesh" % gate_count)
	if gate_count < 8:
		_fail("expected at least 8 authored gates, got %d" % gate_count)

	var wa: Node3D = feat_layer._nodes_by_cell.get(wood_cell)
	if wa and str(wa.get_meta("building_visual_id", "")) == "wood_wall" \
			and str((wa.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) == WOOD_MESH_PATH:
		_ok("wood_wall still authored after gate placement")
	else:
		_fail("wood_wall authored bind regressed")

	var sa: Node3D = feat_layer._nodes_by_cell.get(stone_cell)
	if sa and str(sa.get_meta("building_visual_id", "")) == "stone_wall" \
			and str((sa.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) == STONE_MESH_PATH:
		_ok("stone_wall still authored after gate placement")
	else:
		_fail("stone_wall authored bind regressed")

	var ba: Node3D = feat_layer._nodes_by_cell.get(bridge_cell)
	if ba and str(ba.get_meta("building_visual_id", "")) == "bridge":
		_ok("bridge remains bridge near gates")
	else:
		_fail("bridge visual broken")

	var reg = get_first_node_in_group("game_visual_registry")
	if reg and reg.has_method("has_authored_building_mesh") \
			and reg.has_authored_building_mesh("gate") \
			and reg.has_authored_building_mesh("wood_wall") \
			and reg.has_authored_building_mesh("stone_wall"):
		_ok("registry has authored gate, wood_wall, stone_wall")
	else:
		_fail("registry missing authored gate or walls")

	_ok("arrangements: line, corner, near-wood, near-stone, near-bridge")
	_finish()


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All gate live place tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "GATE LIVE PLACE FAILED")
