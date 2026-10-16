extends SceneTree


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")

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
	await _check_blueprint_live(editor, world, player, feat_layer)
	_finish()


func _check_blueprint_live(editor, world, player, feat_layer) -> void:
	if not _Blueprints.LARGE_STRUCTURES:
		_fail("LARGE_STRUCTURES must stay on for live blueprint place")
		return
	if player == null or player.get("inventory") == null:
		_fail("player inventory missing for blueprint place")
		return
	var weapon = player.get_node_or_null("WeaponController")
	var hl = player.get_node_or_null("TargetHighlight")
	var probe = player.get("_floor_probe")
	if weapon == null or hl == null or probe == null:
		_fail("blueprint place needs the weapon, highlight, and floor probe")
		return
	var anchor := _flat_blueprint_anchor(world, player)
	if anchor.x < -100000:
		_fail("no flat 3-column run in reach for the wall segment")
		return
	var before := {}
	for x in 3:
		before[anchor.x + x] = _layers_at(anchor.x + x, anchor.y)
	var beside := _layers_at(anchor.x + 3, anchor.y)
	var bp := _Blueprints.get_blueprint(_Blueprints.WALL_SEGMENT)
	var tile := int(bp["cells"][0]["tile"])
	var homes := {}
	for x in 3:
		homes[_TerrainEdits.chunk_for_column(anchor.x + x, anchor.y)] = true
	var inv = player.inventory
	weapon.inventory = inv
	inv.add_item("stone", 40)
	inv.set_slot(0, "stone", 24)
	var stone_before: int = inv.count_item("stone")
	weapon.blueprint_index = 0
	weapon.blueprint_quarter = 0
	weapon._cooldown_timer = 0.0
	if weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	hl._action_column = Vector3(float(anchor.x) + 0.5, 0.0, float(anchor.y) + 0.5)
	weapon._try_place_selected()
	var guard := 0
	while guard < 90:
		var early: Dictionary = {}
		if "last_place_batch" in editor:
			early = editor.last_place_batch
		if int(early.get("placed_count", 0)) >= 6:
			break
		if player.has_method("_tick_skill_feel"):
			player._tick_skill_feel(1.0 / 60.0)
		guard += 1
	await process_frame
	var batch: Dictionary = editor.last_place_batch
	var placed := int(batch.get("placed_count", 0))
	var remesh := int(batch.get("remesh_count", 0))
	if placed != 6 or remesh != homes.size():
		_fail("blueprint place wrote %d cells over %d remeshes, want 6 over %d (%s)" % [placed, remesh, homes.size(), editor.last_fail_reason])
		return
	if int(batch.get("water_count", 0)) != remesh or int(batch.get("crystal_count", 0)) != remesh:
		_fail("blueprint place must update water and crystal once per chunk")
		return
	if inv.count_item("stone") >= stone_before:
		_fail("blueprint place did not spend stone")
	var raised := true
	for x in 3:
		var wx := anchor.x + x
		if _layers_at(wx, anchor.y) != int(before[wx]) + 2:
			raised = false
		if _TerrainEdits.get_build_tile(wx, anchor.y) != tile:
			raised = false
		var blocked: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(probe, wx, anchor.y, false, true)
		if not blocked.get("ok", false):
			_fail("blueprint column %s does not block: %s" % [str(Vector2i(wx, anchor.y)), blocked.get("reason", "?")])
			raised = false
		var node: Node3D = feat_layer._nodes_by_cell.get(Vector2i(wx, anchor.y))
		if node == null or str(node.get_meta("building_visual_id", "")) != "stone_wall":
			_fail("blueprint column %s has no stone wall visual" % str(Vector2i(wx, anchor.y)))
	if _layers_at(anchor.x + 3, anchor.y) != beside:
		raised = false
	if not raised:
		_fail("wall segment must raise only its three columns by two cells")
		return
	_ok("live blueprint place wrote 6 cells in %d chunk remesh(es) and blocks" % remesh)


func _flat_blueprint_anchor(world, player) -> Vector2i:
	var origin: Vector3 = player.get_voxel_position()
	var px := int(floor(origin.x))
	var pz := int(floor(origin.z))
	for dz in range(-5, 6):
		for dx in range(-5, 4):
			var ax := px + dx
			var az := pz + dz
			if _blueprint_run_clear(world, player, ax, az):
				return Vector2i(ax, az)
	return Vector2i(-1000000, 0)


func _blueprint_run_clear(world, player, ax: int, az: int) -> bool:
	var height: float = world.get_surface_height(float(ax), float(az))
	for x in 3:
		var wx := ax + x
		if not _ActionTargeting._column_in_range(player, wx, az, 8.0):
			return false
		if not _TerrainEdits.can_edit(wx, az):
			return false
		if absf(world.get_surface_height(float(wx), float(az)) - height) > 0.01:
			return false
		if _TerrainEdits.get_build_tile(wx, az) >= 0:
			return false
		if not _FeatureRegistry.get_feature(wx, az).is_empty():
			return false
	return true


func _layers_at(x: int, z: int) -> int:
	var layer: float = _WorldSettings.get_active().layer_height()
	return int(round(_TerrainEdits.get_height_delta(x, z) / maxf(layer, 0.001)))


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All stone_wall live place tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "STONE WALL LIVE PLACE FAILED")
