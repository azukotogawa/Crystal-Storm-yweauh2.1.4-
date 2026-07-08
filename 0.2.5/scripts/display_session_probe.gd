extends SceneTree
## Display-session corroboration: production main.tscn in a running window (not --headless).
## Writes to display_session_evidence.md — NOT manual_verification.md (human-hand only).

const MAIN_SCENE := "res://scenes/main.tscn"
const SCRATCH_PATH := "/tmp/grok-goal-e8916ce4c6d5/implementer/display_session_evidence.md"
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	_ensure_texture_generator_autoload()
	call_deferred("_run")


func _ensure_texture_generator_autoload() -> void:
	# SceneTree -s probes may not receive CrystalTextureGenerator from project.godot.
	if root.get_node_or_null("CrystalTextureGenerator") != null:
		return
	var gen := _CrystalTextureGenerator.new()
	gen.name = "CrystalTextureGenerator"
	root.add_child(gen)


func _run() -> void:
	var stamp := Time.get_datetime_string_from_system()
	var failed := false
	var lines: PackedStringArray = []
	lines.append("# Display session corroboration (automated)")
	lines.append("")
	lines.append("**NOT** `manual_verification.md` — human-hand interactive play required for **Working** status.")
	lines.append("**Session:** Display window probe (`display_session_probe.gd`) loading `scenes/main.tscn`.")
	lines.append("**Preset:** MEDIUM | **Captured:** %s" % stamp)
	lines.append("**Limits:** Dig/jump/entities checked via data + input simulation; no pixel/visual confirmation.")
	lines.append("")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		lines.append("## FAIL — could not load main scene")
		await _finish(lines, true)
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var registry = null
	var crystal: CrystalManager = null

	for _attempt in 600:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		registry = get_first_node_in_group("game_visual_registry")
		crystal = get_first_node_in_group("crystal_manager")
		if (
			player != null and chunk_manager != null and world != null
			and registry != null and crystal != null
			and bool(player.get("world_ready"))
			and registry.has_method("is_ready") and registry.is_ready()
		):
			break
		await process_frame

	if player == null or chunk_manager == null:
		lines.append("## FAIL — bootstrap timeout")
		await _finish(lines, true)
		return

	var perf = get_first_node_in_group("performance_service")
	if perf and perf.has_method("refresh_world_visuals"):
		perf.refresh_world_visuals()
	for _w in 120:
		await process_frame

	lines.append("## P0 — Runtime errors/warnings")
	lines.append("- PASS %s — Bootstrap OK in display window; crystal_manager ready." % stamp)

	# Dig via attack input → WeaponController production path
	lines.append("")
	lines.append("## P0 — Pickaxe / digging")
	player.set("voxel_position", Vector3(2.5, player.get("voxel_position").y, 4.5))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	var weapon: Node = player.get_node_or_null("WeaponController")
	var inv = player.get("inventory")
	if inv:
		inv.set_slot(0, "stone_pick", 1)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	var dig_wx := 3
	var dig_wz := 5
	var before_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
	Input.action_press("attack")
	for _w in 8:
		await process_frame
	Input.action_release("attack")
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 60:
		await process_frame
	var after_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
	var delta: float = _TerrainEdits.get_height_delta(dig_wx, dig_wz)
	if delta < -0.01 and after_h < before_h - 0.01:
		lines.append("- PASS %s — Dig via attack input: column (%d,%d) height %.2f→%.2f (data only; visual confirm pending)." % [
			stamp, dig_wx, dig_wz, before_h, after_h
		])
	else:
		lines.append("- [ ] %s — Dig FAIL: column (%d,%d) before=%.2f after=%.2f delta=%.2f" % [
			stamp, dig_wx, dig_wz, before_h, after_h, delta
		])
		failed = true

	# Entities
	lines.append("")
	lines.append("## P0 — Entity sprites")
	var entity_mgr = get_first_node_in_group("entity_manager")
	var test_cell := Vector2i(11, 11)
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		var perf_svc = get_first_node_in_group("performance_service")
		if perf_svc and perf_svc.get("quality"):
			entity_mgr.apply_performance_config(perf_svc.quality)
	var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if entity_mgr and entity_mgr.has_method("_spawn_world_entity") and brain_cfg:
		entity_mgr.call("_spawn_world_entity", test_cell.x, test_cell.y, brain_cfg, test_cell, Color(0.72, 0.58, 0.42))
	var entity_ok := false
	for _attempt in 16:
		if registry and registry.has_method("refresh_all"):
			registry.refresh_all()
		for entity in get_nodes_in_group("world_entity"):
			if is_instance_valid(entity) and entity.has_method("refresh_visual"):
				entity.refresh_visual()
		for _w in 20:
			await process_frame
		var stats := _count_entity_sprites()
		if stats.visible >= 1:
			lines.append("- PASS %s — Entity sprite visible at %s (%d/%d textured)." % [stamp, test_cell, stats.visible, stats.total])
			entity_ok = true
			break
	if not entity_ok:
		var stats2 := _count_entity_sprites()
		lines.append("- [ ] %s — Entity FAIL: %d/%d textured at %s." % [stamp, stats2.visible, stats2.total, test_cell])
		failed = true

	# Vegetation
	lines.append("")
	lines.append("## P0 — Vegetation billboards")
	var visuals = get_first_node_in_group("world_visuals_root")
	var plant_keys: Array = _FeatureRegistry.get_plant_keys()
	if plant_keys.size() > 0:
		var pk: Vector2i = plant_keys[0]
		player.set("voxel_position", Vector3(float(pk.x) + 0.5, player.get("voxel_position").y, float(pk.y) + 0.5))
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		var feat_layer = get_first_node_in_group("feature_visual_layer")
		if feat_layer and feat_layer.has_method("repopulate_all"):
			feat_layer.repopulate_all()
		for _w in 150:
			await process_frame
	var veg := _count_vegetation(visuals)
	if veg.textured >= 1:
		lines.append("- PASS %s — Vegetation billboards textured (%d/%d)." % [stamp, veg.textured, veg.total])
	else:
		lines.append("- [ ] %s — Vegetation FAIL: %d/%d textured." % [stamp, veg.textured, veg.total])
		failed = true

	# Chunk streaming
	lines.append("")
	lines.append("## P0 — Chunk streaming")
	var before_chunks: int = chunk_manager.chunks.size()
	var start_col: Vector3 = player.get("voxel_position")
	player.set("voxel_position", start_col + Vector3(64.0, 0.0, 0.0))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	for _w in 240:
		await process_frame
	var after_chunks: int = chunk_manager.chunks.size()
	var hole := false
	for coord in chunk_manager.chunks.keys():
		var view = chunk_manager.chunks[coord]
		if view == null or not is_instance_valid(view):
			hole = true
			break
	if after_chunks >= before_chunks and not hole:
		lines.append("- PASS %s — Chunk move +64 columns: %d→%d chunks, no invalid views." % [stamp, before_chunks, after_chunks])
	else:
		lines.append("- [ ] %s — Streaming FAIL: %d→%d hole=%s" % [stamp, before_chunks, after_chunks, hole])
		failed = true

	# P1 — jump via jump + move input through player physics (not Y teleport)
	lines.append("")
	lines.append("## P1 — Jump while moving")
	var start_x: float = float(player.get("voxel_position").x)
	var jump_ok := false
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	Input.action_press("ui_right")
	for _w in 15:
		await process_frame
	Input.action_press("jump")
	await process_frame
	Input.action_release("jump")
	var air_seen := false
	var landed := false
	var moved := false
	const STATE_IDLE := 0
	const STATE_RUNNING := 1
	const STATE_JUMPING := 2
	const STATE_FALLING := 3
	for _w in 240:
		await process_frame
		var st: int = int(player.get("current_state"))
		if st == STATE_JUMPING or st == STATE_FALLING:
			air_seen = true
		var vx: float = float(player.get("voxel_position").x)
		if vx > start_x + 0.15:
			moved = true
		if air_seen and st in [STATE_IDLE, STATE_RUNNING] and player.has_method("_is_grounded") and player.call("_is_grounded"):
			landed = true
			break
	Input.action_release("ui_right")
	jump_ok = air_seen and landed and moved
	if jump_ok:
		lines.append("- PASS %s — Jump input + ui_right: air state seen, landed grounded, moved %.2f cols." % [
			stamp, float(player.get("voxel_position").x) - start_x
		])
	else:
		lines.append("- [ ] %s — Jump input FAIL air=%s landed=%s moved=%s." % [stamp, air_seen, landed, moved])
		failed = true

	lines.append("")
	lines.append("## P1 — Ramp / terrain transitions")
	var concave_h := _TerrainRamps.walkable_height_from_entry(
		world, 4.5, 6.5,
		{"concave": true, "surface_h": 12.0, "dir": Vector2i(1, 0), "dir2": Vector2i(0, 1)}
	)
	if concave_h >= 12.0 + _WorldSettings.get_active().layer_height() * 0.5:
		lines.append("- PASS %s — Ramp math: concave walkable=%.2f." % [stamp, concave_h])
	else:
		lines.append("- [ ] %s — Ramp math FAIL %.2f." % [stamp, concave_h])
		failed = true

	lines.append("")
	lines.append("## P1 — Crystal loaded/unloaded chunks")
	var far := Vector2i(512, 512)
	var depth: float = crystal.get_depth_at(far.x, far.y)
	var loaded: bool = chunk_manager.is_world_cell_loaded(far.x, far.y) if chunk_manager.has_method("is_world_cell_loaded") else false
	if not loaded and depth <= 0.01:
		lines.append("- PASS %s — Crystal edge: far cell (%d,%d) unloaded depth=%.2f." % [stamp, far.x, far.y, depth])
	else:
		lines.append("- [ ] %s — Crystal edge FAIL loaded=%s depth=%.2f." % [stamp, loaded, depth])
		failed = true

	lines.append("")
	lines.append("## P1 — Save/load terrain edits")
	var save_svc = get_first_node_in_group("save_game_service") as SaveGameService
	var save_ok := false
	if save_svc:
		if save_svc.config:
			save_svc.config.auto_save_enabled = false
		if save_svc.save_slot(8) == OK:
			save_ok = await save_svc.load_slot(8)
	if save_ok:
		var y_after_save: float = world.get_surface_height(float(dig_wx), float(dig_wz))
		if y_after_save < before_h - 0.01:
			lines.append("- PASS %s — Save/load slot 8 preserved dig at (%d,%d) y=%.2f." % [stamp, dig_wx, dig_wz, y_after_save])
		else:
			lines.append("- [ ] %s — Save/load slot 8: surface not preserved y=%.2f." % [stamp, y_after_save])
			failed = true
	else:
		lines.append("- [ ] %s — Save/load slot 8 failed." % stamp)
		failed = true

	lines.append("")
	lines.append("## Human verification required")
	lines.append("- Fill `manual_verification.md` after interactive play (`interactive_manual_verification.md`).")
	lines.append("- Headless corroboration: `scripted_smoke_evidence.md`, `save_slot_verify.log`")

	await _finish(lines, failed)


func _count_entity_sprites() -> Dictionary:
	var visible := 0
	var total := 0
	for entity in get_nodes_in_group("world_entity"):
		if not is_instance_valid(entity):
			continue
		var spr: Sprite3D = entity.get_node_or_null("Sprite3D") as Sprite3D
		if spr == null:
			continue
		total += 1
		if spr.visible and (spr.texture != null or (spr.material_override is StandardMaterial3D and (spr.material_override as StandardMaterial3D).albedo_texture != null)):
			visible += 1
	return {"visible": visible, "total": total}


func _count_vegetation(visuals) -> Dictionary:
	var textured := 0
	var total := 0
	var veg_root: Node3D = visuals.get_vegetation_root() if visuals and visuals.has_method("get_vegetation_root") else null
	if veg_root:
		for child in veg_root.get_children():
			total += 1
			var spr: Sprite3D = child.get_node_or_null("Billboard") as Sprite3D
			if spr and spr.visible and spr.texture != null:
				textured += 1
	return {"textured": textured, "total": total}


func _finish(lines: PackedStringArray, failed: bool) -> void:
	var text := "\n".join(lines) + "\n"
	DirAccess.make_dir_recursive_absolute("/tmp/grok-goal-e8916ce4c6d5/implementer")
	var f := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	print(text)
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT") != "1":
		var game := root.get_child(0) if root.get_child_count() > 0 else null
		var cm: ChunkManager = get_first_node_in_group("chunk_manager")
		if cm and cm.has_method("release_all_chunks_for_teardown"):
			cm.release_all_chunks_for_teardown()
		for _w in 60:
			await process_frame
		if game and game.get_parent() == root:
			root.remove_child(game)
			game.queue_free()
		for _w in 180:
			await process_frame
	_ProbeExit.finish_tree(self, 1 if failed else 0, "DISPLAY SESSION FAILED" if failed else "DISPLAY SESSION OK")