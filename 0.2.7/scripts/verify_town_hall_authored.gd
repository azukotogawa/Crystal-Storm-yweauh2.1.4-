extends SceneTree
## Prove town_hall uses the on-disk authored mesh, only on TOWN_BUILDING cells.
## Usage: godot --headless -s scripts/verify_town_hall_authored.gd


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")


const HALL_MESH_PATH := "res://assets/structures/town_hall/town_hall.obj"
const HALL_ALBEDO_PATH := "res://assets/structures/town_hall/town_hall_albedo.png"
const RUIN_MESH_PATH := "res://assets/structures/ruin_pillar/ruin_pillar.obj"
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
	await _test_town_center_only()
	if _failed == 0:
		print("All town_hall authored pipeline tests OK")
		quit(0)
	else:
		push_error("verify_town_hall_authored: %d failure(s)" % _failed)
		quit(1)


func _test_asset_files_exist() -> void:
	if not ResourceLoader.exists(HALL_MESH_PATH) or not ResourceLoader.exists(HALL_ALBEDO_PATH):
		_fail("authored town_hall files missing")
		return
	var mesh_res: Resource = load(HALL_MESH_PATH)
	if mesh_res == null or not (mesh_res is Mesh):
		_fail("town_hall.obj must import as Mesh")
		return
	var tex: Texture2D = load(HALL_ALBEDO_PATH) as Texture2D
	if tex == null or tex.get_width() != 256:
		_fail("town_hall albedo expected 256px Texture2D")
		return
	var aabb: AABB = (mesh_res as Mesh).get_aabb()
	# Wide hall with a roof, not a wall / pillar / deck / cube.
	if aabb.size.x < 1.2:
		_fail("town_hall too narrow to be a hall (w=%.3f)" % aabb.size.x)
	if aabb.size.y < 2.0:
		_fail("town_hall roof too short (h=%.3f)" % aabb.size.y)
	if aabb.size.y > aabb.size.x * 2.2:
		_fail("town_hall looks like a tower not a hall (size=%s)" % str(aabb.size))
	if is_equal_approx(aabb.size.x, aabb.size.y) and is_equal_approx(aabb.size.y, aabb.size.z):
		_fail("town_hall looks like a cube")
	var body := 0
	var roof := 0
	for si in (mesh_res as Mesh).get_surface_count():
		var verts: PackedVector3Array = (mesh_res as Mesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for p in verts:
			if p.y < 1.35 and absf(p.x) > 0.40:
				body += 1
			if p.y > 1.55:
				roof += 1
	if body < 8:
		_fail("town_hall missing wide hall body (%d verts)" % body)
	if roof < 8:
		_fail("town_hall missing pitched roof (%d verts)" % roof)
	print("OK authored files load mesh=%s albedo=%dx%d aabb=%s body=%d roof=%d" % [
		mesh_res.get_class(), tex.get_width(), tex.get_height(), str(aabb.size), body, roof
	])


func _test_registry_loads_authored() -> void:
	var reg := _GameVisualRegistry.new()
	if not reg.has_authored_building_mesh("town_hall"):
		_fail("registry must declare town_hall as authored")
	if reg.authored_building_mesh_path("town_hall") != HALL_MESH_PATH:
		_fail("authored path mismatch")
	var mesh: Mesh = reg.get_authored_building_mesh("town_hall")
	if mesh == null:
		_fail("get_authored_building_mesh(town_hall) null")
		reg.free()
		return
	for id in ["wood_wall", "stone_wall", "gate", "bridge", "ruin_pillar"]:
		if not reg.has_authored_building_mesh(id):
			_fail("%s authored bind regressed" % id)
	if reg.get_authored_building_albedo("town_hall") == null:
		_fail("authored albedo null")
	var others: Array[String] = ["wood_wall", "stone_wall", "gate", "bridge", "ruin_pillar"]
	for id in others:
		var other: Mesh = reg.get_authored_building_mesh(id)
		if other == null:
			continue
		if mesh == other:
			_fail("town_hall shares %s mesh" % id)
		elif mesh.get_aabb().size.is_equal_approx(other.get_aabb().size):
			_fail("town_hall AABB matches %s %s" % [id, str(other.get_aabb().size)])
	print("OK town AABB distinct hall=%s wood=%s stone=%s gate=%s bridge=%s ruin=%s" % [
		str(mesh.get_aabb().size),
		str(reg.get_authored_building_mesh("wood_wall").get_aabb().size),
		str(reg.get_authored_building_mesh("stone_wall").get_aabb().size),
		str(reg.get_authored_building_mesh("gate").get_aabb().size),
		str(reg.get_authored_building_mesh("bridge").get_aabb().size),
		str(reg.get_authored_building_mesh("ruin_pillar").get_aabb().size)
	])
	print("OK registry loads authored town_hall")
	reg.free()


func _test_configure_binds_authored() -> void:
	var reg := _GameVisualRegistry.new()
	root.add_child(reg)
	var mi := MeshInstance3D.new()
	reg.configure_building_mesh(mi, null, Vector3(2.4, 3.0, 2.4), Color.WHITE, "town_hall")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("configure must set uses_authored_mesh")
	if str(mi.get_meta("authored_resource_path", "")) != HALL_MESH_PATH:
		_fail("wrong authored path")
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		_fail("hall material missing albedo")
	elif mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
		_fail("hall must use nearest filter")
	if not is_equal_approx(mi.scale.y, 1.0):
		_fail("hall Y scale should be 1.0, got %.3f" % mi.scale.y)
	print("OK configure_building_mesh binds authored town_hall")
	mi.free()
	reg.queue_free()


func _test_town_center_only() -> void:
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

	_FeatureRegistry.register_feature(5, 5, _WorldFeatureTypes.FeatureKind.TOWN, {
		"center": Vector2i(5, 5), "name": "Test Town", "radius": 2
	})
	_FeatureRegistry.register_feature(5, 5, _WorldFeatureTypes.FeatureKind.TOWN_BUILDING, {
		"center": Vector2i(5, 5), "name": "Test Town", "town_building": "hall"
	})
	_FeatureRegistry.register_feature(6, 5, _WorldFeatureTypes.FeatureKind.TOWN, {
		"center": Vector2i(5, 5), "name": "Test Town", "radius": 2
	})
	feat_layer.refresh_cell(5, 5)
	feat_layer.refresh_cell(6, 5)
	await process_frame
	var hall: Node3D = feat_layer._nodes_by_cell.get(Vector2i(5, 5))
	var disk: Node3D = feat_layer._nodes_by_cell.get(Vector2i(6, 5))
	if hall == null:
		_fail("town center hall missing")
	else:
		if str(hall.get_meta("building_visual_id", "")) != "town_hall":
			_fail("center id %s" % hall.get_meta("building_visual_id", ""))
		var mesh: MeshInstance3D = hall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or str(mesh.get_meta("authored_resource_path", "")) != HALL_MESH_PATH:
			_fail("center not authored hall")
		else:
			print("OK town center uses authored hall")
	if disk != null:
		_fail("TOWN disk cell must not get a hall prop")
	else:
		print("OK TOWN disk cell has no hall")

	feat_layer.refresh_cell(5, 5)
	await process_frame
	var again: Node3D = feat_layer._nodes_by_cell.get(Vector2i(5, 5))
	if again == null or str((again.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != HALL_MESH_PATH:
		_fail("refresh_cell lost authored hall")
	else:
		print("OK refresh_cell keeps authored hall")

	feat_layer._populate_chunk(Vector2i(0, 0))
	await process_frame
	var streamed: Node3D = feat_layer._nodes_by_cell.get(Vector2i(5, 5))
	var streamed_disk: Node3D = feat_layer._nodes_by_cell.get(Vector2i(6, 5))
	if streamed == null or str((streamed.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) != HALL_MESH_PATH:
		_fail("chunk repopulate lost authored hall")
	else:
		print("OK chunk repopulate keeps authored hall")
	if streamed_disk != null:
		_fail("chunk repopulate spawned disk hall")
	else:
		print("OK chunk repopulate still has no disk hall")

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
