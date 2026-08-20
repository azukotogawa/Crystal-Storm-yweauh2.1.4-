extends SceneTree
## Prove ruin_pillar uses the on-disk authored mesh, only at ruin centers.
## Usage: godot --headless -s scripts/verify_ruin_pillar_authored.gd


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")


const RUIN_MESH_PATH := "res://assets/structures/ruin_pillar/ruin_pillar.obj"
const RUIN_ALBEDO_PATH := "res://assets/structures/ruin_pillar/ruin_pillar_albedo.png"
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
	await _test_center_only_and_stream()
	if _failed == 0:
		print("All ruin_pillar authored pipeline tests OK")
		quit(0)
	else:
		push_error("verify_ruin_pillar_authored: %d failure(s)" % _failed)
		quit(1)


func _test_asset_files_exist() -> void:
	if not ResourceLoader.exists(RUIN_MESH_PATH) or not ResourceLoader.exists(RUIN_ALBEDO_PATH):
		_fail("authored ruin files missing")
		return
	var mesh_res: Resource = load(RUIN_MESH_PATH)
	if mesh_res == null or not (mesh_res is Mesh):
		_fail("ruin_pillar.obj must import as Mesh")
		return
	var tex: Texture2D = load(RUIN_ALBEDO_PATH) as Texture2D
	if tex == null or tex.get_width() != 256:
		_fail("ruin albedo expected 256px Texture2D")
		return
	var aabb: AABB = (mesh_res as Mesh).get_aabb()
	# Tall thin landmark, not a wall slab / deck / cube.
	if aabb.size.y < 2.0:
		_fail("ruin pillar too short to be a landmark (h=%.3f)" % aabb.size.y)
	if aabb.size.x > aabb.size.y * 0.55:
		_fail("ruin pillar too wide — looks like a wall (size=%s)" % str(aabb.size))
	if is_equal_approx(aabb.size.x, aabb.size.y) and is_equal_approx(aabb.size.y, aabb.size.z):
		_fail("ruin pillar looks like a cube")
	var shaft := 0
	var rubble := 0
	var broken_top := 0
	for si in (mesh_res as Mesh).get_surface_count():
		var verts: PackedVector3Array = (mesh_res as Mesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for p in verts:
			if p.y > 0.50 and p.y < 2.00 and absf(p.x) < 0.38 and absf(p.z) < 0.38:
				shaft += 1
			if p.y < 0.28 and (absf(p.x) > 0.22 or absf(p.z) > 0.22):
				rubble += 1
			if p.y > 2.15:
				broken_top += 1
	if shaft < 8:
		_fail("ruin missing column shaft (%d verts)" % shaft)
	if rubble < 8:
		_fail("ruin missing rubble collar (%d verts)" % rubble)
	if broken_top < 4:
		_fail("ruin missing broken top (%d verts)" % broken_top)
	print("OK authored files load mesh=%s albedo=%dx%d aabb=%s shaft=%d rubble=%d top=%d" % [
		mesh_res.get_class(), tex.get_width(), tex.get_height(), str(aabb.size),
		shaft, rubble, broken_top
	])


func _test_registry_loads_authored() -> void:
	var reg := _GameVisualRegistry.new()
	if not reg.has_authored_building_mesh("ruin_pillar"):
		_fail("registry must declare ruin_pillar as authored")
	if reg.authored_building_mesh_path("ruin_pillar") != RUIN_MESH_PATH:
		_fail("authored path mismatch")
	var mesh: Mesh = reg.get_authored_building_mesh("ruin_pillar")
	if mesh == null:
		_fail("get_authored_building_mesh(ruin_pillar) null")
		reg.free()
		return
	if not reg.has_authored_building_mesh("stone_wall") or not reg.has_authored_building_mesh("gate") \
			or not reg.has_authored_building_mesh("wood_wall") or not reg.has_authored_building_mesh("bridge"):
		_fail("completed authored binds regressed")
	if reg.get_authored_building_albedo("ruin_pillar") == null:
		_fail("authored albedo null")
	var stone_mesh: Mesh = reg.get_authored_building_mesh("stone_wall")
	var gate_mesh: Mesh = reg.get_authored_building_mesh("gate")
	var wood_mesh: Mesh = reg.get_authored_building_mesh("wood_wall")
	var bridge_mesh: Mesh = reg.get_authored_building_mesh("bridge")
	if mesh == stone_mesh or mesh == gate_mesh or mesh == wood_mesh or mesh == bridge_mesh:
		_fail("ruin shares a completed-asset mesh")
	elif stone_mesh != null and gate_mesh != null and wood_mesh != null and bridge_mesh != null:
		var r_aabb: AABB = mesh.get_aabb()
		for other in [stone_mesh, gate_mesh, wood_mesh, bridge_mesh]:
			if r_aabb.size.is_equal_approx(other.get_aabb().size):
				_fail("ruin AABB matches a completed asset %s" % str(other.get_aabb().size))
		print("OK ruin AABB distinct ruin=%s wood=%s stone=%s gate=%s bridge=%s" % [
			str(r_aabb.size), str(wood_mesh.get_aabb().size), str(stone_mesh.get_aabb().size),
			str(gate_mesh.get_aabb().size), str(bridge_mesh.get_aabb().size)
		])
	print("OK registry loads authored ruin_pillar")
	reg.free()


func _test_configure_binds_authored() -> void:
	var reg := _GameVisualRegistry.new()
	root.add_child(reg)
	var mi := MeshInstance3D.new()
	reg.configure_building_mesh(mi, null, Vector3(1.2, 2.4, 1.2), Color.WHITE, "ruin_pillar")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("configure must set uses_authored_mesh")
	if str(mi.get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
		_fail("wrong authored path")
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		_fail("ruin material missing albedo")
	elif mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		_fail("ruin must use nearest filter")
	if not is_equal_approx(mi.scale.y, 1.0):
		_fail("ruin Y scale should be full height 1.0, got %.3f" % mi.scale.y)
	var si := MeshInstance3D.new()
	reg.configure_building_mesh(si, null, Vector3.ONE, Color.WHITE, "stone_wall")
	if str(si.get_meta("authored_resource_path", "")) != STONE_MESH_PATH:
		_fail("stone_wall rebound")
	print("OK configure_building_mesh binds authored ruin_pillar")
	mi.free()
	si.free()
	reg.queue_free()


func _test_center_only_and_stream() -> void:
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
	var view := ChunkView.new()
	view.chunk_data = ChunkData.new(Vector2i(0, 0), world)
	cm.chunks[Vector2i(0, 0)] = view
	await process_frame

	_FeatureRegistry.register_feature(4, 5, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(4, 5), "name": "Test Ruin"
	})
	_FeatureRegistry.register_feature(6, 5, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(4, 5), "name": "Test Ruin"
	})
	feat_layer.refresh_cell(4, 5)
	feat_layer.refresh_cell(6, 5)
	await process_frame
	var center: Node3D = feat_layer._nodes_by_cell.get(Vector2i(4, 5))
	var edge: Node3D = feat_layer._nodes_by_cell.get(Vector2i(6, 5))
	if center == null:
		_fail("ruin center anchor missing")
	else:
		if str(center.get_meta("building_visual_id", "")) != "ruin_pillar":
			_fail("center id %s" % center.get_meta("building_visual_id", ""))
		var mesh: MeshInstance3D = center.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or str(mesh.get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
			_fail("center not authored ruin mesh")
		else:
			print("OK ruin center uses authored pillar")
	if edge != null:
		_fail("ruin edge must not get a pillar")
	else:
		print("OK ruin edge has no prop")

	feat_layer.refresh_cell(4, 5)
	await process_frame
	var again: Node3D = feat_layer._nodes_by_cell.get(Vector2i(4, 5))
	if again == null or str((again.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
		_fail("refresh_cell lost authored ruin")
	else:
		print("OK refresh_cell keeps authored ruin")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var streamed: Node3D = feat_layer._nodes_by_cell.get(Vector2i(4, 5))
	var streamed_edge: Node3D = feat_layer._nodes_by_cell.get(Vector2i(6, 5))
	if streamed == null or str((streamed.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != RUIN_MESH_PATH:
		_fail("chunk repopulate lost authored ruin")
	else:
		print("OK chunk repopulate keeps authored ruin")
	if streamed_edge != null:
		_fail("chunk repopulate spawned edge pillar")
	else:
		print("OK chunk repopulate still has no edge pillar")

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
