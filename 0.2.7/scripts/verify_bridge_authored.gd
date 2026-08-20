extends SceneTree
## Prove bridge uses the on-disk authored mesh end-to-end (not multi-box procedural).
## Also proves wood/stone/gate authored binds are not regressed.
## Usage: godot --headless -s scripts/verify_bridge_authored.gd


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")


const BRIDGE_MESH_PATH := "res://assets/structures/bridge/bridge.obj"
const BRIDGE_ALBEDO_PATH := "res://assets/structures/bridge/bridge_albedo.png"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const GATE_MESH_PATH := "res://assets/structures/gate/gate.obj"

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.reset()
	_BuildingRegistry.ensure_builtins()

	_test_asset_files_exist()
	_test_registry_loads_authored()
	_test_configure_binds_authored()
	_test_other_ids_not_regressed()
	await _test_place_multi_refresh_stream()

	if _failed == 0:
		print("All bridge authored pipeline tests OK")
		quit(0)
	else:
		push_error("verify_bridge_authored: %d failure(s)" % _failed)
		quit(1)


func _test_asset_files_exist() -> void:
	if not ResourceLoader.exists(BRIDGE_MESH_PATH):
		_fail("authored mesh missing: %s" % BRIDGE_MESH_PATH)
		return
	if not ResourceLoader.exists(BRIDGE_ALBEDO_PATH):
		_fail("authored albedo missing: %s" % BRIDGE_ALBEDO_PATH)
		return
	var mesh_res: Resource = load(BRIDGE_MESH_PATH)
	if mesh_res == null or not (mesh_res is Mesh):
		_fail("bridge.obj must import as Mesh")
		return
	var tex: Texture2D = load(BRIDGE_ALBEDO_PATH) as Texture2D
	if tex == null:
		_fail("bridge_albedo.png failed to load as Texture2D")
		return
	if tex.get_width() != 256 or tex.get_height() != 256:
		_fail("bridge albedo expected 256x256, got %dx%d" % [tex.get_width(), tex.get_height()])
	var aabb: AABB = (mesh_res as Mesh).get_aabb()
	# Low square deck, not a wall/gate/cube.
	if aabb.size.y > 0.7:
		_fail("bridge mesh too tall to be a deck (h=%.3f)" % aabb.size.y)
	if aabb.size.x < 0.9 or aabb.size.z < 0.9:
		_fail("bridge deck footprint too small %s" % str(aabb.size))
	if aabb.size.y > aabb.size.x * 0.7:
		_fail("bridge not a low crossing (size=%s)" % str(aabb.size))
	if is_equal_approx(aabb.size.x, aabb.size.y) and is_equal_approx(aabb.size.y, aabb.size.z):
		_fail("bridge mesh looks like a cube %s" % str(aabb.size))
	# Deck + two side rails: not a flat floor tile.
	var deck_n := 0
	var left_rail := 0
	var right_rail := 0
	for si in (mesh_res as Mesh).get_surface_count():
		var verts: PackedVector3Array = (mesh_res as Mesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for p in verts:
			if p.y < 0.16 and absf(p.x) < 0.50 and absf(p.z) < 0.42:
				deck_n += 1
			if p.z < -0.38 and p.y > 0.20:
				left_rail += 1
			if p.z > 0.38 and p.y > 0.20:
				right_rail += 1
	if deck_n < 8:
		_fail("bridge missing deck volume (%d verts)" % deck_n)
	if left_rail < 8 or right_rail < 8:
		_fail("bridge missing side rails (L=%d R=%d)" % [left_rail, right_rail])
	print("OK authored files load mesh=%s albedo=%dx%d aabb=%s deck=%d rails=%d/%d" % [
		mesh_res.get_class(), tex.get_width(), tex.get_height(), str(aabb.size),
		deck_n, left_rail, right_rail
	])


func _test_registry_loads_authored() -> void:
	var reg := _GameVisualRegistry.new()
	if not reg.has_authored_building_mesh("bridge"):
		_fail("registry must declare bridge as authored")
	if reg.authored_building_mesh_path("bridge") != BRIDGE_MESH_PATH:
		_fail("authored path mismatch")
	var mesh: Mesh = reg.get_authored_building_mesh("bridge")
	if mesh == null:
		_fail("get_authored_building_mesh(bridge) null")
		reg.free()
		return
	if not reg.has_authored_building_mesh("wood_wall"):
		_fail("wood_wall authored bind regressed")
	if not reg.has_authored_building_mesh("stone_wall"):
		_fail("stone_wall authored bind regressed")
	if not reg.has_authored_building_mesh("gate"):
		_fail("gate authored bind regressed")
	if reg.get_authored_building_albedo("bridge") == null:
		_fail("authored albedo null")
	var wood_mesh: Mesh = reg.get_authored_building_mesh("wood_wall")
	var stone_mesh: Mesh = reg.get_authored_building_mesh("stone_wall")
	var gate_mesh: Mesh = reg.get_authored_building_mesh("gate")
	if mesh == wood_mesh or mesh == stone_mesh or mesh == gate_mesh:
		_fail("bridge shares a wall/gate mesh resource")
	elif wood_mesh != null and stone_mesh != null and gate_mesh != null:
		var b_aabb: AABB = mesh.get_aabb()
		var w_aabb: AABB = wood_mesh.get_aabb()
		var s_aabb: AABB = stone_mesh.get_aabb()
		var g_aabb: AABB = gate_mesh.get_aabb()
		if b_aabb.size.is_equal_approx(w_aabb.size) or b_aabb.size.is_equal_approx(s_aabb.size) \
				or b_aabb.size.is_equal_approx(g_aabb.size):
			_fail("bridge AABB matches a completed asset wood=%s stone=%s gate=%s bridge=%s" % [
				str(w_aabb.size), str(s_aabb.size), str(g_aabb.size), str(b_aabb.size)
			])
		if b_aabb.size.y > w_aabb.size.y * 0.60:
			_fail("bridge not lower than wood_wall (bridge.y=%.3f wood.y=%.3f)" % [
				b_aabb.size.y, w_aabb.size.y
			])
		print("OK bridge AABB distinct from completed assets bridge=%s wood=%s stone=%s gate=%s" % [
			str(b_aabb.size), str(w_aabb.size), str(s_aabb.size), str(g_aabb.size)
		])
	print("OK registry loads authored bridge mesh+albedo")
	reg.free()


func _test_configure_binds_authored() -> void:
	var reg := _GameVisualRegistry.new()
	root.add_child(reg)
	var mi := MeshInstance3D.new()
	reg.configure_building_mesh(mi, null, Vector3(1.35, 0.55, 1.35), Color.WHITE, "bridge")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("configure_building_mesh must set uses_authored_mesh for bridge")
	if str(mi.get_meta("authored_resource_path", "")) != BRIDGE_MESH_PATH:
		_fail("mesh meta authored_resource_path=%s" % mi.get_meta("authored_resource_path", ""))
	if mi.mesh == null:
		_fail("bridge mesh not assigned")
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		_fail("bridge material missing albedo")
	elif mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		_fail("bridge must use nearest texture filter")
	if mi.scale.y < 1.0 or mi.scale.y > 1.4:
		_fail("bridge Y scale should be a low deck (~1.15), got %.3f" % mi.scale.y)
	var gi := MeshInstance3D.new()
	reg.configure_building_mesh(gi, null, Vector3(1, 2, 1), Color.WHITE, "gate")
	if str(gi.get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
		_fail("gate rebound to wrong path")
	print("OK configure_building_mesh binds authored bridge (gate still distinct)")
	mi.free()
	gi.free()
	reg.queue_free()


func _test_other_ids_not_regressed() -> void:
	var layer = _FeatureVisualLayer.new()
	var bridge_id: String = layer._resolve_player_build_visual_id({
		"build_id": "bridge", "is_bridge": true
	}, 0, 0)
	var gate_id: String = layer._resolve_player_build_visual_id({
		"build_id": "gate", "is_passage": true
	}, 0, 0)
	if bridge_id != "bridge" or gate_id != "gate":
		_fail("identity regression bridge=%s gate=%s" % [bridge_id, gate_id])
	if bridge_id == gate_id:
		_fail("bridge collapsed to gate")
	print("OK identities not regressed (bridge=%s)" % bridge_id)
	layer.free()


func _test_place_multi_refresh_stream() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()

	var root3d := Node3D.new()
	root.add_child(root3d)
	var world_visuals = _WorldVisuals.new()
	root3d.add_child(world_visuals)
	var registry = _GameVisualRegistry.new()
	root3d.add_child(registry)
	registry._initialized = true
	registry._bundle_ready = true
	registry.feature_billboards_enabled = true
	var feat_layer = _FeatureVisualLayer.new()
	world_visuals.add_child(feat_layer)
	feat_layer._registry = registry
	feat_layer._bind_layer_roots()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 77
	world.add_to_group("world")
	root3d.add_child(world)
	var cm := _ChunkManager.new()
	cm.add_to_group("chunk_manager")
	cm.set_process(false)
	cm.set_physics_process(false)
	root3d.add_child(cm)
	for coord in [Vector2i(0, 0), Vector2i(1, 0)]:
		var view := ChunkView.new()
		view.chunk_data = ChunkData.new(coord, world)
		cm.chunks[coord] = view
	var editor := _TerrainEditor.new()
	editor.add_to_group("terrain_editor")
	root3d.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)
	feat_layer._bind_terrain_placement_refresh()
	await process_frame

	var inv := _Inventory.new()
	inv.add_item("wood", 40)
	inv.add_item("stone", 10)

	var cells: Array[Vector2i] = [
		Vector2i(14, 4), Vector2i(15, 4), Vector2i(16, 4), Vector2i(17, 4),
		Vector2i(14, 5),
	]
	for cell in cells:
		_TerrainEdits.dig(cell.x, cell.y, 1)
		if not editor.try_build_bridge(Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5), inv):
			_fail("place bridge at %s: %s" % [str(cell), editor.last_fail_reason])
		feat_layer.refresh_cell(cell.x, cell.y)
	await process_frame

	for cell in cells:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(cell)
		if anchor == null:
			_fail("missing anchor at %s" % str(cell))
			continue
		if str(anchor.get_meta("building_visual_id", "")) != "bridge":
			_fail("visual id at %s is %s" % [str(cell), anchor.get_meta("building_visual_id", "")])
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or str(mesh.get_meta("authored_resource_path", "")) != BRIDGE_MESH_PATH:
			_fail("bridge at %s not authored" % str(cell))
	print("OK multi-bridge place uses authored mesh (%d cells incl. chunk boundary)" % cells.size())

	var mid: Vector2i = cells[1]
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	var mid_anchor: Node3D = feat_layer._nodes_by_cell.get(mid)
	if mid_anchor == null or not bool((mid_anchor.get_node_or_null("Mesh") as MeshInstance3D).get_meta("uses_authored_mesh", false)):
		_fail("refresh_cell dropped authored bridge")
	else:
		print("OK refresh_cell keeps authored bridge")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var a0: Node3D = feat_layer._nodes_by_cell.get(cells[0])
	if a0 == null or str((a0.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != BRIDGE_MESH_PATH:
		_fail("chunk repopulate lost authored bridge")
	else:
		print("OK chunk repopulate keeps authored bridge")

	_FeatureRegistry.clear_feature(mid.x, mid.y)
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	if feat_layer._nodes_by_cell.get(mid) != null:
		_fail("stale bridge node after feature clear")
	else:
		print("OK remove leaves no stale visual node")

	# Adjacent gate still gate mesh.
	var gx := 12
	var gz := 4
	var gy: float = world.get_surface_height(float(gx), float(gz))
	if editor.try_build_gate(Vector3(float(gx) + 0.5, gy, float(gz) + 0.5), inv):
		feat_layer.refresh_cell(gx, gz)
		await process_frame
		var ga: Node3D = feat_layer._nodes_by_cell.get(Vector2i(gx, gz))
		if ga == null or str(ga.get_meta("building_visual_id", "")) != "gate":
			_fail("adjacent gate broken")
		elif str((ga.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
			_fail("gate rebound away from gate mesh")
		else:
			print("OK adjacent gate still authored gate mesh")
	else:
		_fail("gate place failed: %s" % editor.last_fail_reason)

	# Adjacent wood still wood.
	var wx := 12
	var wz := 5
	var wy: float = world.get_surface_height(float(wx), float(wz))
	if editor.try_build_wall(Vector3(float(wx) + 0.5, wy, float(wz) + 0.5), inv, false):
		feat_layer.refresh_cell(wx, wz)
		await process_frame
		var wa: Node3D = feat_layer._nodes_by_cell.get(Vector2i(wx, wz))
		if wa == null or str((wa.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
			_fail("adjacent wood_wall rebound")
		else:
			print("OK adjacent wood_wall still authored wood mesh")
	else:
		_fail("wood wall place failed: %s" % editor.last_fail_reason)

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
