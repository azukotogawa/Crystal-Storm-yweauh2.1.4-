extends SceneTree
## Maps manual_verification.md unchecked items to structural runtime proof (NOT human sign-off).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var lines: PackedStringArray = []
	lines.append("# Manual checklist corroboration (automated — NOT sign-off)")
	lines.append("")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_finish(lines, true)
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var weapon: Node = null
	var registry = null

	for _attempt in 800:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		weapon = player.get_node_or_null("WeaponController") if player else null
		registry = get_first_node_in_group("game_visual_registry")
		if (
			player and chunk_manager and world and weapon
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 4
			and (not registry or not registry.has_method("is_ready") or registry.is_ready())
		):
			break
		await process_frame

	if player == null or chunk_manager == null or world == null:
		lines.append("FAIL bootstrap timeout")
		_finish(lines, true)
		return

	var inv = player.get("inventory")
	var terrain_editor: TerrainEditor = get_first_node_in_group("terrain_editor") as TerrainEditor
	for _w in 120:
		if terrain_editor != null:
			break
		terrain_editor = get_first_node_in_group("terrain_editor") as TerrainEditor
		await process_frame

	player.set("voxel_position", Vector3(2.5, player.get("voxel_position").y, 4.5))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")

	# Dig carve (mirror smoke_gameplay coordinates)
	lines.append("## Digging — visible carve")
	var pick_def := _ItemTypes.get_def("stone_pick")
	if inv:
		inv.set_slot(1, "stone_pick", 1)
	if weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(1)
	var range_v: float = float(pick_def.get("range", 2.4))
	_ActionTargeting.warp_mouse_to_column(player, world, 3.5, 5.5)
	for _w in 8:
		await process_frame
	var dig_pick: Vector2i = _ActionTargeting.target_cell(player, range_v)
	var dig_wx := dig_pick.x
	var dig_wz := dig_pick.y
	var before_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
	weapon.set("_cooldown_timer", 0.0)
	weapon.call("_do_dig_attack", "stone_pick", pick_def)
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 40:
		await process_frame
	var after_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
	var delta: float = _TerrainEdits.get_height_delta(dig_wx, dig_wz)
	var mesh_sy: float = _SmokeProbeHelpers.dig_mesh_surface_y(chunk_manager, dig_wx, dig_wz)
	var mesh_ok := mesh_sy >= 0.0 and mesh_sy < before_h - 0.01 and absf(mesh_sy - after_h) < 0.2
	if delta < -0.01 and after_h < before_h - 0.01 and mesh_ok:
		lines.append("PASS dig carve wx=%d wz=%d %.2f→%.2f mesh_y=%.2f" % [dig_wx, dig_wz, before_h, after_h, mesh_sy])
		print("OK dig carve delta=%.2f" % delta)
	else:
		lines.append("FAIL dig carve delta=%.2f before=%.2f after=%.2f mesh=%.2f" % [delta, before_h, after_h, mesh_sy])
		push_error("dig carve failed")
		failed = true

	# Tool-gated highlights (ActionTargeting modes)
	lines.append("")
	lines.append("## Highlights — tool-gated modes")
	if inv:
		inv.set_slot(1, "stone_pick", 1)
		weapon.set_active_hotbar_index(1)
	var dig_mode = _ActionTargeting.resolve_action(player, world, chunk_manager, 2.4).get("mode")
	if inv:
		inv.set_slot(0, "wooden_sword", 1)
		weapon.set_active_hotbar_index(0)
	var atk_mode = _ActionTargeting.resolve_action(player, world, chunk_manager, 2.8).get("mode")
	if inv:
		inv.set_slot(2, "stone", 4)
		weapon.set_active_hotbar_index(2)
	var build_mode = _ActionTargeting.resolve_action(player, world, chunk_manager, 2.0).get("mode")
	if dig_mode == &"dig" and atk_mode == &"attack" and build_mode == &"build":
		lines.append("PASS highlight modes dig=%s attack=%s build=%s" % [dig_mode, atk_mode, build_mode])
		print("OK highlight modes dig/attack/build")
	else:
		lines.append("FAIL modes dig=%s attack=%s build=%s" % [dig_mode, atk_mode, build_mode])
		push_error("highlight modes wrong")
		failed = true

	# Build wall (mirror display_session_probe)
	lines.append("")
	lines.append("## Build — stone wall")
	var build_wx := 20
	var build_wz := 22
	_ActionTargeting.warp_mouse_to_column(player, world, float(build_wx) + 0.5, float(build_wz) + 0.5)
	for _w in 10:
		await process_frame
	if inv:
		if inv.count_item("stone") < 2:
			inv.add_item("stone", 4)
		inv.set_slot(0, "stone", 4)
	if weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	weapon.set("_cooldown_timer", 0.0)
	var build_target: Vector3 = _ActionTargeting.target_column(player, 2.0)
	build_wx = floori(build_target.x)
	build_wz = floori(build_target.z)
	var build_ok := false
	if weapon.has_method("_try_build_wall"):
		weapon.call("_try_build_wall")
		build_ok = _TerrainEdits.get_height_delta(build_wx, build_wz) > 0.01
	if not build_ok and terrain_editor and inv:
		build_ok = terrain_editor.try_build_wall(build_target, inv, inv.count_item("stone") > 0)
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 40:
		await process_frame
	var build_delta: float = _TerrainEdits.get_height_delta(build_wx, build_wz)
	if build_delta > 0.01 and _TerrainEdits.get_build_tile(build_wx, build_wz) >= 0:
		lines.append("PASS build wall wx=%d wz=%d delta=%.2f" % [build_wx, build_wz, build_delta])
		print("OK build wall delta=%.2f" % build_delta)
	else:
		lines.append("FAIL build delta=%.2f tile=%s editor=%s" % [
			build_delta, _TerrainEdits.get_build_tile(build_wx, build_wz), terrain_editor != null
		])
		push_error("build wall failed")
		failed = true

	# Terrain atlas variety
	lines.append("")
	lines.append("## Visuals — terrain atlas")
	var atlas_cells: Dictionary = {}
	var atlas_bound := false
	for coord in chunk_manager.chunks.keys():
		var view: ChunkView = chunk_manager.chunks[coord] as ChunkView
		if view == null or view.chunk_data == null:
			continue
		var mm: MultiMeshInstance3D = view.get_node_or_null("LayerContainer/mm_instance") as MultiMeshInstance3D
		if mm and mm.material_override is ShaderMaterial:
			var tex: Texture2D = (mm.material_override as ShaderMaterial).get_shader_parameter("texture_atlas")
			if tex != null and "Cube.png" in tex.resource_path:
				atlas_bound = true
		if chunk_manager.has_method("_build_mesh"):
			for q in chunk_manager._build_mesh(view.chunk_data).get("quads", []):
				var c: Vector2i = _VoxelTypes.get_atlas_coord(int(q.get("type", -1)))
				atlas_cells["%d,%d" % [c.x, c.y]] = true
	if atlas_bound and atlas_cells.size() >= 3:
		lines.append("PASS atlas Cube.png cells=%d" % atlas_cells.size())
		print("OK atlas cells=%d" % atlas_cells.size())
	else:
		lines.append("FAIL atlas bound=%s cells=%d" % [atlas_bound, atlas_cells.size()])
		push_error("atlas variety failed")
		failed = true

	# Ramps structural
	lines.append("")
	lines.append("## Visuals — ramps")
	var ramp_counts := {FACE_RAMP: 0, FACE_RAMP_CORNER: 0, FACE_RAMP_SIDE: 0}
	for coord in chunk_manager.chunks.keys():
		var view: ChunkView = chunk_manager.chunks[coord] as ChunkView
		if view == null or view.chunk_data == null or not chunk_manager.has_method("_build_mesh"):
			continue
		for q in chunk_manager._build_mesh(view.chunk_data).get("quads", []):
			var fc := int(q.get("face_code", -1))
			if ramp_counts.has(fc):
				ramp_counts[fc] += 1
	# Synthetic L-step proves corner prisms emit (spawn area may have corner=0 at 28% placement).
	var corner_synth_ok := _synthetic_corner_ramp_ok()
	if ramp_counts[FACE_RAMP] >= 1 and ramp_counts[FACE_RAMP_SIDE] >= 1 and corner_synth_ok:
		lines.append("PASS ramps cardinal=%d corner=%d concave=%d synth_corner=1" % [
			ramp_counts[FACE_RAMP], ramp_counts[FACE_RAMP_CORNER], ramp_counts[FACE_RAMP_SIDE]
		])
		print("OK ramp face codes present synth_corner=1")
	else:
		lines.append("FAIL ramps cardinal=%d corner=%d concave=%d synth_corner=%s" % [
			ramp_counts[FACE_RAMP], ramp_counts[FACE_RAMP_CORNER], ramp_counts[FACE_RAMP_SIDE], corner_synth_ok
		])
		push_error("ramp mesh missing face codes or synthetic corner failed")
		failed = true

	# Vegetation / entities voxel
	lines.append("")
	lines.append("## Visuals — voxel props")
	var entity_mgr = get_first_node_in_group("entity_manager")
	var test_cell := Vector2i(11, 11)
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		var perf_svc = get_first_node_in_group("performance_service")
		if perf_svc and perf_svc.get("quality"):
			entity_mgr.apply_performance_config(perf_svc.quality)
	var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if entity_mgr and entity_mgr.has_method("_spawn_world_entity") and brain_cfg:
		entity_mgr.call("_spawn_world_entity", test_cell.x, test_cell.y, brain_cfg, test_cell, Color(0.72, 0.58, 0.42))
	var ent := {"visible": 0, "total": 0}
	for _attempt in 16:
		if registry and registry.has_method("refresh_all"):
			registry.refresh_all()
		for entity in get_nodes_in_group("world_entity"):
			if is_instance_valid(entity) and entity.has_method("refresh_visual"):
				entity.refresh_visual()
		for _w in 20:
			await process_frame
		ent = _SmokeProbeHelpers.count_entity_sprites(self)
		if ent.visible >= 1:
			break
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	var plant_keys: Array = _FeatureRegistry.get_plant_keys()
	if plant_keys.size() > 0 and feat_layer and feat_layer.has_method("repopulate_all"):
		var pk: Vector2i = plant_keys[0]
		player.set("voxel_position", Vector3(float(pk.x) + 0.5, player.get("voxel_position").y, float(pk.y) + 0.5))
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		feat_layer.repopulate_all()
	for _w in 150:
		await process_frame
	var visuals = get_first_node_in_group("world_visuals_root")
	var veg := _SmokeProbeHelpers.count_vegetation(visuals)
	if veg.textured >= 1 and ent.visible >= 1:
		lines.append("PASS vegetation=%d/%d entities=%d/%d" % [veg.textured, veg.total, ent.visible, ent.total])
		print("OK veg=%d entities=%d" % [veg.textured, ent.visible])
	else:
		lines.append("FAIL veg=%d/%d entities=%d/%d" % [veg.textured, veg.total, ent.visible, ent.total])
		push_error("voxel props insufficient")
		failed = true

	_finish(lines, failed)


func _synthetic_corner_ramp_ok() -> bool:
	var layer: float = _WorldSettings.get_active().layer_height()
	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var world: InfiniteNoiseWorld = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	for x in ChunkData.SIZE:
		if data.surface_map.size() <= x:
			data.surface_map.append([])
			data.tile_map.append([])
		data.surface_map[x].resize(ChunkData.SIZE)
		data.tile_map[x].resize(ChunkData.SIZE)
		for z in ChunkData.SIZE:
			data.surface_map[x][z] = 8.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND

	var cx := 6
	var cz := 6
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[cx][cz] = low_h
	data.tile_map[cx][cz] = _VoxelTypes.GRASSLAND
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		data.surface_map[cx + d.x][cz + d.y] = high_h
		data.tile_map[cx + d.x][cz + d.y] = _VoxelTypes.GRASSLAND

	var cm := ChunkManager.new()
	cm.ramp_placement_chance = 100
	var corner := 0
	for q in cm._build_mesh(data).get("quads", []):
		if int(q.get("face_code", -1)) == FACE_RAMP_CORNER:
			corner += 1

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()
	return corner >= 1


func _finish(lines: PackedStringArray, failed: bool) -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-4d59198f47c0/implementer/manual_checklist_corroboration.md"
	else:
		scratch = scratch.path_join("manual_checklist_corroboration.md")
	DirAccess.make_dir_recursive_absolute(scratch.get_base_dir())
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("\n".join(lines))
	if failed:
		_ProbeExit.finish_tree(self, 1, "Manual checklist corroboration FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "Manual checklist corroboration OK")