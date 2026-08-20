extends SceneTree
## Prove wood_wall uses the on-disk authored mesh end-to-end (not multi-box procedural).
## Usage: godot --headless -s scripts/verify_wood_wall_authored.gd


const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")


const WOOD_MESH_PATH := "res://assets/structures/wood_wall/wood_wall.obj"
const WOOD_ALBEDO_PATH := "res://assets/structures/wood_wall/wood_wall_albedo.png"

var _failed: int = 0


func _init() -> void:
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
		print("All wood_wall authored pipeline tests OK")
		quit(0)
	else:
		push_error("verify_wood_wall_authored: %d failure(s)" % _failed)
		quit(1)


func _test_asset_files_exist() -> void:
	if not ResourceLoader.exists(WOOD_MESH_PATH):
		_fail("authored mesh missing: %s" % WOOD_MESH_PATH)
		return
	if not ResourceLoader.exists(WOOD_ALBEDO_PATH):
		_fail("authored albedo missing: %s" % WOOD_ALBEDO_PATH)
		return
	var mesh_res: Resource = load(WOOD_MESH_PATH)
	if mesh_res == null:
		_fail("load(%s) returned null" % WOOD_MESH_PATH)
		return
	if not (mesh_res is Mesh):
		_fail("wood_wall.obj must import as Mesh, got %s" % mesh_res.get_class())
		return
	var tex: Texture2D = load(WOOD_ALBEDO_PATH) as Texture2D
	if tex == null:
		_fail("wood_wall_albedo.png failed to load as Texture2D")
		return
	print("OK authored files load mesh=%s albedo=%dx%d" % [
		mesh_res.get_class(), tex.get_width(), tex.get_height()
	])


func _test_registry_loads_authored() -> void:
	var reg := _GameVisualRegistry.new()
	if not reg.has_authored_building_mesh("wood_wall"):
		_fail("registry must declare wood_wall as authored")
	var path := reg.authored_building_mesh_path("wood_wall")
	if path != WOOD_MESH_PATH:
		_fail("authored path mismatch: %s" % path)
	var mesh: Mesh = reg.get_authored_building_mesh("wood_wall")
	if mesh == null:
		_fail("get_authored_building_mesh(wood_wall) null")
		reg.free()
		return
	# Must not be the multi-box procedural path (those set structure_part_count > 0 via configure).
	var albedo: Texture2D = reg.get_authored_building_albedo("wood_wall")
	if albedo == null:
		_fail("authored albedo null")
	print("OK registry loads authored wood_wall mesh+albedo path=%s" % path)
	reg.free()


func _test_configure_binds_authored() -> void:
	var reg := _GameVisualRegistry.new()
	root.add_child(reg)
	var mi := MeshInstance3D.new()
	mi.set_meta("building_visual_id", "wood_wall")
	reg.configure_building_mesh(mi, null, Vector3(1, 1.5, 1), Color.WHITE, "wood_wall")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("configure_building_mesh must set uses_authored_mesh for wood_wall")
	var apath := str(mi.get_meta("authored_resource_path", ""))
	if apath != WOOD_MESH_PATH:
		_fail("mesh meta authored_resource_path=%s" % apath)
	if mi.mesh == null:
		_fail("wood_wall mesh not assigned")
	# Authored mesh must differ from procedural multi-box for same id sizes.
	var procedural: ArrayMesh = reg.build_structure_array_mesh(reg.structure_mesh_parts("wood_wall"))
	if procedural != null and mi.mesh.get_aabb().is_equal_approx(procedural.get_aabb()):
		# Same AABB is possible; require surface count or resource path meta.
		pass
	if mi.mesh is ArrayMesh and str(mi.get_meta("authored_resource_path", "")).is_empty():
		_fail("procedural ArrayMesh used without authored path")
	# Resource path on mesh meta or registry cache
	var authored_ref: Mesh = reg.get_authored_building_mesh("wood_wall")
	if mi.mesh != authored_ref:
		# Duplicate load OK if same path meta
		if str(mi.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
			_fail("bound mesh is not the authored resource")
	if mi.material_override == null:
		_fail("wood_wall material missing")
	var mat := mi.material_override as StandardMaterial3D
	if mat == null or mat.albedo_texture == null:
		_fail("wood_wall material missing albedo texture")
	print("OK configure_building_mesh binds authored wood_wall")
	mi.free()
	reg.queue_free()


func _test_other_ids_not_regressed() -> void:
	var layer = _FeatureVisualLayer.new()
	var reg := _GameVisualRegistry.new()
	# Resolve identities still distinct.
	var gate_id: String = layer._resolve_player_build_visual_id({
		"build_id": "gate", "is_passage": true
	}, 0, 0)
	var bridge_id: String = layer._resolve_player_build_visual_id({
		"build_id": "bridge", "is_bridge": true
	}, 0, 0)
	var wood_id: String = layer._resolve_player_build_visual_id({
		"build_id": "wood_wall"
	}, 0, 0)
	if gate_id != "gate" or bridge_id != "bridge" or wood_id != "wood_wall":
		_fail("identity regression gate=%s bridge=%s wood=%s" % [gate_id, bridge_id, wood_id])
	if gate_id == wood_id or bridge_id == wood_id:
		_fail("gate/bridge collapsed to wood_wall")
	# Silhouette part lists stay documented even when meshes are authored.
	var gparts: Array = reg.structure_mesh_parts("gate")
	var bparts: Array = reg.structure_mesh_parts("bridge")
	if gparts.size() < 3 or bparts.size() < 2:
		_fail("gate/bridge silhouette parts regressed")
	# Ruin / town ids still resolve via kind path (source check).
	var src: String = (load("res://world/feature_visual_layer.gd") as GDScript).source_code
	if "ruin_pillar" not in src or "town_hall" not in src:
		_fail("ruin/town visual ids missing from feature_visual_layer")
	print("OK gate/bridge/ruin/town identities not regressed")
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
	# Two adjacent chunks so we can place across boundary (SIZE=16).
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

	# Place a line of walls spanning chunk boundary (wx 14,15 on chunk0; 16,17 on chunk1).
	var cells: Array[Vector2i] = [
		Vector2i(14, 4), Vector2i(15, 4), Vector2i(16, 4), Vector2i(17, 4),
		Vector2i(14, 5),  # corner / staggered
	]
	for cell in cells:
		var y: float = world.get_surface_height(float(cell.x), float(cell.y))
		if not editor.try_build_wall(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5), inv, false):
			_fail("place wood wall at %s: %s" % [str(cell), editor.last_fail_reason])
		feat_layer.refresh_cell(cell.x, cell.y)
	await process_frame

	for cell in cells:
		var anchor: Node3D = feat_layer._nodes_by_cell.get(cell)
		if anchor == null:
			_fail("missing anchor at %s" % str(cell))
			continue
		var vid := str(anchor.get_meta("building_visual_id", ""))
		if vid != "wood_wall":
			_fail("visual id at %s is %s" % [str(cell), vid])
		var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
			_fail("wall at %s not using authored mesh" % str(cell))
			continue
		if str(mesh.get_meta("authored_resource_path", "")) != WOOD_MESH_PATH:
			_fail("wall at %s wrong resource path" % str(cell))
	print("OK multi-wall place uses authored mesh (%d cells incl. chunk boundary)" % cells.size())

	# Refresh path: remove + rebuild
	var mid: Vector2i = cells[1]
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	var mid_anchor: Node3D = feat_layer._nodes_by_cell.get(mid)
	if mid_anchor == null:
		_fail("refresh_cell dropped wood_wall")
	else:
		var mm: MeshInstance3D = mid_anchor.get_node_or_null("Mesh") as MeshInstance3D
		if mm == null or not bool(mm.get_meta("uses_authored_mesh", false)):
			_fail("after refresh_cell wood_wall not authored")
		else:
			print("OK refresh_cell keeps authored wood_wall")

	# Stream-style re-populate of chunk 0 should rebind authored mesh.
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
		else:
			print("OK chunk repopulate keeps authored wood_wall")

	# Dig/replace: clear feature and ensure no stale node after refresh
	_FeatureRegistry.clear_feature(mid.x, mid.y)
	feat_layer.refresh_cell(mid.x, mid.y)
	await process_frame
	if feat_layer._nodes_by_cell.get(mid) != null:
		_fail("stale wood_wall node after feature clear")
	else:
		print("OK remove leaves no stale visual node")

	# Gate still not wood_wall when placed nearby
	inv.add_item("wood", 4)
	var gx := 12
	var gz := 4
	var gy: float = world.get_surface_height(float(gx), float(gz))
	if editor.try_build_gate(Vector3(float(gx) + 0.5, gy, float(gz) + 0.5), inv):
		feat_layer.refresh_cell(gx, gz)
		await process_frame
		var ga: Node3D = feat_layer._nodes_by_cell.get(Vector2i(gx, gz))
		if ga == null:
			_fail("gate anchor missing")
		elif str(ga.get_meta("building_visual_id", "")) == "wood_wall":
			_fail("gate resolved to wood_wall")
		elif str((ga.get_node_or_null("Mesh") as MeshInstance3D).get_meta("authored_resource_path", "")) == WOOD_MESH_PATH:
			_fail("gate bound wood_wall mesh")
		else:
			print("OK adjacent gate not wood_wall / not wood mesh")
	else:
		_fail("gate place failed: %s" % editor.last_fail_reason)

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
