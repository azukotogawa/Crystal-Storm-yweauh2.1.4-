extends SceneTree
## Prove gate uses the on-disk authored mesh end-to-end (not multi-box procedural).
## Also proves wood_wall / stone_wall authored binds are not regressed.
## Usage: godot --headless -s scripts/verify_gate_authored.gd


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")


const GATE_MESH_PATH := "res://assets/structures/gate/gate.obj"
const GATE_ALBEDO_PATH := "res://assets/structures/gate/gate_albedo.png"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"

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
		print("All gate authored pipeline tests OK")
		quit(0)
	else:
		push_error("verify_gate_authored: %d failure(s)" % _failed)
		quit(1)


func _test_asset_files_exist() -> void:
	if not ResourceLoader.exists(GATE_MESH_PATH):
		_fail("authored mesh missing: %s" % GATE_MESH_PATH)
		return
	if not ResourceLoader.exists(GATE_ALBEDO_PATH):
		_fail("authored albedo missing: %s" % GATE_ALBEDO_PATH)
		return
	var mesh_res: Resource = load(GATE_MESH_PATH)
	if mesh_res == null:
		_fail("load(%s) returned null" % GATE_MESH_PATH)
		return
	if not (mesh_res is Mesh):
		_fail("gate.obj must import as Mesh, got %s" % mesh_res.get_class())
		return
	var tex: Texture2D = load(GATE_ALBEDO_PATH) as Texture2D
	if tex == null:
		_fail("gate_albedo.png failed to load as Texture2D")
		return
	if tex.get_width() != 256 or tex.get_height() != 256:
		_fail("gate albedo expected 256x256, got %dx%d" % [tex.get_width(), tex.get_height()])
	var aabb: AABB = (mesh_res as Mesh).get_aabb()
	# Open arch: tall, not a cube, thin in Z so the middle is a passage.
	if aabb.size.y < 1.8:
		_fail("gate mesh too short to be a passage arch (h=%.3f)" % aabb.size.y)
	if aabb.size.z > aabb.size.x * 0.55:
		_fail("gate mesh too deep to read as an open passage (size=%s)" % str(aabb.size))
	if is_equal_approx(aabb.size.x, aabb.size.y) and is_equal_approx(aabb.size.y, aabb.size.z):
		_fail("gate mesh looks like a cube %s" % str(aabb.size))
	# Central passage must be empty: no verts in the walk volume.
	# Posts + lintel must exist so it is a doorway, not an empty cell.
	var blocked := 0
	var left_post := 0
	var right_post := 0
	var lintel := 0
	var st: int = (mesh_res as Mesh).get_surface_count()
	for si in st:
		var arr: Array = (mesh_res as Mesh).surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for p in verts:
			if absf(p.x) < 0.20 and absf(p.z) < 0.16 and p.y > 0.15 and p.y < 1.55:
				blocked += 1
			if p.x < -0.25 and p.y < 1.70:
				left_post += 1
			if p.x > 0.25 and p.y < 1.70:
				right_post += 1
			if p.y > 1.70:
				lintel += 1
	if blocked > 0:
		_fail("central passage is not open (%d verts in walk volume)" % blocked)
	if left_post < 8 or right_post < 8:
		_fail("gate missing side posts (L=%d R=%d)" % [left_post, right_post])
	if lintel < 8:
		_fail("gate missing overhead beam (%d verts)" % lintel)
	print("OK authored files load mesh=%s albedo=%dx%d aabb=%s open_center" % [
		mesh_res.get_class(), tex.get_width(), tex.get_height(), str(aabb.size)
	])


func _test_registry_loads_authored() -> void:
	var reg := _GameVisualRegistry.new()
	if not reg.has_authored_building_mesh("gate"):
		_fail("registry must declare gate as authored")
	var path := reg.authored_building_mesh_path("gate")
	if path != GATE_MESH_PATH:
		_fail("authored path mismatch: %s" % path)
	var mesh: Mesh = reg.get_authored_building_mesh("gate")
	if mesh == null:
		_fail("get_authored_building_mesh(gate) null")
		reg.free()
		return
	if not reg.has_authored_building_mesh("wood_wall"):
		_fail("wood_wall authored bind regressed")
	if not reg.has_authored_building_mesh("stone_wall"):
		_fail("stone_wall authored bind regressed")
	var albedo: Texture2D = reg.get_authored_building_albedo("gate")
	if albedo == null:
		_fail("authored albedo null")
	var wood_mesh: Mesh = reg.get_authored_building_mesh("wood_wall")
	var stone_mesh: Mesh = reg.get_authored_building_mesh("stone_wall")
	if wood_mesh == null or stone_mesh == null:
		_fail("wood/stone mesh failed to load")
	elif mesh == wood_mesh or mesh == stone_mesh:
		_fail("gate shares a wall mesh resource")
	elif wood_mesh != null and stone_mesh != null:
		var g_aabb: AABB = mesh.get_aabb()
		var w_aabb: AABB = wood_mesh.get_aabb()
		var s_aabb: AABB = stone_mesh.get_aabb()
		if g_aabb.size.is_equal_approx(w_aabb.size) or g_aabb.size.is_equal_approx(s_aabb.size):
			_fail("gate AABB matches a wall (wood=%s stone=%s gate=%s)" % [
				str(w_aabb.size), str(s_aabb.size), str(g_aabb.size)
			])
		# Tall thin arch vs shorter/thicker wall slabs.
		if g_aabb.size.y < w_aabb.size.y * 1.15:
			_fail("gate not taller than wood_wall (gate.y=%.3f wood.y=%.3f)" % [
				g_aabb.size.y, w_aabb.size.y
			])
		if g_aabb.size.z > w_aabb.size.z * 0.70:
			_fail("gate not thinner than wood_wall (gate.z=%.3f wood.z=%.3f)" % [
				g_aabb.size.z, w_aabb.size.z
			])
		print("OK gate AABB distinct from walls gate=%s wood=%s stone=%s" % [
			str(g_aabb.size), str(w_aabb.size), str(s_aabb.size)
		])
	print("OK registry loads authored gate mesh+albedo path=%s" % path)
	reg.free()


func _test_configure_binds_authored() -> void:
	var reg := _GameVisualRegistry.new()
	root.add_child(reg)
	var mi := MeshInstance3D.new()
	mi.set_meta("building_visual_id", "gate")
	reg.configure_building_mesh(mi, null, Vector3(1.15, 2.05, 0.55), Color.WHITE, "gate")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("configure_building_mesh must set uses_authored_mesh for gate")
	var apath := str(mi.get_meta("authored_resource_path", ""))
	if apath != GATE_MESH_PATH:
		_fail("mesh meta authored_resource_path=%s" % apath)
	if mi.mesh == null:
		_fail("gate mesh not assigned")
	if mi.mesh is ArrayMesh and str(mi.get_meta("authored_resource_path", "")).is_empty():
		_fail("procedural ArrayMesh used without authored path")
	if mi.material_override == null:
		_fail("gate material missing")
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		_fail("gate material missing albedo texture")
	elif mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		_fail("gate must use nearest texture filter")
	# Full-height arch, not a short wall cap.
	if mi.scale.y < 0.9 or mi.scale.y > 1.15:
		_fail("gate Y scale must be full height (~1.0), got %.3f" % mi.scale.y)
	var wi := MeshInstance3D.new()
	reg.configure_building_mesh(wi, null, Vector3(1, 1.5, 1), Color.WHITE, "wood_wall")
	if str(wi.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
		_fail("wood_wall rebound to wrong path")
	var si := MeshInstance3D.new()
	reg.configure_building_mesh(si, null, Vector3(1, 1.5, 1), Color.WHITE, "stone_wall")
	if str(si.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
		_fail("stone_wall rebound to wrong path")
	print("OK configure_building_mesh binds authored gate (walls still distinct)")
	mi.free()
	wi.free()
	si.free()
	reg.queue_free()


func _test_other_ids_not_regressed() -> void:
	var layer = _FeatureVisualLayer.new()
	var reg := _GameVisualRegistry.new()
	var gate_id: String = layer._resolve_player_build_visual_id({
		"build_id": "gate", "is_passage": true
	}, 0, 0)
	var bridge_id: String = layer._resolve_player_build_visual_id({
		"build_id": "bridge", "is_bridge": true
	}, 0, 0)
	var wood_id: String = layer._resolve_player_build_visual_id({
		"build_id": "wood_wall"
	}, 0, 0)
	var stone_id: String = layer._resolve_player_build_visual_id({
		"build_id": "stone_wall"
	}, 0, 0)
	if gate_id != "gate" or bridge_id != "bridge" or wood_id != "wood_wall" or stone_id != "stone_wall":
		_fail("identity regression gate=%s bridge=%s wood=%s stone=%s" % [gate_id, bridge_id, wood_id, stone_id])
	if gate_id == wood_id or gate_id == stone_id:
		_fail("gate collapsed to a wall")
	var gparts: Array = reg.structure_mesh_parts("gate")
	if gparts.size() < 3:
		_fail("gate silhouette parts regressed")
	print("OK identities not regressed (gate=%s)" % gate_id)
	layer.free()
	reg.free()


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
	inv.add_item("stone", 20)

	var cells: Array[Vector2i] = [
		Vector2i(14, 4), Vector2i(15, 4), Vector2i(16, 4), Vector2i(17, 4),
		Vector2i(14, 5),
	]
	for cell in cells:
		var y: float = world.get_surface_height(float(cell.x), float(cell.y))
		if not editor.try_build_gate(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5), inv):
			_fail("place gate at %s: %s" % [str(cell), editor.last_fail_reason])
		feat_layer.refresh_cell(cell.x, cell.y)
	await process_frame

	for cell in cells:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(cell)
		if anchor == null:
			_fail("missing anchor at %s" % str(cell))
			continue
		var vid := str(anchor.get_meta("building_visual_id", ""))
		if vid != "gate":
			_fail("visual id at %s is %s" % [str(cell), vid])
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("gate at %s not using authored mesh" % str(cell))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
			_fail("gate at %s wrong resource path %s" % [str(cell), mesh.get_meta("authored_resource_path", "")])
	print("OK multi-gate place uses authored mesh (%d cells incl. chunk boundary)" % cells.size())

	var mid: Vector2i = cells[1]
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	var mid_anchor: Node3D = feat_layer._nodes_by_cell.get(mid)
	if mid_anchor == null:
		_fail("refresh_cell dropped gate")
	else:
		var mm: MeshInstance3D = mid_anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mm == null or not bool(mm.get_meta("uses_authored_mesh", false)):
			_fail("after refresh_cell gate not authored")
		else:
			print("OK refresh_cell keeps authored gate")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var c0: Vector2i = cells[0]
	var a0: Node3D = feat_layer._nodes_by_cell.get(c0)
	if a0 == null:
		_fail("chunk repopulate lost gate at %s" % str(c0))
	else:
		var m0: MeshInstance3D = a0.get_node_or_null("Mesh") as MeshInstance3D
		if m0 == null or not bool(m0.get_meta("uses_authored_mesh", false)):
			_fail("chunk repopulate lost authored bind")
		elif str(m0.get_meta("authored_resource_path", "")) != GATE_MESH_PATH:
			_fail("chunk repopulate rebound wrong mesh")
		else:
			print("OK chunk repopulate keeps authored gate")

	_FeatureRegistry.clear_feature(mid.x, mid.y)
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	if feat_layer._nodes_by_cell.get(mid) != null:
		_fail("stale gate node after feature clear")
	else:
		print("OK remove leaves no stale visual node")

	# Adjacent wood still wood.
	var wx := 12
	var wz := 4
	var wy: float = world.get_surface_height(float(wx), float(wz))
	if editor.try_build_wall(Vector3(float(wx) + 0.5, wy, float(wz) + 0.5), inv, false):
		feat_layer.refresh_cell(wx, wz)
		await process_frame
		var wa: Node3D = feat_layer._nodes_by_cell.get(Vector2i(wx, wz))
		if wa == null or str(wa.get_meta("building_visual_id", "")) != "wood_wall":
			_fail("adjacent wood_wall broken")
		elif str((wa.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
			_fail("wood_wall rebound away from wood mesh")
		else:
			print("OK adjacent wood_wall still authored wood mesh")
	else:
		_fail("wood wall place failed: %s" % editor.last_fail_reason)

	# Adjacent stone still stone.
	var sx := 12
	var sz := 5
	var sy: float = world.get_surface_height(float(sx), float(sz))
	if editor.try_build_wall(Vector3(float(sx) + 0.5, sy, float(sz) + 0.5), inv, true):
		feat_layer.refresh_cell(sx, sz)
		await process_frame
		var sa: Node3D = feat_layer._nodes_by_cell.get(Vector2i(sx, sz))
		if sa == null or str(sa.get_meta("building_visual_id", "")) != "stone_wall":
			_fail("adjacent stone_wall broken")
		elif str((sa.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
			_fail("stone_wall rebound away from stone mesh")
		else:
			print("OK adjacent stone_wall still authored stone mesh")
	else:
		_fail("stone wall place failed: %s" % editor.last_fail_reason)

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
