extends SceneTree
## Live main scene: place stone walls in mixed arrangements; assert authored mesh bind.
## Also places wood_wall to prove no authored-path regression.
## Usage: godot --path . -s scripts/verify_stone_wall_live_place.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"

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
	inv.add_item("stone", 50)
	inv.add_item("wood", 20)

	var placements: Array[Dictionary] = []
	for i in 4:
		placements.append({"id": "stone_wall", "cell": Vector2i(px + 2 + i, pz)})
	placements.append({"id": "stone_wall", "cell": Vector2i(px + 2, pz + 1)})
	placements.append({"id": "stone_wall", "cell": Vector2i(px + 2, pz + 2)})
	placements.append({"id": "stone_wall", "cell": Vector2i(px + 4, pz + 1)})
	placements.append({"id": "stone_wall", "cell": Vector2i(px + 5, pz + 2)})
	var dig_cell := Vector2i(px + 7, pz)
	_TerrainEdits.dig(dig_cell.x, dig_cell.y, 1)
	placements.append({"id": "stone_wall", "cell": Vector2i(px + 8, pz)})
	var gate_cell := Vector2i(px + 3, pz + 4)
	var bridge_cell := Vector2i(px + 6, pz + 4)
	_TerrainEdits.dig(bridge_cell.x, bridge_cell.y, 1)
	var wood_cell := Vector2i(px + 9, pz + 2)

	for p in placements:
		var c: Vector2i = p.cell
		_FeatureRegistry.clear_feature(c.x, c.y)
		var y: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv, true):
			_fail("place stone %s: %s" % [str(c), editor.last_fail_reason])
		else:
			feat_layer.refresh_cell(c.x, c.y)

	var gy: float = world.get_surface_height(float(gate_cell.x), float(gate_cell.y))
	if not editor.try_build_gate(Vector3(float(gate_cell.x) + 0.5, gy, float(gate_cell.y) + 0.5), inv):
		_fail("gate: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(gate_cell.x, gate_cell.y)
	if not editor.try_build_bridge(Vector3(float(bridge_cell.x) + 0.5, 0.0, float(bridge_cell.y) + 0.5), inv):
		_fail("bridge: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(bridge_cell.x, bridge_cell.y)

	var near_gate := Vector2i(gate_cell.x + 1, gate_cell.y)
	var near_bridge := Vector2i(bridge_cell.x + 1, bridge_cell.y)
	for c in [near_gate, near_bridge]:
		var y2: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y2, float(c.y) + 0.5), inv, true):
			_fail("near structure stone %s: %s" % [str(c), editor.last_fail_reason])
		feat_layer.refresh_cell(c.x, c.y)
		placements.append({"id": "stone_wall", "cell": c})

	_FeatureRegistry.clear_feature(wood_cell.x, wood_cell.y)
	var yw: float = world.get_surface_height(float(wood_cell.x), float(wood_cell.y))
	if not editor.try_build_wall(Vector3(float(wood_cell.x) + 0.5, yw, float(wood_cell.y) + 0.5), inv, false):
		_fail("wood regression place: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(wood_cell.x, wood_cell.y)

	await process_frame
	await process_frame

	var wall_count := 0
	for p in placements:
		var c: Vector2i = p.cell
		var anchor: Node3D = feat_layer._nodes_by_cell.get(c)
		if anchor == null:
			_fail("no anchor %s" % str(c))
			continue
		if str(anchor.get_meta("building_visual_id", "")) != "stone_wall":
			_fail("id not stone_wall at %s (%s)" % [str(c), anchor.get_meta("building_visual_id", "")])
			continue
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("not authored at %s" % str(c))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
			_fail("path meta wrong at %s" % str(c))
			continue
		if mesh.mesh == null or mesh.material_override == null:
			_fail("mesh/material null at %s" % str(c))
			continue
		wall_count += 1

	_ok("placed %d stone walls with authored mesh (target ~10+)" % wall_count)
	if wall_count < 10:
		_fail("expected at least 10 authored stone walls, got %d" % wall_count)

	var wa: Node3D = feat_layer._nodes_by_cell.get(wood_cell)
	if wa and str(wa.get_meta("building_visual_id", "")) == "wood_wall":
		var wm: MeshInstance3D = wa.get_node_or_null("Mesh") as MeshInstance3D
		if wm and bool(wm.get_meta("uses_authored_mesh", false)) \
				and str(wm.get_meta("authored_resource_path", "")) == WOOD_MESH_PATH:
			_ok("wood_wall still authored after stone placement")
		else:
			_fail("wood_wall authored bind regressed")
	else:
		_fail("wood_wall visual broken beside stone")

	var ga: Node3D = feat_layer._nodes_by_cell.get(gate_cell)
	var ba: Node3D = feat_layer._nodes_by_cell.get(bridge_cell)
	if ga and str(ga.get_meta("building_visual_id", "")) == "gate":
		_ok("gate remains gate near stone walls")
	else:
		_fail("gate visual broken")
	if ba and str(ba.get_meta("building_visual_id", "")) == "bridge":
		_ok("bridge remains bridge near stone walls")
	else:
		_fail("bridge visual broken")

	var reg = get_first_node_in_group("game_visual_registry")
	if reg and reg.has_method("has_authored_building_mesh") \
			and reg.has_authored_building_mesh("stone_wall") \
			and reg.has_authored_building_mesh("wood_wall"):
		_ok("registry has authored stone_wall and wood_wall")
	else:
		_fail("registry missing authored stone or wood")

	_ok("arrangements: line, corner, staggered, dig-adjacent, near-gate, near-bridge")
	_finish()


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All stone_wall live place tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "STONE WALL LIVE PLACE FAILED")
