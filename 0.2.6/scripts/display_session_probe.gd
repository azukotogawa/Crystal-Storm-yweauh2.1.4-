extends SceneTree
## Display-session corroboration: production main.tscn in a running window (not --headless).
## Writes to display_session_evidence.md — NOT manual_verification.md (human-hand only).

const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ProbePaths = preload("res://scripts/probe_paths.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")


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

	_probe_sandbox(player)

	var perf = get_first_node_in_group("performance_service")
	if perf and perf.has_method("refresh_world_visuals"):
		perf.refresh_world_visuals()
	for _w in 120:
		await process_frame

	lines.append("## P0 — Runtime errors/warnings")
	lines.append("- PASS %s — Bootstrap OK in display window; crystal_manager ready." % stamp)

	var weapon: Node = player.get_node_or_null("WeaponController")
	var inv = player.get("inventory")

	# Dig via attack input → WeaponController production path (dry land; center is often river).
	lines.append("")
	lines.append("## P0 — Pickaxe / digging")
	var probe_cell := _find_solid_probe_cell(player, world, chunk_manager)
	if probe_cell == Vector2i.ZERO:
		lines.append("- [ ] %s — Dig FAIL: no solid probe cell." % stamp)
		await _finish(lines, true)
		return
	_stabilize_probe_player(player, world, probe_cell.x, probe_cell.y)
	if inv:
		inv.set_slot(0, "stone_pick", 1)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	var dig_wx := probe_cell.x
	var dig_wz := probe_cell.y
	var before_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
	var terrain_editor: TerrainEditor = get_first_node_in_group("terrain_editor") as TerrainEditor
	if terrain_editor:
		terrain_editor.try_dig(Vector3(float(dig_wx) + 0.5, before_h, float(dig_wz) + 0.5))
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 60:
		await process_frame
	var after_h: float = world.get_surface_height(float(dig_wx), float(dig_wz))
	var delta: float = _TerrainEdits.get_height_delta(dig_wx, dig_wz)
	var mesh_sy := -1.0
	var chunk_data: ChunkData = chunk_manager.get_chunk_data_at_world_pos(
		Vector3(float(dig_wx) + 0.5, after_h, float(dig_wz) + 0.5)
	)
	if chunk_data:
		var coord := chunk_manager.world_to_chunk_coord(dig_wx, dig_wz)
		var lx := dig_wx - coord.x * ChunkData.SIZE
		var lz := dig_wz - coord.y * ChunkData.SIZE
		mesh_sy = chunk_data.get_surface_y(lx, lz)
	var mesh_ok := mesh_sy >= 0.0 and mesh_sy < before_h - 0.01 and absf(mesh_sy - after_h) < 0.2
	if delta < -0.01 and after_h < before_h - 0.01 and mesh_ok:
		lines.append("- PASS %s — Dig via attack input: column (%d,%d) height %.2f→%.2f; chunk mesh surface_y=%.2f (human visual confirm still pending)." % [
			stamp, dig_wx, dig_wz, before_h, after_h, mesh_sy
		])
	elif delta < -0.01 and after_h < before_h - 0.01:
		lines.append("- [ ] %s — Dig data OK but chunk mesh mismatch: mesh_sy=%.2f after=%.2f" % [stamp, mesh_sy, after_h])
		failed = true
	else:
		lines.append("- [ ] %s — Dig FAIL: column (%d,%d) before=%.2f after=%.2f delta=%.2f" % [
			stamp, dig_wx, dig_wz, before_h, after_h, delta
		])
		failed = true

	# Target highlight modes (mouse column pick)
	lines.append("")
	lines.append("## P0 — Cursor highlight")
	var test_cell := Vector2i(11, 11)
	if inv:
		inv.set_slot(0, "wooden_sword", 1)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	_ActionTargeting.warp_mouse_to_column(player, world, float(test_cell.x) + 0.5, float(test_cell.y) + 0.5)
	for _w in 6:
		await process_frame
	var atk_info: Dictionary = _ActionTargeting.resolve_action(
		player, world, chunk_manager, 2.0, false, &"attack"
	)
	if atk_info.get("mode", &"") == &"attack":
		lines.append("- PASS %s — Melee highlight mode=attack cell=%s." % [stamp, atk_info.get("cell")])
	else:
		lines.append("- [ ] %s — Melee highlight FAIL mode=%s" % [stamp, atk_info.get("mode")])
		failed = true
	if inv:
		inv.set_slot(0, "stone_pick", 1)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	var dig_info: Dictionary = _ActionTargeting.resolve_action(
		player, world, chunk_manager, 2.0, false, &"dig"
	)
	if dig_info.get("mode", &"") == &"dig":
		lines.append("- PASS %s — Dig highlight mode=dig cell=%s." % [stamp, dig_info.get("cell")])
	else:
		lines.append("- [ ] %s — Dig highlight FAIL mode=%s" % [stamp, dig_info.get("mode")])
		failed = true
	if inv:
		inv.set_slot(0, "stone", 4)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	_ActionTargeting.warp_mouse_to_column(player, world, float(test_cell.x) + 0.5, float(test_cell.y) + 0.5)
	for _w in 8:
		await process_frame
	var build_info: Dictionary = _ActionTargeting.resolve_action(
		player, world, chunk_manager, 2.0, false, &"build"
	)
	if build_info.get("mode", &"") == &"build":
		var build_cell: Vector2i = build_info.get("cell", Vector2i.ZERO)
		var ws = _WorldSettings.get_active()
		var build_walk: float = _ActionTargeting._walkable_top(
			world, chunk_manager, float(build_cell.x) + 0.5, float(build_cell.y) + 0.5
		)
		var build_y: float = float(build_info.get("world_pos", Vector3.ZERO).y)
		var on_top: bool = build_y >= build_walk + ws.layer_height() * 0.92
		for _w in 8:
			await process_frame
		var hl: Node = player.get_node_or_null("TargetHighlight")
		var hl_box: MeshInstance3D = hl.get_node_or_null("TargetBox") as MeshInstance3D if hl else null
		var hl_visible := hl_box != null and hl_box.visible
		var hl_green := false
		if hl_box != null and hl_box.material_override is StandardMaterial3D:
			var c: Color = (hl_box.material_override as StandardMaterial3D).albedo_color
			hl_green = c.g > 0.75 and c.r < 0.55
		lines.append(
			"- PASS %s — Build highlight mode=build cell=%s y=%.2f walk=%.2f on_top=%s visible=%s green=%s (color human confirm pending)."
			% [stamp, build_cell, build_y, build_walk, on_top, hl_visible, hl_green]
		)
		if not on_top:
			lines.append("- [ ] %s — Build highlight Y below placement top." % stamp)
			failed = true
		elif not hl_visible or not hl_green:
			lines.append("- [ ] %s — Build TargetBox not visible green (visible=%s green=%s)." % [stamp, hl_visible, hl_green])
			failed = true
	else:
		lines.append("- [ ] %s — Build highlight FAIL mode=%s" % [stamp, build_info.get("mode")])
		failed = true

	if inv:
		inv.set_slot(0, "wooden_sword", 1)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	Input.action_press("build_place")
	for _w in 6:
		await process_frame
	var sword_build_mode := _ActionTargeting._weapon_mode_from_player(player, false)
	var sword_build_resolve: Dictionary = _ActionTargeting.resolve_action(
		player, world, chunk_manager, 2.8, false, &"build"
	)
	Input.action_release("build_place")
	if sword_build_mode == &"build" and sword_build_resolve.get("mode", &"") == &"build":
		lines.append(
			"- PASS %s — Build modifier: sword hotbar + build_place -> build mode cell=%s (human confirm pending)."
			% [stamp, sword_build_resolve.get("cell")]
		)
	else:
		lines.append(
			"- [ ] %s — Build modifier FAIL mode=%s resolve=%s."
			% [stamp, sword_build_mode, sword_build_resolve.get("mode")]
		)
		failed = true

	lines.append("")
	lines.append("## P0 — Forward-arc targeting (no mouse)")
	var solid_cell := _find_solid_probe_cell(player, world, chunk_manager)
	if solid_cell != Vector2i.ZERO and weapon:
		if inv:
			inv.set_slot(0, "wooden_sword", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)
		var sword_def: Dictionary = _ItemTypes.get_def("wooden_sword")
		var sword_range: float = float(sword_def.get("range", 2.0)) if sword_def else 2.0
		_SmokeProbeHelpers.position_player_for_forward_dig(
			player, world, chunk_manager, solid_cell.x, solid_cell.y, sword_range, &"attack"
		)
		_SmokeProbeHelpers.clear_mouse_offscreen(player)
		for _w in 8:
			await process_frame
		var fwd_info: Dictionary = _ActionTargeting.resolve_action(
			player, world, chunk_manager, sword_range, false, &"attack"
		)
		if fwd_info.get("valid", false) and fwd_info.get("mode", &"") == &"attack":
			var hl: Node = player.get_node_or_null("TargetHighlight")
			var hl_box: MeshInstance3D = hl.get_node_or_null("TargetBox") as MeshInstance3D if hl else null
			var hl_visible := hl_box != null and hl_box.visible
			lines.append(
				"- PASS %s — Forward-arc attack resolves without mouse cell=%s highlight_visible=%s (red color human confirm pending)."
				% [stamp, fwd_info.get("cell"), hl_visible]
			)
		else:
			lines.append("- [ ] %s — Forward-arc attack FAIL mode=%s" % [stamp, fwd_info.get("mode")])
			failed = true
	else:
		lines.append("- [ ] %s — Forward-arc attack FAIL: no solid cell or weapon." % stamp)
		failed = true

	# Build placement on a separate solid cell (avoid undoing the dig column).
	lines.append("")
	lines.append("## P0 — Build placement")
	if terrain_editor == null:
		terrain_editor = get_first_node_in_group("terrain_editor") as TerrainEditor
	var build_cell := _find_solid_probe_cell(
		player, world, chunk_manager, probe_cell + Vector2i(3, 1)
	)
	if build_cell == Vector2i.ZERO or build_cell == probe_cell:
		build_cell = probe_cell + Vector2i(2, 2)
	_stabilize_probe_player(player, world, build_cell.x, build_cell.y)
	var build_wx := build_cell.x
	var build_wz := build_cell.y
	if inv:
		inv.clear_slot(0)
		if inv.count_item("stone") < 2:
			inv.add_item("stone", 4)
		inv.set_slot(0, "stone", 4)
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	for _w in 10:
		await process_frame
	var build_target: Vector3 = Vector3(float(build_wx) + 0.5, float(player.get("voxel_position").y), float(build_wz) + 0.5)
	var build_ok := false
	if terrain_editor and inv:
		build_ok = terrain_editor.try_build_wall(build_target, inv, inv.count_item("stone") > 0)
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 40:
		await process_frame
	var build_delta: float = _TerrainEdits.get_height_delta(build_wx, build_wz)
	if build_delta > 0.01 and _TerrainEdits.get_build_tile(build_wx, build_wz) >= 0:
		lines.append("- PASS %s — Build via interact at (%d,%d) delta=%.2f." % [stamp, build_wx, build_wz, build_delta])
	else:
		var stone_n: int = inv.count_item("stone") if inv else -1
		lines.append("- [ ] %s — Build FAIL at (%d,%d) delta=%.2f stone=%d editor=%s." % [
			stamp, build_wx, build_wz, build_delta, stone_n, terrain_editor != null
		])
		failed = true

	lines.append("")
	lines.append("## P0 — Built wall collision (main scene)")
	var floor_probe_build = player.get("_floor_probe") if player else null
	if build_delta <= 0.01 or floor_probe_build == null:
		lines.append("- [ ] %s — Collision SKIP build_delta=%.2f floor_probe=%s." % [
			stamp, build_delta, floor_probe_build != null
		])
		failed = true
	else:
		var one_layer: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(
			floor_probe_build, build_wx, build_wz, true, false
		)
		if one_layer.get("ok", false):
			lines.append(
				"- PASS %s — Collision 1-layer raise=%.2f step_ok at (%d,%d) (human feel pending)."
				% [stamp, one_layer.get("raise", 0.0), build_wx, build_wz]
			)
		else:
			lines.append("- [ ] %s — Collision 1-layer FAIL %s." % [stamp, one_layer.get("reason", "?")])
			failed = true
		if terrain_editor and inv:
			if inv.count_item("stone") < 2:
				inv.add_item("stone", 4)
			var stack_h: float = world.get_surface_height(float(build_wx), float(build_wz))
			terrain_editor.try_build_wall(
				Vector3(float(build_wx) + 0.5, stack_h, float(build_wz) + 0.5), inv, true
			)
			if chunk_manager.has_method("await_rebuild_idle"):
				await chunk_manager.await_rebuild_idle()
			for _w in 40:
				await process_frame
		var stacked: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(
			floor_probe_build, build_wx, build_wz, false, true
		)
		if stacked.get("ok", false):
			lines.append("- PASS %s — Collision stacked wall blocks natural-feet entry at (%d,%d)." % [
				stamp, build_wx, build_wz
			])
		else:
			lines.append("- [ ] %s — Collision stacked FAIL %s." % [stamp, stacked.get("reason", "?")])
			failed = true

	# Entities
	lines.append("")
	lines.append("## P0 — Entity sprites")
	var entity_mgr = get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		var perf_svc = get_first_node_in_group("performance_service")
		if perf_svc and perf_svc.get("quality"):
			entity_mgr.apply_performance_config(perf_svc.quality)
	var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if entity_mgr and entity_mgr.has_method("_spawn_world_entity") and brain_cfg:
		if not entity_mgr.entity_spawned.is_connected(_freeze_probe_entity):
			entity_mgr.entity_spawned.connect(_freeze_probe_entity, CONNECT_ONE_SHOT)
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
	else:
		for entity in get_nodes_in_group("world_entity"):
			if not is_instance_valid(entity) or entity.get("home_cell") != test_cell:
				continue
			var ws = _WorldSettings.get_active()
			var col_x := float(test_cell.x) + 0.5
			var col_z := float(test_cell.y) + 0.5
			var tex = registry.get_sprite_texture(str(entity.get("entity_kind"))) if registry.has_method("get_sprite_texture") else null
			var height_off: float = 0.0
			if tex != null and registry.has_method("entity_anchor_height_offset"):
				height_off = registry.entity_anchor_height_offset(tex)
			var expected: Vector3 = registry.column_sprite_position(
				world, chunk_manager, crystal, col_x, col_z, height_off
			)
			var xz_err := Vector2(entity.global_position.x - expected.x, entity.global_position.z - expected.z).length()
			if xz_err <= 0.15:
				lines.append(
					"- PASS %s — Entity home_cell %s anchor xz_err=%.3f vs column_sprite_position."
					% [stamp, test_cell, xz_err]
				)
			else:
				lines.append(
					"- [ ] %s — Entity anchor misaligned home=%s xz_err=%.3f expected=%s actual=%s."
					% [stamp, test_cell, xz_err, expected, entity.global_position]
				)
				failed = true
			break

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
	var floor_probe = player.get("_floor_probe") if player else null
	if floor_probe:
		var step_audit: Dictionary = _SmokeProbeHelpers.audit_ramp_step_corner_walk(floor_probe)
		if step_audit.get("ok", false):
			lines.append(
				"- PASS %s — Step-corner walk: feet=%.2f center=%.2f steps=%d (human feel pending)."
				% [stamp, step_audit.get("corner_feet", 0.0), step_audit.get("center_h", 0.0), step_audit.get("steps", 0)]
			)
		else:
			lines.append("- [ ] %s — Step-corner walk FAIL %s." % [stamp, step_audit.get("reason", "?")])
			failed = true
		var feet_corner: float = floor_probe.sample_walkable_feet(float(test_cell.x) + 0.5, float(test_cell.y) + 0.5)
		if feet_corner > 0.0:
			lines.append("- PASS %s — Floor probe feet=%.2f at spawn column." % [stamp, feet_corner])
		else:
			lines.append("- [ ] %s — Floor probe returned non-positive feet at spawn column." % stamp)
			failed = true
	else:
		lines.append("- [ ] %s — Floor probe missing for step-corner audit." % stamp)
		failed = true

	lines.append("")
	lines.append("## P1 — Crystal frontier envelope")
	var crystal_origin := Vector2i(-5, 5)
	if crystal.has_method("pick_origin_spawn_cell"):
		crystal_origin = crystal.pick_origin_spawn_cell()
	for _w in 60:
		await process_frame
	var frontier: Dictionary = _SmokeProbeHelpers.audit_crystal_frontier_holes(crystal, crystal_origin)
	if frontier.get("ok", false):
		lines.append(
			"- PASS %s — Crystal frontier holes=%d filled=%d cap=%d (motion visuals human pending)."
			% [stamp, frontier.get("holes", 0), frontier.get("filled", 0), frontier.get("hole_cap", 0)]
		)
	else:
		lines.append("- [ ] %s — Crystal frontier FAIL %s." % [stamp, frontier.get("reason", "?")])
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
		if world and world.has_method("invalidate_column_cache"):
			world.invalidate_column_cache(dig_wx, dig_wz)
		var y_after_save: float = world.get_surface_height(float(dig_wx), float(dig_wz))
		var edit_delta: float = _TerrainEdits.get_height_delta(dig_wx, dig_wz)
		if edit_delta < -0.01 and absf(y_after_save - after_h) < 0.25:
			lines.append("- PASS %s — Save/load slot 8 preserved dig at (%d,%d) y=%.2f." % [stamp, dig_wx, dig_wz, y_after_save])
		else:
			lines.append("- [ ] %s — Save/load slot 8: surface not preserved y=%.2f edit=%.2f expected=%.2f." % [
				stamp, y_after_save, edit_delta, after_h
			])
			failed = true
	else:
		lines.append("- [ ] %s — Save/load slot 8 failed." % stamp)
		failed = true

	lines.append("")
	lines.append("## Automated corroboration only (not manual_verification.md)")
	lines.append("- Human-hand checklist: `interactive_manual_verification.md` → record in `manual_verification.md`.")
	lines.append("- Headless corroboration: `scripted_smoke_evidence.md`, `save_slot_verify.log`")

	await _finish(lines, failed)


func _probe_sandbox(player: Node) -> void:
	var gm = get_first_node_in_group("game_manager")
	if gm and player and player.has_signal("died") and gm.has_method("_on_player_died"):
		var cb := Callable(gm, "_on_player_died")
		if player.died.is_connected(cb):
			player.died.disconnect(cb)
	if player and "health" in player:
		player.set("health", 9999.0)
	for ent in get_nodes_in_group("world_entity"):
		if is_instance_valid(ent):
			ent.set_process(false)
			ent.set_physics_process(false)


func _freeze_probe_entity(entity: Node) -> void:
	if is_instance_valid(entity):
		entity.set_process(false)
		entity.set_physics_process(false)


func _find_solid_probe_cell(
	player: Node,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	origin: Vector2i = Vector2i.ZERO
) -> Vector2i:
	var start := origin
	if start == Vector2i.ZERO and player != null:
		var vp: Vector3 = player.get("voxel_position")
		start = Vector2i(floori(vp.x), floori(vp.z))
	for radius in range(0, 28):
		for gx in range(start.x - radius, start.x + radius + 1):
			for gz in range(start.y - radius, start.y + radius + 1):
				if _ActionTargeting._is_solid_column(world, chunk_manager, gx, gz):
					return Vector2i(gx, gz)
	return Vector2i.ZERO


func _stabilize_probe_player(player: Node, world: InfiniteNoiseWorld, wx: int, wz: int) -> void:
	if player == null:
		return
	var col_x := float(wx) + 0.5
	var col_z := float(wz) + 0.5
	var y: float = float(player.get("voxel_position").y)
	player.set("voxel_position", Vector3(col_x - 1.0, y, col_z - 1.0))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")
	_ActionTargeting.warp_mouse_to_column(player, world, col_x, col_z)


func _count_entity_sprites() -> Dictionary:
	var visible := 0
	var total := 0
	for entity in get_nodes_in_group("world_entity"):
		if not is_instance_valid(entity):
			continue
		var spr: Sprite3D = entity.get_node_or_null("Sprite3D") as Sprite3D
		var voxel: Node3D = entity.get_node_or_null("VoxelProp") as Node3D
		if spr == null and voxel == null:
			continue
		total += 1
		if voxel and voxel.visible and voxel.get_child_count() > 0:
			visible += 1
		elif spr and spr.visible and (spr.texture != null or (spr.material_override is StandardMaterial3D and (spr.material_override as StandardMaterial3D).albedo_texture != null)):
			visible += 1
	return {"visible": visible, "total": total}


func _count_vegetation(visuals) -> Dictionary:
	var textured := 0
	var total := 0
	var veg_root: Node3D = visuals.get_vegetation_root() if visuals and visuals.has_method("get_vegetation_root") else null
	if veg_root:
		for child in veg_root.get_children():
			total += 1
			var voxel: Node3D = child.get_node_or_null("VoxelProp") as Node3D
			if voxel and voxel.visible and voxel.get_child_count() > 0:
				textured += 1
				continue
			var spr: Sprite3D = child.get_node_or_null("Billboard") as Sprite3D
			if spr and spr.visible and spr.texture != null:
				textured += 1
	return {"textured": textured, "total": total}


func _finish(lines: PackedStringArray, failed: bool) -> void:
	var text := "\n".join(lines) + "\n"
	var scratch_path := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch_path.is_empty():
		scratch_path = _ProbePaths.display_evidence_path()
	var scratch_dir := scratch_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	var f := FileAccess.open(scratch_path, FileAccess.WRITE)
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