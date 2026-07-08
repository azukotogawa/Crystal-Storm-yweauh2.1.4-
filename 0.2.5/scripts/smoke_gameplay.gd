extends SceneTree
## Scripted play session: loads production main.tscn and exercises real gameplay paths.
## Evidence → SCRATCH_PATH (scripted session, not human-hand manual QA).

const MAIN_SCENE := "res://scenes/main.tscn"
const SCRATCH_PATH := "/tmp/grok-goal-e8916ce4c6d5/implementer/scripted_smoke_evidence.md"
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _force_fail_mode() -> String:
	return OS.get_environment("SMOKE_FORCE_FAIL").strip_edges().to_lower()


func _run() -> void:
	var failed := false
	var lines: PackedStringArray = []
	var stamp := Time.get_datetime_string_from_system()
	lines.append("# Gameplay verification log")
	lines.append("")
	lines.append("**Method:** Headless scripted smoke (`smoke_gameplay.gd`) — NOT interactive manual QA.")
	lines.append("Exercises WeaponController._do_dig_attack, EntityManager._spawn_world_entity, production boot.")
	lines.append("For **Working** status see `manual_verification.md` (human-hand session required).")
	lines.append("")
	lines.append("Preset: MEDIUM | Captured: %s" % stamp)
	lines.append("")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		lines.append("## Bootstrap FAIL — could not load main scene")
		await _finish(lines, true)
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null
	var registry = null
	var crystal: CrystalManager = null

	for _attempt in 600:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		registry = get_first_node_in_group("game_visual_registry")
		crystal = get_first_node_in_group("crystal_manager")
		if (
			player != null
			and chunk_manager != null
			and terrain != null
			and terrain.chunk_manager != null
			and world != null
			and registry != null
			and crystal != null
			and bool(player.get("world_ready"))
			and registry.has_method("is_ready")
			and registry.is_ready()
		):
			break
		await process_frame

	if player == null or chunk_manager == null or terrain == null:
		lines.append("## Bootstrap FAIL — timeout waiting for playable state")
		await _finish(lines, true)
		return

	var perf = get_first_node_in_group("performance_service")
	if perf and perf.has_method("refresh_world_visuals"):
		perf.refresh_world_visuals()
	for _w in 120:
		await process_frame

	lines.append("## P0 — Runtime")
	lines.append("- Bootstrap OK: player, chunk_manager, terrain_editor, crystal_manager ready.")

	if _force_fail_mode() == "1":
		lines.append("")
		lines.append("## P0 — Forced fail (quit-path harness)")
		lines.append("- **Dig FAIL**: SMOKE_FORCE_FAIL=1")
		await _finish(lines, true)
		return

	# --- Pickaxe via WeaponController (production dig path) ---
	lines.append("")
	lines.append("## P0 — Pickaxe / digging (WeaponController)")
	player.set("voxel_position", Vector3(2.5, player.get("voxel_position").y, 4.5))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")

	var weapon: Node = player.get_node_or_null("WeaponController")
	var pick_def: Dictionary = _ItemTypes.get_def("stone_pick")
	var dug := false
	var dig_wx := -1
	var dig_wz := -1
	if weapon != null and pick_def and weapon.has_method("_do_dig_attack") and weapon.has_method("_attack_forward"):
		var inv = player.get("inventory")
		if inv:
			inv.set_slot(1, "stone_pick", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(1)
		var forward: Vector3 = weapon.call("_attack_forward")
		var range_v: float = float(pick_def.get("range", 2.0))
		var target: Vector3 = player.get("voxel_position") + forward * range_v
		dig_wx = floori(target.x)
		dig_wz = floori(target.z)
		var before_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
		weapon.call("_do_dig_attack", "stone_pick", pick_def)
		if chunk_manager.has_method("await_rebuild_idle"):
			await chunk_manager.await_rebuild_idle()
		for _w in 40:
			await process_frame
		var after_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
		var delta: float = _TerrainEdits.get_height_delta(dig_wx, dig_wz)
		dug = delta < -0.01 and after_h < before_h - 0.01
		if dug:
			lines.append("- **Dig OK**: WeaponController column (%d,%d) %.2f→%.2f delta=%.2f (data only; visual confirm pending)." % [
				dig_wx, dig_wz, before_h, after_h, delta
			])
		else:
			lines.append("- **Dig FAIL**: target_col=(%d,%d) before=%.2f after=%.2f delta=%.2f" % [
				dig_wx, dig_wz, before_h, after_h, delta
			])
			failed = true
	else:
		lines.append("- **Dig FAIL**: WeaponController missing dig API")
		failed = true

	# --- Entities: EntityManager._spawn_world_entity + registry refresh (production path) ---
	lines.append("")
	lines.append("## P0 — Entity sprites")
	var entity_mgr = get_first_node_in_group("entity_manager")
	var test_cell := Vector2i(11, 11)
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		var perf_svc = get_first_node_in_group("performance_service")
		if perf_svc and perf_svc.get("quality"):
			entity_mgr.apply_performance_config(perf_svc.quality)
	player.set("voxel_position", Vector3(float(test_cell.x) + 0.5, player.get("voxel_position").y, float(test_cell.y) + 0.5))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	var chunk_coord := chunk_manager.world_to_chunk_coord(test_cell.x, test_cell.y)
	if chunk_manager.has_method("update_stream"):
		chunk_manager.update_stream(chunk_coord.x, chunk_coord.y)
	for _w in 120:
		await process_frame
		if chunk_manager.chunks.has(chunk_coord):
			break
	var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if _force_fail_mode() == "entities":
		brain_cfg = null
	if entity_mgr and entity_mgr.has_method("_spawn_world_entity") and brain_cfg:
		entity_mgr.call(
			"_spawn_world_entity",
			test_cell.x, test_cell.y, brain_cfg, test_cell, Color(0.72, 0.58, 0.42)
		)
	var sprite_stats := {"visible": 0, "total": 0}
	for _attempt in 16:
		if registry and registry.has_method("refresh_all"):
			registry.refresh_all()
		for entity in get_nodes_in_group("world_entity"):
			if is_instance_valid(entity) and entity.has_method("refresh_visual"):
				entity.refresh_visual()
		for _w in 20:
			await process_frame
		sprite_stats = _count_entity_sprites()
		if sprite_stats.visible >= 1:
			break
	if sprite_stats.visible >= 1:
		lines.append("- **Entities OK**: %d/%d textured sprites (EntityManager spawn at %s)." % [
			sprite_stats.visible, sprite_stats.total, test_cell
		])
	else:
		lines.append("- **Entities FAIL**: %d/%d textured sprites after EntityManager spawn." % [
			sprite_stats.visible, sprite_stats.total
		])
		failed = true

	# --- Vegetation ---
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
	var veg_stats := _count_vegetation(visuals)
	if veg_stats.textured >= 1:
		lines.append("- **Vegetation OK**: %d/%d billboards textured." % [veg_stats.textured, veg_stats.total])
	else:
		lines.append("- **Vegetation FAIL**: %d billboards, %d textured." % [veg_stats.total, veg_stats.textured])
		failed = true

	# --- Chunk streaming ---
	lines.append("")
	lines.append("## P0 — Chunk streaming")
	var chunks_before: int = chunk_manager.chunks.size()
	var start_col: Vector3 = player.get("voxel_position")
	player.set("voxel_position", start_col + Vector3(64.0, 0.0, 0.0))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	for _w in 240:
		await process_frame
	var chunks_after: int = chunk_manager.chunks.size()
	var hole := false
	for coord in chunk_manager.chunks.keys():
		var view = chunk_manager.chunks[coord]
		if view == null or not is_instance_valid(view):
			hole = true
			break
	if chunks_after >= chunks_before and not hole:
		lines.append("- **Streaming OK**: chunks %d→%d after +64 column move; no invalid views." % [chunks_before, chunks_after])
	else:
		lines.append("- **Streaming FAIL**: chunks %d→%d hole=%s" % [chunks_before, chunks_after, hole])
		failed = true

	# --- P1 Jump via jump + move input through player physics (not Y teleport) ---
	lines.append("")
	lines.append("## P1 — Jump while moving")
	var probe = player.get("_floor_probe")
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
		lines.append("- **Jump OK**: jump input + ui_right; air state seen, landed grounded, moved %.2f cols." % [
			float(player.get("voxel_position").x) - start_x
		])
	else:
		lines.append("- **Jump FAIL**: jump input air=%s landed=%s moved=%s." % [air_seen, landed, moved])
		failed = true

	# --- P1 Ramp / step ---
	lines.append("")
	lines.append("## P1 — Ramp collision / terrain transitions")
	var concave_h := _TerrainRamps.walkable_height_from_entry(
		world, 4.5, 6.5,
		{"concave": true, "surface_h": 12.0, "dir": Vector2i(1, 0), "dir2": Vector2i(0, 1)}
	)
	var layer_h: float = _WorldSettings.get_active().layer_height()
	if concave_h >= 12.0 + layer_h * 0.5:
		lines.append("- **Ramp OK**: concave walkable=%.2f above carved floor (probe math)." % concave_h)
	else:
		lines.append("- **Ramp FAIL**: concave walkable too low %.2f" % concave_h)
		failed = true
	if probe != null and probe.has_method("sample_walkable_feet"):
		var feet: float = probe.sample_walkable_feet(float(test_cell.x) + 0.5, float(test_cell.y) + 0.5)
		if feet > 0.0:
			lines.append("- **Ramp OK**: floor probe feet=%.2f at entity spawn column." % feet)
		else:
			lines.append("- **Ramp FAIL**: floor probe returned non-positive feet height.")
			failed = true

	# --- P1 Crystal chunk edge ---
	lines.append("")
	lines.append("## P1 — Crystal loaded/unloaded chunks")
	var far_cell := Vector2i(512, 512)
	var depth_far: float = crystal.get_depth_at(far_cell.x, far_cell.y) if crystal else 0.0
	var loaded_far: bool = chunk_manager.is_world_cell_loaded(far_cell.x, far_cell.y) if chunk_manager.has_method("is_world_cell_loaded") else false
	if not loaded_far and depth_far <= 0.01:
		lines.append("- **Crystal edge OK**: far cell (%d,%d) unloaded, depth=%.2f." % [far_cell.x, far_cell.y, depth_far])
	else:
		lines.append("- **Crystal edge FAIL**: far loaded=%s depth=%.2f (expected unloaded+zero)." % [loaded_far, depth_far])
		failed = true
	var cells_before: int = crystal.covered_cells if "covered_cells" in crystal else 0
	for _w in 30:
		await process_frame
	var cells_after: int = crystal.covered_cells if "covered_cells" in crystal else 0
	if cells_after >= cells_before:
		lines.append("- **Crystal edge OK**: sim tick stable cells %d→%d near player bubble." % [cells_before, cells_after])
	else:
		lines.append("- **Crystal edge FAIL**: cell count dropped unexpectedly.")
		failed = true

	lines.append("")
	lines.append("## P1 — Save/load terrain edits")
	lines.append("- In-game slot roundtrip: `verify_save_slot_main.gd` (isolated; load_slot can hang in combined smoke).")
	lines.append("- Dict roundtrip: `verify_save_terrain.gd`.")

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
		if _sprite_has_texture(spr) and spr.visible:
			visible += 1
	return {"visible": visible, "total": total}


func _count_vegetation(visuals) -> Dictionary:
	var veg_root: Node3D = visuals.get_vegetation_root() if visuals and visuals.has_method("get_vegetation_root") else null
	var textured := 0
	var total := 0
	if veg_root:
		for child in veg_root.get_children():
			total += 1
			var spr: Sprite3D = child.get_node_or_null("Billboard") as Sprite3D
			if spr and spr.visible and _sprite_has_texture(spr):
				textured += 1
	return {"textured": textured, "total": total}


func _sprite_has_texture(spr: Sprite3D) -> bool:
	if spr == null:
		return false
	var has_tex := spr.texture != null
	if spr.material_override is StandardMaterial3D:
		var mat := spr.material_override as StandardMaterial3D
		has_tex = has_tex or mat.albedo_texture != null
		if has_tex and mat.albedo_color.get_luminance() < 0.05:
			return false
	return has_tex


func _finish(lines: PackedStringArray, failed: bool) -> void:
	var text := "\n".join(lines) + "\n"
	DirAccess.make_dir_recursive_absolute("/tmp/grok-goal-e8916ce4c6d5/implementer")
	var f := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		print(text)
	else:
		push_error("Could not write %s" % SCRATCH_PATH)
		failed = true

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

	_ProbeExit.finish_tree(self, 1 if failed else 0, "SMOKE GAMEPLAY FAILED" if failed else "SMOKE GAMEPLAY OK")