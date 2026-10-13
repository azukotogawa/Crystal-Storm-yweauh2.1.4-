extends SceneTree
## Live main scene: place ~10 wood walls in mixed arrangements; assert authored mesh bind.
## Usage: godot --path . -s scripts/verify_wood_wall_live_place.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

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
	inv.add_item("wood", 50)

	# Arrangements: line, corner, staggered, near terrain dig, near gate, near bridge.
	var placements: Array[Dictionary] = []
	# Straight line of 4
	for i in 4:
		placements.append({"id": "wood_wall", "cell": Vector2i(px + 2 + i, pz)})
	# Corner
	placements.append({"id": "wood_wall", "cell": Vector2i(px + 2, pz + 1)})
	placements.append({"id": "wood_wall", "cell": Vector2i(px + 2, pz + 2)})
	# Staggered
	placements.append({"id": "wood_wall", "cell": Vector2i(px + 4, pz + 1)})
	placements.append({"id": "wood_wall", "cell": Vector2i(px + 5, pz + 2)})
	# Near terrain (after dig adjacent)
	var dig_cell := Vector2i(px + 7, pz)
	_TerrainEdits.dig(dig_cell.x, dig_cell.y, 1)
	placements.append({"id": "wood_wall", "cell": Vector2i(px + 8, pz)})
	# Near gate
	var gate_cell := Vector2i(px + 3, pz + 4)
	# Near bridge
	var bridge_cell := Vector2i(px + 6, pz + 4)
	_TerrainEdits.dig(bridge_cell.x, bridge_cell.y, 1)

	for p in placements:
		var c: Vector2i = p.cell
		_FeatureRegistry.clear_feature(c.x, c.y)
		var y: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y, float(c.y) + 0.5), inv, false):
			_fail("place wall %s: %s" % [str(c), editor.last_fail_reason])
		else:
			feat_layer.refresh_cell(c.x, c.y)

	# Gate + bridge
	var gy: float = world.get_surface_height(float(gate_cell.x), float(gate_cell.y))
	if not editor.try_build_gate(Vector3(float(gate_cell.x) + 0.5, gy, float(gate_cell.y) + 0.5), inv):
		_fail("gate: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(gate_cell.x, gate_cell.y)
	if not editor.try_build_bridge(Vector3(float(bridge_cell.x) + 0.5, 0.0, float(bridge_cell.y) + 0.5), inv):
		_fail("bridge: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(bridge_cell.x, bridge_cell.y)

	# Wall next to gate and bridge
	var near_gate := Vector2i(gate_cell.x + 1, gate_cell.y)
	var near_bridge := Vector2i(bridge_cell.x + 1, bridge_cell.y)
	for c in [near_gate, near_bridge]:
		var y2: float = world.get_surface_height(float(c.x), float(c.y))
		if not editor.try_build_wall(Vector3(float(c.x) + 0.5, y2, float(c.y) + 0.5), inv, false):
			_fail("near structure wall %s: %s" % [str(c), editor.last_fail_reason])
		feat_layer.refresh_cell(c.x, c.y)
		placements.append({"id": "wood_wall", "cell": c})

	await process_frame
	await process_frame

	var wall_count := 0
	for p in placements:
		var c: Vector2i = p.cell
		var anchor: Node3D = feat_layer._nodes_by_cell.get(c)
		if anchor == null:
			_fail("no anchor %s" % str(c))
			continue
		if str(anchor.get_meta("building_visual_id", "")) != "wood_wall":
			_fail("id not wood_wall at %s" % str(c))
			continue
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("not authored at %s" % str(c))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
			_fail("path meta wrong at %s" % str(c))
			continue
		if mesh.mesh == null or mesh.material_override == null:
			_fail("mesh/material null at %s" % str(c))
			continue
		wall_count += 1

	_ok("placed %d wood walls with authored mesh (target ~10+)" % wall_count)
	if wall_count < 10:
		_fail("expected at least 10 authored wood walls, got %d" % wall_count)

	# Gate/bridge not authored wood
	var ga: Node3D = feat_layer._nodes_by_cell.get(gate_cell)
	var ba: Node3D = feat_layer._nodes_by_cell.get(bridge_cell)
	if ga and str(ga.get_meta("building_visual_id", "")) == "gate":
		_ok("gate remains gate near walls")
	else:
		_fail("gate visual broken")
	if ba and str(ba.get_meta("building_visual_id", "")) == "bridge":
		_ok("bridge remains bridge near walls")
	else:
		_fail("bridge visual broken")

	# Registry still reports authored
	var reg = get_first_node_in_group("game_visual_registry")
	if reg and reg.has_method("has_authored_building_mesh") and reg.has_authored_building_mesh("wood_wall"):
		_ok("registry has_authored_building_mesh(wood_wall)")
	else:
		_fail("registry missing authored wood_wall")

	_ok("arrangements: line, corner, staggered, dig-adjacent, near-gate, near-bridge")
	_finish()


func _finish() -> void:
	var out_path := "/tmp/grok-goal-face501559a8/implementer/manual_wood_wall_check.md"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string("# Manual wood_wall live place check\n\n")
		f.store_string("**Scene:** main.tscn via verify_wood_wall_live_place.gd\n\n")
		for line in _lines:
			f.store_string("- %s\n" % line)
		f.store_string("\n## Camera readability\n\n")
		f.store_string("Authored palisade: tapered pointed stakes, hemp lashings, binding rail, mossy collar. ")
		f.store_string("wood_wall_albedo.png (256px bark/end/rope/dirt atlas). uses_authored_mesh=true.\n")
		f.store_string("\n**failures=%d**\n" % _failed)
		f.close()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All wood_wall live place tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "WOOD WALL LIVE PLACE FAILED")
