extends SceneTree
## Gate / bridge visual identity: must not resolve to wood_wall.
## Usage: godot --headless -s scripts/verify_gate_bridge_visual_identity.gd


const _FeatureVisualLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")


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

	_test_resolve_ids()
	_test_sizes_distinct()
	_test_mesh_silhouettes_distinct()
	_test_textures_distinct()
	_test_source_refresh_wiring()
	await _test_anchors_and_immediate_refresh()

	if _failed == 0:
		print("All gate/bridge visual identity tests OK")
		quit(0)
	else:
		push_error("verify_gate_bridge_visual_identity: %d failure(s)" % _failed)
		quit(1)


## Core mapping: gate → "gate", bridge → "bridge", wood_wall → "wood_wall".
## Must fail if gate or bridge collapses to wood_wall (old DIRT tile_override bug).
func _test_resolve_ids() -> void:
	var layer = _FeatureVisualLayer.new()
	root.add_child(layer)

	var gate_feat := {
		"build_id": "gate",
		"player_built": true,
		"is_passage": true,
		"is_bridge": false,
		"flow_resistance": 0.4,
	}
	var bridge_feat := {
		"build_id": "bridge",
		"player_built": true,
		"is_passage": false,
		"is_bridge": true,
		"flow_resistance": 0.3,
	}
	var wood_feat := {
		"build_id": "wood_wall",
		"player_built": true,
		"is_passage": false,
		"is_bridge": false,
	}

	# Even with DIRT tile_override (gameplay tile for gate/bridge), identity must stay gate/bridge.
	_FeatureRegistry.set_tile_override(100, 100, _VoxelTypes.DIRT)
	_FeatureRegistry.set_tile_override(101, 101, _VoxelTypes.DIRT)
	_FeatureRegistry.set_tile_override(102, 102, _VoxelTypes.DIRT)

	var gate_id: String = layer._resolve_player_build_visual_id(gate_feat, 100, 100)
	var bridge_id: String = layer._resolve_player_build_visual_id(bridge_feat, 101, 101)
	var wood_id: String = layer._resolve_player_build_visual_id(wood_feat, 102, 102)

	if gate_id != "gate":
		_fail("gate visual id expected 'gate' got '%s'" % gate_id)
	if bridge_id != "bridge":
		_fail("bridge visual id expected 'bridge' got '%s'" % bridge_id)
	if wood_id != "wood_wall":
		_fail("wood_wall visual id expected 'wood_wall' got '%s'" % wood_id)

	if gate_id == "wood_wall":
		_fail("gate must not resolve to wood_wall (DIRT tile_override bug)")
	if bridge_id == "wood_wall":
		_fail("bridge must not resolve to wood_wall (DIRT tile_override bug)")
	if gate_id == bridge_id:
		_fail("gate and bridge must have distinct visual ids (both '%s')" % gate_id)
	if gate_id == wood_id or bridge_id == wood_id:
		_fail("gate/bridge must differ from wood_wall (gate=%s bridge=%s wood=%s)" % [gate_id, bridge_id, wood_id])

	var gate_flag := {"is_passage": true, "is_bridge": false}
	var bridge_flag := {"is_passage": false, "is_bridge": true}
	if layer._resolve_player_build_visual_id(gate_flag, 100, 100) != "gate":
		_fail("is_passage flag alone must resolve to gate")
	if layer._resolve_player_build_visual_id(bridge_flag, 101, 101) != "bridge":
		_fail("is_bridge flag alone must resolve to bridge")

	var empty_feat := {}
	var legacy: String = layer._resolve_player_build_visual_id(empty_feat, 100, 100)
	if legacy != "wood_wall":
		_fail("legacy DIRT tile_override without build_id should still map wood_wall, got '%s'" % legacy)

	print("OK resolve: gate=%s bridge=%s wood_wall=%s (DIRT override present)" % [gate_id, bridge_id, wood_id])
	layer.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()


func _test_sizes_distinct() -> void:
	var layer = _FeatureVisualLayer.new()
	var g: Dictionary = layer._visual_size_for_build("gate")
	var b: Dictionary = layer._visual_size_for_build("bridge")
	var w: Dictionary = layer._visual_size_for_build("wood_wall")
	var gs: Vector3 = g.size
	var bs: Vector3 = b.size
	var ws: Vector3 = w.size
	if gs.is_equal_approx(bs) or gs.is_equal_approx(ws) or bs.is_equal_approx(ws):
		_fail("mesh sizes must differ: gate=%s bridge=%s wood=%s" % [gs, bs, ws])
	if bs.y >= gs.y or bs.y >= ws.y:
		_fail("bridge height should be lower than gate/wall (deck silhouette)")
	print("OK sizes distinct gate=%s bridge=%s wood=%s" % [gs, bs, ws])
	layer.free()


## Multi-part silhouettes must differ so boxes-with-tint cannot pass as distinct.
func _test_mesh_silhouettes_distinct() -> void:
	var registry = _GameVisualRegistry.new()
	var ids: Array[String] = ["gate", "bridge", "wood_wall", "stone_wall", "ruin_pillar", "town_hall"]
	var sigs: Dictionary = {}
	for id in ids:
		var parts: Array = registry.structure_mesh_parts(id)
		if parts.is_empty():
			_fail("structure_mesh_parts empty for %s" % id)
			continue
		var mesh: ArrayMesh = registry.build_structure_array_mesh(parts)
		if mesh == null or mesh.get_surface_count() < 1:
			_fail("no array mesh for %s" % id)
			continue
		var aabb: AABB = mesh.get_aabb()
		var sig := "%d:%.2f:%.2f:%.2f" % [parts.size(), aabb.size.x, aabb.size.y, aabb.size.z]
		if sigs.values().has(sig):
			_fail("silhouette collision: %s matches another structure (%s)" % [id, sig])
		sigs[id] = sig
	# Gate must not be a single solid box (passage requires open middle = multi-part).
	if registry.structure_mesh_parts("gate").size() < 3:
		_fail("gate must use multi-part arch silhouette (posts+lintel)")
	if registry.structure_mesh_parts("bridge").size() < 2:
		_fail("bridge must use deck+rail multi-part silhouette")
	# Bridge AABB short; gate/wall tall.
	var gate_aabb := registry.build_structure_array_mesh(registry.structure_mesh_parts("gate")).get_aabb()
	var bridge_aabb := registry.build_structure_array_mesh(registry.structure_mesh_parts("bridge")).get_aabb()
	var wall_aabb := registry.build_structure_array_mesh(registry.structure_mesh_parts("wood_wall")).get_aabb()
	var ruin_aabb := registry.build_structure_array_mesh(registry.structure_mesh_parts("ruin_pillar")).get_aabb()
	var hall_aabb := registry.build_structure_array_mesh(registry.structure_mesh_parts("town_hall")).get_aabb()
	if bridge_aabb.size.y >= gate_aabb.size.y * 0.55:
		_fail("bridge mesh height not clearly lower than gate")
	if bridge_aabb.size.y >= wall_aabb.size.y * 0.55:
		_fail("bridge mesh height not clearly lower than wood_wall")
	if ruin_aabb.size.y <= wall_aabb.size.y:
		_fail("ruin pillar should read taller than wall segment")
	if hall_aabb.size.x <= wall_aabb.size.x * 1.3:
		_fail("town hall footprint should be wider than wall")
	print("OK mesh silhouettes distinct %s" % str(sigs))
	registry.free()


func _test_textures_distinct() -> void:
	var gen := _CrystalTextureGenerator.new()
	var gate_tex: Texture2D = gen.generate_texture(
		_CrystalTextureGenerator.Category.BUILDING, &"gate", 48
	)
	var bridge_tex: Texture2D = gen.generate_texture(
		_CrystalTextureGenerator.Category.BUILDING, &"bridge", 48
	)
	var wood_tex: Texture2D = gen.generate_texture(
		_CrystalTextureGenerator.Category.BUILDING, &"wood_wall", 48
	)
	if gate_tex == null or bridge_tex == null or wood_tex == null:
		_fail("missing generated building texture for gate/bridge/wood_wall")
		return

	var gh := _tex_signature(gate_tex)
	var bh := _tex_signature(bridge_tex)
	var wh := _tex_signature(wood_tex)
	if gh == bh or gh == wh or bh == wh:
		_fail("building textures not distinct: gate=%s bridge=%s wood=%s" % [gh, bh, wh])
		return

	var ga := _tex_avg_rgb(gate_tex)
	var ba := _tex_avg_rgb(bridge_tex)
	var wa := _tex_avg_rgb(wood_tex)
	if ga.distance_to(wa) < 0.08:
		_fail("gate palette too similar to wood_wall (avg dist=%.3f)" % ga.distance_to(wa))
	if ba.distance_to(wa) < 0.08:
		_fail("bridge palette too similar to wood_wall (avg dist=%.3f)" % ba.distance_to(wa))
	if ga.distance_to(ba) < 0.08:
		_fail("gate palette too similar to bridge (avg dist=%.3f)" % ga.distance_to(ba))

	var bundle: Dictionary = gen.generate_game_visual_bundle()
	if not bundle.has("building_gate") or not bundle.has("building_bridge"):
		_fail("generate_game_visual_bundle missing building_gate / building_bridge keys")
	elif not bundle.has("building_wood_wall"):
		_fail("generate_game_visual_bundle missing building_wood_wall")
	else:
		print("OK textures distinct signatures gate=%s bridge=%s wood=%s" % [gh, bh, wh])


func _tex_signature(tex: Texture2D) -> String:
	var img: Image = tex.get_image()
	if img == null:
		return "null"
	var acc := 0
	var step := maxi(1, img.get_width() / 8)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			acc = (acc * 31 + int(c.r * 255.0) + int(c.g * 255.0) * 3 + int(c.b * 255.0) * 7 + int(c.a * 255.0) * 11) & 0x7fffffff
	return "%08x" % acc


func _tex_avg_rgb(tex: Texture2D) -> Vector3:
	var img: Image = tex.get_image()
	if img == null:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var n := 0
	var step := maxi(1, img.get_width() / 12)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return Vector3.ZERO
	return sum / float(n)


func _test_source_refresh_wiring() -> void:
	var layer_src: String = (load("res://world/feature_visual_layer.gd") as GDScript).source_code
	if "structure_placed" not in layer_src:
		_fail("feature_visual_layer must connect structure_placed for immediate place visuals")
	if "func refresh_cell" not in layer_src:
		_fail("feature_visual_layer must expose refresh_cell for placement refresh")
	if "_on_structure_placed_visual" not in layer_src:
		_fail("missing _on_structure_placed_visual handler")
	if "building_visual_id" not in layer_src:
		_fail("anchors must stamp building_visual_id meta")
	if "_resolve_player_build_visual_id" not in layer_src:
		_fail("must use _resolve_player_build_visual_id (not bare DIRT→wood_wall)")
	else:
		print("OK placement refresh path present")


func _test_anchors_and_immediate_refresh() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()

	var root3d := Node3D.new()
	root.add_child(root3d)

	var world_visuals = _WorldVisuals.new()
	root3d.add_child(world_visuals)

	var registry = _GameVisualRegistry.new()
	root3d.add_child(registry)
	# Seed building textures into registry cache (skip full perf/bootstrap).
	var gen := _CrystalTextureGenerator.new()
	registry._gen = gen
	registry._initialized = true
	registry._bundle_ready = true
	registry.feature_billboards_enabled = true
	for bid in [&"gate", &"bridge", &"wood_wall", &"ruin_pillar", &"stone_wall", &"town_hall"]:
		var tex: Texture2D = gen.generate_texture(_CrystalTextureGenerator.Category.BUILDING, bid, 48)
		registry._cache["building_%s" % bid] = tex

	var feat_layer = _FeatureVisualLayer.new()
	world_visuals.add_child(feat_layer)
	feat_layer._registry = registry
	feat_layer._bind_layer_roots()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 99
	world.add_to_group("world")
	root3d.add_child(world)

	var cm := _ChunkManager.new()
	cm.add_to_group("chunk_manager")
	cm.set_process(false)
	cm.set_physics_process(false)
	root3d.add_child(cm)
	var coord := Vector2i(0, 0)
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
	inv.add_item("wood", 20)

	var gx := 3
	var gz := 4
	var gh: float = world.get_surface_height(float(gx), float(gz))
	if not editor.try_build_gate(Vector3(float(gx) + 0.5, gh, float(gz) + 0.5), inv):
		_fail("try_build_gate failed: %s" % editor.last_fail_reason)
	else:
		await process_frame
		var gate_anchor: Node3D = feat_layer._nodes_by_cell.get(Vector2i(gx, gz))
		if gate_anchor == null or not is_instance_valid(gate_anchor):
			feat_layer.refresh_cell(gx, gz)
			await process_frame
			gate_anchor = feat_layer._nodes_by_cell.get(Vector2i(gx, gz))
		if gate_anchor == null:
			_fail("gate anchor missing after placement / refresh_cell")
		else:
			var vid := str(gate_anchor.get_meta("building_visual_id", ""))
			if vid != "gate":
				_fail("placed gate anchor visual id='%s' (must be gate, not wood_wall)" % vid)
			elif "wood_wall" in gate_anchor.name:
				_fail("gate anchor name still wood_wall: %s" % gate_anchor.name)
			else:
				print("OK gate anchor immediate id=%s name=%s" % [vid, gate_anchor.name])

	var bx := 6
	var bz := 7
	_TerrainEdits.dig(bx, bz, 1)
	if not editor.try_build_bridge(Vector3(float(bx) + 0.5, 0.0, float(bz) + 0.5), inv):
		_fail("try_build_bridge failed: %s" % editor.last_fail_reason)
	else:
		await process_frame
		var bridge_anchor: Node3D = feat_layer._nodes_by_cell.get(Vector2i(bx, bz))
		if bridge_anchor == null:
			feat_layer.refresh_cell(bx, bz)
			await process_frame
			bridge_anchor = feat_layer._nodes_by_cell.get(Vector2i(bx, bz))
		if bridge_anchor == null:
			_fail("bridge anchor missing after placement / refresh_cell")
		else:
			var bid := str(bridge_anchor.get_meta("building_visual_id", ""))
			if bid != "bridge":
				_fail("placed bridge anchor visual id='%s' (must be bridge, not wood_wall)" % bid)
			else:
				print("OK bridge anchor immediate id=%s name=%s" % [bid, bridge_anchor.name])

	var wx := 8
	var wz := 9
	if not editor.try_build_wall(Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5), inv, false):
		_fail("try_build_wall wood failed: %s" % editor.last_fail_reason)
	else:
		feat_layer.refresh_cell(wx, wz)
		await process_frame
		var wood_anchor: Node3D = feat_layer._nodes_by_cell.get(Vector2i(wx, wz))
		if wood_anchor == null:
			_fail("wood_wall anchor missing")
		else:
			var wid := str(wood_anchor.get_meta("building_visual_id", ""))
			if wid != "wood_wall":
				_fail("wood_wall visual id='%s'" % wid)
			else:
				print("OK wood_wall anchor id=%s" % wid)

	# Ruin landmark only at center (edge cell of same ruin must not get a wall-like prop).
	_FeatureRegistry.register_feature(10, 11, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(10, 11),
		"name": "Test Ruin",
	})
	_FeatureRegistry.register_feature(12, 11, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(10, 11),
		"name": "Test Ruin",
	})
	feat_layer.refresh_cell(10, 11)
	feat_layer.refresh_cell(12, 11)
	await process_frame
	var ruin_anchor: Node3D = feat_layer._nodes_by_cell.get(Vector2i(10, 11))
	var ruin_edge: Node3D = feat_layer._nodes_by_cell.get(Vector2i(12, 11))
	if ruin_anchor == null:
		_fail("ruin center anchor missing")
	else:
		var rid := str(ruin_anchor.get_meta("building_visual_id", ""))
		if rid != "ruin_pillar":
			_fail("ruin visual id expected ruin_pillar got '%s'" % rid)
		else:
			print("OK ruin remains ruin_pillar")
	if ruin_edge != null:
		_fail("ruin edge cell must not place a building prop (dense pillar field bug)")
	else:
		print("OK ruin edge cell has no prop")

	# Town hall landmark via TOWN_BUILDING at center.
	_FeatureRegistry.register_feature(14, 14, _WorldFeatureTypes.FeatureKind.TOWN_BUILDING, {
		"center": Vector2i(14, 14),
		"name": "Test Town",
		"town_building": "hall",
	})
	feat_layer.refresh_cell(14, 14)
	await process_frame
	var hall_anchor: Node3D = feat_layer._nodes_by_cell.get(Vector2i(14, 14))
	if hall_anchor == null:
		_fail("town_hall anchor missing for TOWN_BUILDING")
	else:
		var hid := str(hall_anchor.get_meta("building_visual_id", ""))
		if hid != "town_hall":
			_fail("town visual id expected town_hall got '%s'" % hid)
		else:
			print("OK town_hall landmark id=%s" % hid)

	var ids: Array[String] = []
	for key in [Vector2i(gx, gz), Vector2i(bx, bz), Vector2i(wx, wz)]:
		var a: Node3D = feat_layer._nodes_by_cell.get(key)
		if a:
			ids.append(str(a.get_meta("building_visual_id", "")))
	if ids.size() == 3:
		if ids[0] == ids[1] or ids[0] == ids[2] or ids[1] == ids[2]:
			_fail("visual identities not unique: %s" % str(ids))
		elif ids[0] == "wood_wall" or ids[1] == "wood_wall":
			_fail("gate or bridge still wood_wall in live anchors: %s" % str(ids))
		else:
			print("OK live identities gate/bridge/wood distinct: %s" % str(ids))
	else:
		_fail("expected 3 player-build anchors, got %d (%s)" % [ids.size(), str(ids)])

	root3d.queue_free()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
