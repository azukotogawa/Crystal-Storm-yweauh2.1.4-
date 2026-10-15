extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbePaths = preload("res://scripts/probe_paths.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _Capture = preload("res://helpers/probe_capture.gd")

const _NAMED_SHOTS := {
	"Bootstrap OK": ["boot"],
	"Dig OK": ["dig", "dig-mesh"],
	"Dig FAIL": ["dig", "dig-mesh"],
	"Entities OK": ["entities"],
	"Entities FAIL": ["entities"],
	"Combat OK": ["combat"],
	"Combat FAIL": ["combat"],
	"Combat VFX OK": ["combat-vfx"],
	"Combat VFX FAIL": ["combat-vfx"],
	"Vegetation OK": ["vegetation"],
	"Vegetation FAIL": ["vegetation"],
	"Streaming OK": ["streaming"],
	"Streaming FAIL": ["streaming"],
	"Jump OK": ["jump"],
	"Jump FAIL": ["jump"],
	"Ramp OK": ["ramp"],
	"Ramp FAIL": ["ramp"],
	"Crystal edge OK": ["crystal-edge"],
	"Crystal edge FAIL": ["crystal-edge"],
	"Session OK": ["session"],
	"Session FAIL": ["session"],
}


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _force_fail_mode() -> String:
	return OS.get_environment("SMOKE_FORCE_FAIL").strip_edges().to_lower()


func _note(lines: PackedStringArray, line: String) -> void:
	lines.append(line)
	var key := _step_key(line)
	if not _NAMED_SHOTS.has(key):
		return
	for step_name in _NAMED_SHOTS[key]:
		await _Capture.capture_step(str(step_name))


func _step_key(line: String) -> String:
	if line.begins_with("- Bootstrap OK"):
		return "Bootstrap OK"
	var open := line.find("**")
	if open < 0:
		return ""
	var close := line.find("**", open + 2)
	if close < 0:
		return ""
	return line.substr(open + 2, close - open - 2)


func _run() -> void:
	var failed := false
	var lines: PackedStringArray = []
	var stamp := Time.get_datetime_string_from_system()
	var session_sec := _SmokeProbeHelpers.session_seconds()
	lines.append("# Gameplay verification log")
	lines.append("")
	lines.append("**Method:** Headless scripted smoke (`smoke_gameplay.gd`) — NOT interactive manual QA.")
	lines.append("Exercises WeaponController._do_dig_attack, EntityManager._spawn_world_entity, combat VFX, chunk mesh audit.")
	lines.append("For **Working** status see `manual_verification.md` (human-hand session required).")
	lines.append("")
	lines.append("Preset: MEDIUM | Session: %.0fs | Captured: %s" % [session_sec, stamp])
	lines.append("")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		lines.append("## Bootstrap FAIL — could not load main scene")
		await _Capture.capture_step("boot")
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
		await _Capture.capture_step("boot")
		await _finish(lines, true)
		return

	var perf = get_first_node_in_group("performance_service")
	if perf and perf.has_method("refresh_world_visuals"):
		perf.refresh_world_visuals()
	for _w in 120:
		await process_frame

	lines.append("## P0 — Runtime")
	await _note(lines, "- Bootstrap OK: player, chunk_manager, terrain_editor, crystal_manager ready.")

	if _force_fail_mode() == "1":
		lines.append("")
		lines.append("## P0 — Forced fail (quit-path harness)")
		await _note(lines, "- **Dig FAIL**: SMOKE_FORCE_FAIL=1")
		await _finish(lines, true)
		return

	lines.append("")
	lines.append("## P0 — Pickaxe / digging (WeaponController)")
	var weapon: Node = player.get_node_or_null("WeaponController")
	var pick_def: Dictionary = _ItemTypes.get_def("stone_pick")
	var dug := false
	var dig_wx := -1
	var dig_wz := -1
	var range_v: float = _ActionTargeting.INTERACTION_RANGE
	var aimed := Vector3.ZERO
	if weapon != null and not pick_def.is_empty() and weapon.has_method("_do_dig_attack") and weapon.has_method("_resolve_terrain_target"):
		aimed = await _aim_dry_dig_column(player, world, chunk_manager, terrain, crystal, weapon, range_v)
	if weapon == null or pick_def.is_empty() or not weapon.has_method("_do_dig_attack"):
		await _note(lines, "- **Dig FAIL**: WeaponController missing dig API")
		failed = true
	elif aimed == Vector3.ZERO:
		await _note(lines, "- **Dig FAIL**: no dry column in interaction range (river and water-adjacent cells are not height edits)")
		failed = true
	else:
		dig_wx = floori(aimed.x)
		dig_wz = floori(aimed.z)
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
		dug = delta < -0.01 and after_h < before_h - 0.01 and mesh_ok
		if dug:
			await _note(lines,
				"- **Dig OK**: WeaponController column (%d,%d) %.2f→%.2f delta=%.2f; chunk mesh surface_y=%.2f corroborates visible terrain edit."
				% [dig_wx, dig_wz, before_h, after_h, delta, mesh_sy]
			)
		elif delta < -0.01 and after_h < before_h - 0.01:
			await _note(lines,
				"- **Dig FAIL**: data lowered but chunk mesh mismatch mesh_sy=%.2f after=%.2f at (%d,%d)."
				% [mesh_sy, after_h, dig_wx, dig_wz]
			)
			failed = true
		else:
			await _note(lines, "- **Dig FAIL**: target_col=(%d,%d) before=%.2f after=%.2f delta=%.2f mesh_sy=%.2f" % [
				dig_wx, dig_wz, before_h, after_h, delta, mesh_sy
			])
			failed = true

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
		sprite_stats = _SmokeProbeHelpers.count_entity_sprites(self)
		if sprite_stats.visible >= 1:
			break
	if sprite_stats.visible >= 1:
		await _note(lines, "- **Entities OK**: %d/%d textured billboard sprites (EntityManager spawn at %s)." % [
			sprite_stats.visible, sprite_stats.total, test_cell
		])
	else:
		await _note(lines, "- **Entities FAIL**: %d/%d textured sprites after EntityManager spawn." % [
			sprite_stats.visible, sprite_stats.total
		])
		failed = true

	lines.append("")
	lines.append("## P0 — Melee entity damage")
	var melee_entity_ok := false
	var spawned_entity: Node = null
	var best_d := INF
	var ws_melee = preload("res://config/world_settings.gd").get_active()
	for entity in get_nodes_in_group("world_entity"):
		if not is_instance_valid(entity) or not entity.has_method("take_damage"):
			continue
		var pos: Vector3 = entity.global_position if "global_position" in entity else Vector3.ZERO
		var ecx: float = ws_melee.world_to_column(pos.x)
		var ecz: float = ws_melee.world_to_column(pos.z)
		var d: float = Vector2(ecx, ecz).distance_to(Vector2(float(test_cell.x) + 0.5, float(test_cell.y) + 0.5))
		if d < best_d:
			best_d = d
			spawned_entity = entity
	if spawned_entity and weapon and weapon.has_method("_do_melee_attack") and best_d < 2.5:
		var hp_before: float = float(spawned_entity.get("health"))
		player.set("voxel_position", Vector3(float(test_cell.x) + 0.5, player.get("voxel_position").y, float(test_cell.y) + 0.5))
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		var inv_melee = player.get("inventory")
		if inv_melee:
			inv_melee.set_slot(0, "wooden_sword", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)
		var sword_def: Dictionary = _ItemTypes.get_def("wooden_sword")
		weapon.call("_do_melee_attack", "wooden_sword", sword_def)
		for _w in 12:
			await process_frame
		var hp_after: float = float(spawned_entity.get("health"))
		melee_entity_ok = hp_after < hp_before - 0.01
	if melee_entity_ok:
		await _note(lines, "- **Combat OK**: melee damaged spawned world_entity (HP reduced).")
	else:
		await _note(lines, "- **Combat FAIL**: melee did not reduce spawned entity health.")
		failed = true

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
	var veg_stats := _SmokeProbeHelpers.count_vegetation(visuals)
	if veg_stats.textured >= 1:
		await _note(lines, "- **Vegetation OK**: %d/%d billboards textured (material-bound, not gray placeholder)." % [
			veg_stats.textured, veg_stats.total
		])
	else:
		await _note(lines, "- **Vegetation FAIL**: %d billboards, %d textured." % [veg_stats.total, veg_stats.textured])
		failed = true

	lines.append("")
	lines.append("## P0 — Chunk streaming")
	var chunks_before: int = chunk_manager.chunks.size()
	var start_col: Vector3 = player.get("voxel_position")
	var inward := Vector3(
		-48.0 if start_col.x >= 0.0 else 48.0,
		0.0,
		-48.0 if start_col.z >= 0.0 else 48.0
	)
	player.set("voxel_position", start_col + inward)
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	for _w in 240:
		await process_frame
	var chunks_after: int = chunk_manager.chunks.size()
	var stream_audit := _SmokeProbeHelpers.audit_loaded_chunks(chunk_manager)
	if chunks_after >= chunks_before and stream_audit.ok:
		await _note(lines,
			"- **Streaming OK**: chunks %d→%d after inward column move; %d loaded views with mesh instances, no holes."
			% [chunks_before, chunks_after, stream_audit.total]
		)
	else:
		await _note(lines,
			"- **Streaming FAIL**: chunks %d→%d invalid=%d empty_mesh=%d missing_surface=%d"
			% [
				chunks_before, chunks_after,
				stream_audit.invalid_views, stream_audit.empty_mesh, stream_audit.missing_surface
			]
		)
		failed = true

	lines.append("")
	lines.append("## P1 — Jump while moving")
	var probe = player.get("_floor_probe")
	var jump_pos: Vector3 = player.get("voxel_position")
	if absf(jump_pos.x) > 900.0:
		jump_pos.x -= 80.0 * signf(jump_pos.x)
	if absf(jump_pos.z) > 900.0:
		jump_pos.z -= 80.0 * signf(jump_pos.z)
	player.set("voxel_position", jump_pos)
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	if chunk_manager.has_method("update_stream"):
		chunk_manager.update_stream(
			floori(jump_pos.x / 16.0),
			floori(jump_pos.z / 16.0)
		)
	for _w in 40:
		await process_frame
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
		await _note(lines, "- **Jump OK**: jump input + ui_right; air state seen, landed grounded, moved %.2f cols." % [
			float(player.get("voxel_position").x) - start_x
		])
	else:
		await _note(lines, "- **Jump FAIL**: jump input air=%s landed=%s moved=%s." % [air_seen, landed, moved])
		failed = true

	lines.append("")
	lines.append("## P0 — Combat VFX")
	var combat_vfx = get_first_node_in_group("combat_visual_feedback")
	var vfx_ok := false
	if combat_vfx and combat_vfx.has_method("show_damage_column"):
		var col_pos: Vector3 = player.get("voxel_position")
		combat_vfx.show_damage_column(col_pos, 9.0, Color(1.0, 0.55, 0.45))
		for _w in 8:
			await process_frame
		var direct_vfx := _SmokeProbeHelpers.combat_vfx_active(combat_vfx)
		if direct_vfx.ok:
			vfx_ok = true
			await _note(lines,
				"- **Combat VFX OK**: damage label visible (%d labels, %d burst sprites after show_damage_column)."
				% [direct_vfx.damage_labels, direct_vfx.burst_sprites]
			)
	if not vfx_ok and weapon and weapon.has_method("_do_melee_attack"):
		var inv2 = player.get("inventory")
		if inv2:
			inv2.set_slot(0, "wooden_sword", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)
		player.set("voxel_position", Vector3(float(test_cell.x) + 0.5, player.get("voxel_position").y, float(test_cell.y) + 0.5))
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		var sword_def: Dictionary = _ItemTypes.get_def("wooden_sword")
		weapon.call("_do_melee_attack", "wooden_sword", sword_def)
		for _w in 20:
			await process_frame
		var hit_vfx := _SmokeProbeHelpers.combat_vfx_active(combat_vfx)
		if hit_vfx.ok:
			vfx_ok = true
			await _note(lines,
				"- **Combat VFX OK**: melee entity_hit produced VFX (%d labels, %d burst sprites)."
				% [hit_vfx.damage_labels, hit_vfx.burst_sprites]
			)
	if not vfx_ok:
		await _note(lines, "- **Combat VFX FAIL**: no visible damage labels or burst sprites after hit.")
		failed = true

	lines.append("")
	lines.append("## P1 — Ramp collision / terrain transitions")
	var concave_h := _TerrainRamps.walkable_height_from_entry(
		world, 4.5, 6.5,
		{"concave": true, "surface_h": 12.0, "dir": Vector2i(1, 0), "dir2": Vector2i(0, 1)}
	)
	var layer_h: float = _WorldSettings.get_active().layer_height()
	if concave_h >= 12.0 + layer_h * 0.5:
		await _note(lines, "- **Ramp OK**: concave walkable=%.2f above carved floor (probe math)." % concave_h)
	else:
		await _note(lines, "- **Ramp FAIL**: concave walkable too low %.2f" % concave_h)
		failed = true
	if probe != null and probe.has_method("sample_walkable_feet"):
		var feet: float = probe.sample_walkable_feet(float(test_cell.x) + 0.5, float(test_cell.y) + 0.5)
		if feet > 0.0:
			await _note(lines, "- **Ramp OK**: floor probe feet=%.2f at entity spawn column." % feet)
		else:
			await _note(lines, "- **Ramp FAIL**: floor probe returned non-positive feet height.")
			failed = true

	lines.append("")
	lines.append("## P1 — Crystal loaded/unloaded chunks")
	var far_cell := Vector2i(512, 512)
	var depth_far: float = crystal.get_depth_at(far_cell.x, far_cell.y) if crystal else 0.0
	var loaded_far: bool = chunk_manager.is_world_cell_loaded(far_cell.x, far_cell.y) if chunk_manager.has_method("is_world_cell_loaded") else false
	if not loaded_far and depth_far <= 0.01:
		await _note(lines, "- **Crystal edge OK**: far cell (%d,%d) unloaded, depth=%.2f." % [far_cell.x, far_cell.y, depth_far])
	else:
		await _note(lines, "- **Crystal edge FAIL**: far loaded=%s depth=%.2f (expected unloaded+zero)." % [loaded_far, depth_far])
		failed = true
	var cells_before: int = crystal.covered_cells if "covered_cells" in crystal else 0
	for _w in 30:
		await process_frame
	var cells_after: int = crystal.covered_cells if "covered_cells" in crystal else 0
	if cells_after >= cells_before:
		await _note(lines, "- **Crystal edge OK**: sim tick stable cells %d→%d near player bubble." % [cells_before, cells_after])
	else:
		await _note(lines, "- **Crystal edge FAIL**: cell count dropped unexpectedly.")
		failed = true

	lines.append("")
	lines.append("## P0 — Sustained session (MEDIUM preset)")
	var session_start_ms := Time.get_ticks_msec()
	var session_end_ms := session_start_ms + int(session_sec * 1000.0)
	var session_frames := 0
	var session_digs := 0
	var session_jumps := 0
	var session_attacks := 0
	var session_entities_peak: int = sprite_stats.visible
	var move_dirs: Array[String] = ["ui_right", "ui_up", "ui_left", "ui_down"]
	var dir_idx := 0
	var session_inv = player.get("inventory")
	if session_inv:
		session_inv.set_slot(1, "stone_pick", 1)
		session_inv.set_slot(0, "wooden_sword", 1)
	while Time.get_ticks_msec() < session_end_ms:
		await process_frame
		session_frames += 1
		var phase := session_frames % 180
		var move_action := move_dirs[dir_idx % move_dirs.size()]
		if phase < 90:
			Input.action_press(move_action)
		else:
			Input.action_release(move_action)
			if phase == 90:
				dir_idx += 1
		if phase == 30 and weapon and weapon.has_method("_do_dig_attack"):
			if weapon.has_method("set_active_hotbar_index"):
				weapon.set_active_hotbar_index(1)
			var pick: Dictionary = _ItemTypes.get_def("stone_pick")
			weapon.call("_do_dig_attack", "stone_pick", pick)
			session_digs += 1
		if phase == 60:
			Input.action_press("jump")
		if phase == 62:
			Input.action_release("jump")
			session_jumps += 1
		if phase == 120 and weapon and weapon.has_method("_do_melee_attack"):
			if weapon.has_method("set_active_hotbar_index"):
				weapon.set_active_hotbar_index(0)
			var sword: Dictionary = _ItemTypes.get_def("wooden_sword")
			weapon.call("_do_melee_attack", "wooden_sword", sword)
			session_attacks += 1
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		var ent_now := _SmokeProbeHelpers.count_entity_sprites(self)
		session_entities_peak = maxi(session_entities_peak, ent_now.textured)
	for action in move_dirs + ["jump"]:
		Input.action_release(action)
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 60:
		await process_frame
	var elapsed_sec := (Time.get_ticks_msec() - session_start_ms) / 1000.0
	var post_audit := _SmokeProbeHelpers.audit_loaded_chunks(chunk_manager)
	var post_veg := _SmokeProbeHelpers.count_vegetation(visuals)
	var session_ok: bool = (
		elapsed_sec >= session_sec - 0.5
		and post_audit.ok
		and session_entities_peak >= 1
		and post_veg.textured >= 1
	)
	if session_ok:
		await _note(lines,
			"- **Session OK**: %.1fs / %.0fs target, %d frames, digs=%d jumps=%d attacks=%d; post-audit chunks=%d entities_peak=%d vegetation=%d."
			% [
				elapsed_sec, session_sec, session_frames, session_digs, session_jumps, session_attacks,
				post_audit.total, session_entities_peak, post_veg.textured
			]
		)
	else:
		await _note(lines,
			"- **Session FAIL**: elapsed=%.1fs target=%.0fs frames=%d audit_ok=%s entities_peak=%d veg=%d invalid=%d empty=%d."
			% [
				elapsed_sec, session_sec, session_frames, post_audit.ok,
				session_entities_peak, post_veg.textured,
				post_audit.invalid_views, post_audit.empty_mesh
			]
		)
		failed = true

	lines.append("")
	lines.append("## P1 — Save/load terrain edits")
	lines.append("- In-game slot roundtrip: `verify_save_slot_main.gd` (isolated; load_slot can hang in combined smoke).")
	lines.append("- Dict roundtrip: `verify_save_terrain.gd`.")

	await _finish(lines, failed)


func _aim_dry_dig_column(
	player: Node,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	terrain: TerrainEditor,
	crystal: CrystalManager,
	weapon: Node,
	range_v: float
) -> Vector3:
	var start := Vector2i(2, 4)
	if player != null and player.get("voxel_position") is Vector3:
		var vp: Vector3 = player.get("voxel_position")
		start = Vector2i(floori(vp.x), floori(vp.z))
	var tried := 0
	for radius in range(0, 18):
		for gx in range(start.x - radius, start.x + radius + 1):
			for gz in range(start.y - radius, start.y + radius + 1):
				if radius > 0 and absi(gx - start.x) != radius and absi(gz - start.y) != radius:
					continue
				if not _is_height_dig_column(world, chunk_manager, terrain, crystal, gx, gz):
					continue
				tried += 1
				_SmokeProbeHelpers.position_player_for_forward_dig(
					player, world, chunk_manager, gx, gz, range_v, &"dig"
				)
				_SmokeProbeHelpers.clear_mouse_offscreen(player)
				for _w in 8:
					await process_frame
				var resolved: Vector3 = weapon.call("_resolve_terrain_target", range_v)
				var rx := floori(resolved.x)
				var rz := floori(resolved.z)
				if resolved != Vector3.ZERO and _is_height_dig_column(world, chunk_manager, terrain, crystal, rx, rz):
					return resolved
				if tried >= 12:
					return Vector3.ZERO
	return Vector3.ZERO


func _is_height_dig_column(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	terrain: TerrainEditor,
	crystal: CrystalManager,
	wx: int,
	wz: int
) -> bool:
	if not _ActionTargeting._can_dig_column(world, chunk_manager, wx, wz):
		return false
	if terrain != null and terrain.has_method("_has_adjacent_water") and terrain._has_adjacent_water(wx, wz):
		return false
	if crystal != null and crystal.has_method("get_depth_at") and float(crystal.get_depth_at(wx, wz)) >= 0.04:
		return false
	return true


func _finish(lines: PackedStringArray, failed: bool) -> void:
	var text := "\n".join(lines) + "\n"
	var scratch_path := _ProbePaths.smoke_evidence_path()
	DirAccess.make_dir_recursive_absolute(scratch_path.get_base_dir())
	var f := FileAccess.open(scratch_path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		print(text)
	else:
		push_error("Could not write %s" % scratch_path)
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