extends SceneTree
## Prove stone_wall uses the on-disk authored mesh end-to-end (not multi-box procedural).
## Also proves wood_wall authored bind is not regressed.
## Usage: godot --headless -s scripts/verify_stone_wall_authored.gd


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")


const STONE_MESH_PATH := "res://assets/structures/stone_wall/stone_wall.obj"
const STONE_ALBEDO_PATH := "res://assets/structures/stone_wall/stone_wall_albedo.png"
const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"

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
		print("All stone_wall authored pipeline tests OK")
		quit(0)
	else:
		push_error("verify_stone_wall_authored: %d failure(s)" % _failed)
		quit(1)


func _test_asset_files_exist() -> void:
	if not ResourceLoader.exists(STONE_MESH_PATH):
		_fail("authored mesh missing: %s" % STONE_MESH_PATH)
		return
	if not ResourceLoader.exists(STONE_ALBEDO_PATH):
		_fail("authored albedo missing: %s" % STONE_ALBEDO_PATH)
		return
	var mesh_res: Resource = load(STONE_MESH_PATH)
	if mesh_res == null:
		_fail("load(%s) returned null" % STONE_MESH_PATH)
		return
	if not (mesh_res is Mesh):
		_fail("stone_wall.obj must import as Mesh, got %s" % mesh_res.get_class())
		return
	var tex: Texture2D = load(STONE_ALBEDO_PATH) as Texture2D
	if tex == null:
		_fail("stone_wall_albedo.png failed to load as Texture2D")
		return
	if tex.get_width() != 256 or tex.get_height() != 256:
		_fail("stone albedo expected 256x256, got %dx%d" % [tex.get_width(), tex.get_height()])
	var aabb: AABB = (mesh_res as Mesh).get_aabb()
	# Must not be a unit cube. Crenellated battlement is taller than wide and not cubic.
	if aabb.size.y < 1.4:
		_fail("stone mesh too short to be a battlement (h=%.3f)" % aabb.size.y)
	if is_equal_approx(aabb.size.x, aabb.size.y) and is_equal_approx(aabb.size.y, aabb.size.z):
		_fail("stone mesh looks like a cube %s" % str(aabb.size))
	print("OK authored files load mesh=%s albedo=%dx%d aabb=%s" % [
		mesh_res.get_class(), tex.get_width(), tex.get_height(), str(aabb.size)
	])


func _test_registry_loads_authored() -> void:
	var reg := _GameVisualRegistry.new()
	if not reg.has_authored_building_mesh("stone_wall"):
		_fail("registry must declare stone_wall as authored")
	var path := reg.authored_building_mesh_path("stone_wall")
	if path != STONE_MESH_PATH:
		_fail("authored path mismatch: %s" % path)
	var mesh: Mesh = reg.get_authored_building_mesh("stone_wall")
	if mesh == null:
		_fail("get_authored_building_mesh(stone_wall) null")
		reg.free()
		return
	if not reg.has_authored_building_mesh("wood_wall"):
		_fail("wood_wall authored bind regressed")
	var albedo: Texture2D = reg.get_authored_building_albedo("stone_wall")
	if albedo == null:
		_fail("authored albedo null")
	var wood_mesh: Mesh = reg.get_authored_building_mesh("wood_wall")
	if wood_mesh == null:
		_fail("wood_wall mesh failed to load")
	elif mesh == wood_mesh:
		_fail("stone_wall and wood_wall share the same mesh resource")
	print("OK registry loads authored stone_wall mesh+albedo path=%s" % path)
	reg.free()


func _test_configure_binds_authored() -> void:
	var reg := _GameVisualRegistry.new()
	root.add_child(reg)
	var mi := MeshInstance3D.new()
	mi.set_meta("building_visual_id", "stone_wall")
	reg.configure_building_mesh(mi, null, Vector3(1, 1.5, 1), Color.WHITE, "stone_wall")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("configure_building_mesh must set uses_authored_mesh for stone_wall")
	var apath := str(mi.get_meta("authored_resource_path", ""))
	if apath != STONE_MESH_PATH:
		_fail("mesh meta authored_resource_path=%s" % apath)
	if mi.mesh == null:
		_fail("stone_wall mesh not assigned")
	if mi.mesh is ArrayMesh and str(mi.get_meta("authored_resource_path", "")).is_empty():
		_fail("procedural ArrayMesh used without authored path")
	var authored_ref: Mesh = reg.get_authored_building_mesh("stone_wall")
	if mi.mesh != authored_ref:
		if str(mi.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
			_fail("bound mesh is not the authored resource")
	if mi.material_override == null:
		_fail("stone_wall material missing")
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		_fail("stone_wall material missing albedo texture")
	elif mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		_fail("stone_wall must use nearest texture filter")
	if mi.scale.y > 0.75:
		_fail("stone_wall authored Y scale must be short cap (<=0.75), got %.3f" % mi.scale.y)
	# Wood still binds its own mesh after stone configure.
	var wi := MeshInstance3D.new()
	reg.configure_building_mesh(wi, null, Vector3(1, 1.5, 1), Color.WHITE, "wood_wall")
	if not bool(wi.get_meta("uses_authored_mesh", false)):
		_fail("wood_wall configure regressed")
	if str(wi.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
		_fail("wood_wall rebound to wrong path")
	if wi.mesh == mi.mesh:
		_fail("wood and stone configure share a mesh instance resource unexpectedly")
	print("OK configure_building_mesh binds authored stone_wall (wood still %s)" % WOOD_MESH_PATH)
	mi.free()
	wi.free()
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
	if stone_id == wood_id:
		_fail("stone_wall collapsed to wood_wall")
	var gparts: Array = reg.structure_mesh_parts("gate")
	var bparts: Array = reg.structure_mesh_parts("bridge")
	if gparts.size() < 3 or bparts.size() < 2:
		_fail("gate/bridge silhouette parts regressed")
	print("OK gate/bridge/wood identities not regressed (stone=%s)" % stone_id)
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
	inv.add_item("stone", 40)
	inv.add_item("wood", 20)

	var cells: Array[Vector2i] = [
		Vector2i(14, 4), Vector2i(15, 4), Vector2i(16, 4), Vector2i(17, 4),
		Vector2i(14, 5),
	]
	for cell in cells:
		var y: float = world.get_surface_height(float(cell.x), float(cell.y))
		if not editor.try_build_wall(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5), inv, true):
			_fail("place stone wall at %s: %s" % [str(cell), editor.last_fail_reason])
		feat_layer.refresh_cell(cell.x, cell.y)
	await process_frame

	for cell in cells:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(cell)
		if anchor == null:
			_fail("missing anchor at %s" % str(cell))
			continue
		var vid := str(anchor.get_meta("building_visual_id", ""))
		if vid != "stone_wall":
			_fail("visual id at %s is %s" % [str(cell), vid])
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("wall at %s not using authored mesh" % str(cell))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
			_fail("wall at %s wrong resource path %s" % [str(cell), mesh.get_meta("authored_resource_path", "")])
	print("OK multi-wall place uses authored stone mesh (%d cells incl. chunk boundary)" % cells.size())

	var mid: Vector2i = cells[1]
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	var mid_anchor: Node3D = feat_layer._nodes_by_cell.get(mid)
	if mid_anchor == null:
		_fail("refresh_cell dropped stone_wall")
	else:
		var mm: MeshInstance3D = mid_anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mm == null or not bool(mm.get_meta("uses_authored_mesh", false)):
			_fail("after refresh_cell stone_wall not authored")
		else:
			print("OK refresh_cell keeps authored stone_wall")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var c0: Vector2i = cells[0]
	var a0: Node3D = feat_layer._nodes_by_cell.get(c0)
	if a0 == null:
		_fail("chunk repopulate lost wall at %s" % str(c0))
	else:
		var m0: MeshInstance3D = a0.get_node_or_null("Mesh") as MeshInstance3D
		if m0 == null or not bool(m0.get_meta("uses_authored_mesh", false)):
			_fail("chunk repopulate lost authored bind")
		elif str(m0.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
			_fail("chunk repopulate rebound wrong mesh")
		else:
			print("OK chunk repopulate keeps authored stone_wall")

	_FeatureRegistry.clear_feature(mid.x, mid.y)
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	if feat_layer._nodes_by_cell.get(mid) != null:
		_fail("stale stone_wall node after feature clear")
	else:
		print("OK remove leaves no stale visual node")

	# Adjacent wood_wall still uses the wood authored mesh (not stone).
	var wx := 12
	var wz := 4
	var wy: float = world.get_surface_height(float(wx), float(wz))
	if editor.try_build_wall(Vector3(float(wx) + 0.5, wy, float(wz) + 0.5), inv, false):
		feat_layer.refresh_cell(wx, wz)
		await process_frame
		var wa: Node3D = feat_layer._nodes_by_cell.get(Vector2i(wx, wz))
		if wa == null:
			_fail("wood_wall anchor missing")
		elif str(wa.get_meta("building_visual_id", "")) != "wood_wall":
			_fail("wood_wall resolved to %s" % wa.get_meta("building_visual_id", ""))
		else:
			var wm: MeshInstance3D = wa.get_node_or_null("Mesh") as MeshInstance3D
			if wm == null or not bool(wm.get_meta("uses_authored_mesh", false)):
				_fail("adjacent wood_wall lost authored bind")
			elif str(wm.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
				_fail("wood_wall rebound to %s" % wm.get_meta("authored_resource_path", ""))
			else:
				print("OK adjacent wood_wall still authored wood mesh")
	else:
		_fail("wood wall place failed: %s" % editor.last_fail_reason)

	var gx := 11
	var gz := 4
	var gy: float = world.get_surface_height(float(gx), float(gz))
	if editor.try_build_gate(Vector3(float(gx) + 0.5, gy, float(gz) + 0.5), inv):
		feat_layer.refresh_cell(gx, gz)
		await process_frame
		var ga: Node3D = feat_layer._nodes_by_cell.get(Vector2i(gx, gz))
		if ga == null:
			_fail("gate anchor missing")
		elif str(ga.get_meta("building_visual_id", "")) == "stone_wall":
			_fail("gate resolved to stone_wall")
		elif str(ga.get_meta("building_visual_id", "")) == "wood_wall":
			_fail("gate resolved to wood_wall")
		elif str((ga.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) == STONE_MESH_PATH:
			_fail("gate bound stone_wall mesh")
		elif str((ga.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) == WOOD_MESH_PATH:
			_fail("gate bound wood_wall mesh")
		else:
			print("OK adjacent gate not a wall mesh")
	else:
		_fail("gate place failed: %s" % editor.last_fail_reason)

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
