extends SceneTree
## Live production-scene audit. Discovers logical vs rendered disagreements.
## Does not pass by hardcoded expected cell values.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldState = preload("res://world/world_state.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")


var _scratch: String = ""
var _windowed: bool = false
var _game: Node = null
var _findings: Array = []
var _actions: Array = []
var _snaps: Dictionary = {}
var _f3_text: String = ""
var _f3_pause: String = ""
var _shots: PackedStringArray = PackedStringArray()
var _failed: int = 0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _note(kind: String, msg: String, extra: Dictionary = {}) -> void:
	var row := {"kind": kind, "msg": msg}
	for k in extra.keys():
		row[k] = extra[k]
	_findings.append(row)
	print("%s %s" % [kind.to_upper(), msg])


func _fail(msg: String) -> void:
	_failed += 1
	_note("fail", msg)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961aca94c53e/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	_windowed = DisplayServer.get_name() != "headless"
	print("AUTONOMOUS_AUDIT_START windowed=%s" % str(_windowed))
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	_game = packed.instantiate()
	root.add_child(_game)
	var compose = _game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 40:
		await process_frame
		if not _GameplayInput.world_loading:
			break
	for _s in 10:
		await process_frame

	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var editor = get_first_node_in_group("terrain_editor")
	var player = get_first_node_in_group("player")
	var insp = _game.get_node_or_null("LiveWorldInspector")
	if insp == null:
		insp = get_first_node_in_group("live_world_inspector")
	if cm == null or world == null or editor == null or player == null:
		_fail("missing world/cm/editor/player")
		_finish()
		return
	if insp:
		insp.panel_open = true
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	if feat_layer and feat_layer.has_method("_bind_terrain_placement_refresh"):
		feat_layer._bind_terrain_placement_refresh()
	if "inventory" in player and player.inventory:
		player.inventory.add_item("stone", 96)
		player.inventory.add_item("wood", 96)
	var inv = player.inventory

	_f3_text = _dump_f3()
	_record_world_vitals(cm, world, compose)

	var origin := _find_dry_origin(world, cm)
	_look_at(origin.x, origin.y)
	await _idle(cm)
	var veg_wait := 0
	while veg_wait < 48:
		if feat_layer == null or not ("_pending_populate" in feat_layer):
			break
		if (feat_layer._pending_populate as Array).is_empty():
			break
		await process_frame
		veg_wait += 1
	_observe_hud_and_vegetation(origin)
	await _shot("audit_spawn")

	# Camera continuous yaw — inspect one cell at several headings.
	var cam = get_first_node_in_group("camera")
	var yaw_cell := origin + Vector2i(2, 2)
	for yaw in [45.0, 90.0, 180.0, 270.0, 12.0, 333.0]:
		if cam and cam.has_method("snap_yaw_degrees"):
			cam.snap_yaw_degrees(float(yaw))
		_look_at(yaw_cell.x, yaw_cell.y)
		if insp:
			insp.pin_cell = yaw_cell
		for _y in 4:
			await process_frame
		var ys: Dictionary = _LiveWorldQuery.inspect_cell(self, yaw_cell.x, yaw_cell.y)
		_classify("camera_yaw_%.0f" % yaw, yaw_cell, ys)
	if cam and cam.has_method("snap_yaw_degrees"):
		cam.snap_yaw_degrees(45.0)

	# Walk a few columns.
	for step in range(6):
		_look_at(origin.x + step, origin.y)
		await process_frame
	_actions.append("walk_6_columns")
	await _shot("audit_walk")

	# Dig / adjacent / under-structure / builds.
	var cells := {
		"dig": origin + Vector2i(3, 3),
		"adj": origin + Vector2i(4, 3),
		"wall": origin + Vector2i(6, 3),
		"under": origin + Vector2i(6, 3),
		"gate": origin + Vector2i(8, 3),
		"bridge": origin + Vector2i(10, 3),
		"rebuild": origin + Vector2i(8, 3),
	}
	await _do_dig(editor, cm, insp, "dig", cells.dig)
	await _do_dig(editor, cm, insp, "dig_adj", cells.adj)
	await _do_build(editor, cm, insp, inv, "wall", cells.wall, &"stone_wall")
	await _do_dig(editor, cm, insp, "dig_under_wall", cells.under)
	await _do_build(editor, cm, insp, inv, "gate", cells.gate, &"gate")
	await _do_dig(editor, cm, insp, "bridge_trench", cells.bridge)
	await _do_build(editor, cm, insp, inv, "bridge", cells.bridge, &"bridge")
	await _shot("audit_builds")

	# Remove/rebuild gate via overlay clear (no dedicated demolish verb).
	await _do_remove(editor, cm, feat_layer, insp, "gate_remove", cells.gate)
	await _do_build(editor, cm, insp, inv, "gate_rebuild", cells.rebuild, &"gate")

	# Generated ramps (existing helper, not a new mechanic).
	var ramp_cells: Dictionary = {
		"ramp_east": origin + Vector2i(12, 2),
		"ramp_west": origin + Vector2i(15, 2),
		"ramp_south": origin + Vector2i(18, 2),
		"ramp_north": origin + Vector2i(21, 2),
	}
	_ValidationYard.apply_generated_ramps(self, ramp_cells)
	await _idle(cm)
	for rk in ramp_cells.keys():
		var rc: Vector2i = ramp_cells[rk]
		_look_at(rc.x, rc.y)
		if insp:
			insp.pin_cell = rc
		for _r in 3:
			await process_frame
		_classify(str(rk), rc, _LiveWorldQuery.inspect_cell(self, rc.x, rc.y))
	await _shot("audit_ramps")

	# Water: player channel if possible, plus nearby natural river/ocean sample.
	var water_cell := origin + Vector2i(3, 6)
	if editor.has_method("try_channel_water"):
		var wy: float = world.get_surface_height(float(water_cell.x), float(water_cell.y))
		var wok: bool = editor.try_channel_water(
			Vector3(float(water_cell.x) + 0.5, wy, float(water_cell.y) + 0.5), inv
		)
		_actions.append({"op": "channel", "ok": wok, "reason": editor.last_fail_reason})
		await _idle(cm)
		_classify("channel", water_cell, _LiveWorldQuery.inspect_cell(self, water_cell.x, water_cell.y))
	_sample_natural_water(world, origin)
	var fluid = get_first_node_in_group("voxel_fluid_service")
	if fluid and fluid.has_method("get_sim_diagnostics"):
		_snaps["water_diag"] = fluid.get_sim_diagnostics()

	# Crystal + enemies as they exist in this world (observation, not spawn hacks).
	var crystal_node = get_first_node_in_group("crystal_manager")
	if crystal_node and crystal_node.has_method("get_origin_cell"):
		var coc: Vector2i = crystal_node.get_origin_cell()
		_look_at(coc.x, coc.y)
		await _idle(cm)
		if insp:
			insp.pin_cell = coc
		for _co in 6:
			await process_frame
		_classify("crystal_origin", coc, _LiveWorldQuery.inspect_cell(self, coc.x, coc.y))
		await _shot("audit_crystal")
	_observe_crystal()
	_observe_entities()
	await _shot("audit_living")

	# Stream unload/reload of the wall cell.
	await _unload_reload(cm, insp, cells.wall)

	# Travel toward far chunk then return (stream preserve).
	var home := Vector2i(floori(player.voxel_position.x), floori(player.voxel_position.z))
	_look_at(home.x + 48, home.y + 16)
	for _t in 24:
		await process_frame
	_snaps["far_stream"] = cm.get_stream_status() if cm.has_method("get_stream_status") else {}
	await _shot("audit_far")
	_look_at(cells.wall.x, cells.wall.y)
	var wait_n := 0
	while wait_n < 90:
		await process_frame
		wait_n += 1
		var life := "missing"
		if cm.has_method("get_chunk_lifecycle"):
			var ck := Vector2i(
				int(floor(float(cells.wall.x) / float(_ChunkData.SIZE))),
				int(floor(float(cells.wall.y) / float(_ChunkData.SIZE)))
			)
			life = str(cm.get_chunk_lifecycle(ck))
		var feat_layer2 = get_first_node_in_group("feature_visual_layer")
		var has_wo := feat_layer2 and feat_layer2.has_method("get_anchor_at") \
			and feat_layer2.get_anchor_at(cells.wall.x, cells.wall.y) != null
		if life == "resident" and has_wo:
			break
	await _idle(cm)
	_classify("return_wall", cells.wall, _LiveWorldQuery.inspect_cell(self, cells.wall.x, cells.wall.y))
	await _shot("audit_return")

	# Pause.
	var pause = get_first_node_in_group("pause_menu")
	if pause and pause.has_method("open"):
		pause.open()
		for _p in 4:
			await process_frame
		_f3_pause = _dump_f3()
		if "PAUSE" not in _f3_pause:
			_note("disagree", "F3 did not show PAUSE while pause open")
		await _shot("audit_pause")
		pause.close()
		for _c in 2:
			await process_frame

	# Save overlay export (persistence authority) — do not full-reload the tree here.
	var save = get_first_node_in_group("save_game_service")
	if save and save.has_method("save_slot"):
		var err: Error = save.save_slot(0, true)
		_actions.append({"op": "save_slot", "err": int(err)})
		if err != OK:
			_note("bug", "save_slot returned %d" % int(err))
	var ws = _WorldState.get_active()
	if ws and ws.has_method("export_persistence_bundle"):
		var bundle: Dictionary = ws.export_persistence_bundle()
		_snaps["persist_keys"] = bundle.keys()
		_snaps["persist_terrain_n"] = (bundle.get("terrain", {}) as Dictionary).size() if bundle.get("terrain", {}) is Dictionary else -1

	_snaps["f3"] = _f3_text
	_snaps["f3_pause"] = _f3_pause
	_snaps["perf"] = _perf_slim()
	_write_reports()
	print("AUTONOMOUS_AUDIT findings=%d fails=%d shots=%d" % [_findings.size(), _failed, _shots.size()])
	_finish()


func _record_world_vitals(cm, world, compose) -> void:
	_snaps["stage"] = str(compose.get_stage_name()) if compose and compose.has_method("get_stage_name") else ""
	_snaps["world_loading"] = _GameplayInput.world_loading
	_snaps["can_interact"] = not _GameplayInput.blocks_actions()
	if cm and cm.has_method("get_stream_status"):
		_snaps["stream"] = cm.get_stream_status()
	if cm and cm.has_method("start_region_status"):
		_snaps["start_region"] = cm.start_region_status()
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake and bake.has_method("fill_status"):
		_snaps["bake"] = bake.fill_status()
	if world and "world_seed" in world:
		_snaps["seed"] = world.world_seed
	var player = get_first_node_in_group("player")
	if player and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		_snaps["player_col"] = [floori(pv.x), floori(pv.z)]
		if world.has_method("get_biome"):
			_snaps["biome"] = str(world.get_biome(pv.x, 0.0, pv.z))


func _do_dig(editor, cm, insp, name: String, cell: Vector2i) -> void:
	var world = get_first_node_in_group("world")
	var y: float = world.get_surface_height(float(cell.x), float(cell.y)) if world else 0.0
	var ok: bool = editor.try_dig(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5))
	_actions.append({"op": name, "ok": ok, "reason": editor.last_fail_reason, "cell": [cell.x, cell.y]})
	if not ok:
		_note("bug", "%s try_dig failed: %s" % [name, editor.last_fail_reason], {"cell": [cell.x, cell.y]})
	await _idle(cm)
	_look_at(cell.x, cell.y)
	if insp:
		insp.pin_cell = cell
	for _f in 4:
		await process_frame
	_classify(name, cell, _LiveWorldQuery.inspect_cell(self, cell.x, cell.y))


func _do_build(editor, cm, insp, inv, name: String, cell: Vector2i, build_id: StringName) -> void:
	var world = get_first_node_in_group("world")
	var y: float = world.get_surface_height(float(cell.x), float(cell.y)) if world else 0.0
	var ok: bool = editor.try_build(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5), inv, build_id)
	_actions.append({"op": name, "ok": ok, "build": str(build_id), "reason": editor.last_fail_reason, "cell": [cell.x, cell.y]})
	if not ok:
		_note("bug", "%s try_build %s failed: %s" % [name, str(build_id), editor.last_fail_reason])
	await _idle(cm)
	_look_at(cell.x, cell.y)
	if insp:
		insp.pin_cell = cell
	for _f in 5:
		await process_frame
	_classify(name, cell, _LiveWorldQuery.inspect_cell(self, cell.x, cell.y))


func _do_remove(editor, cm, feat_layer, insp, name: String, cell: Vector2i) -> void:
	var feat: Dictionary = _FeatureRegistry.get_feature(cell.x, cell.y)
	var raised: bool = bool(feat.get("raises_terrain", false)) and not bool(feat.get("is_bridge", false))
	_FeatureRegistry.clear_feature(cell.x, cell.y)
	_FeatureRegistry.clear_tile_override(cell.x, cell.y)
	var ws = _WorldState.get_active()
	var key := Vector2i(cell.x, cell.y)
	if ws and "build_tile" in ws and ws.build_tile.has(key):
		ws.build_tile.erase(key)
		if ws.has_method("bump"):
			ws.bump(_WorldState.DOMAIN_TERRAIN)
	if raised and _TerrainEdits.get_height_delta(cell.x, cell.y) > 0.01:
		_TerrainEdits.dig(cell.x, cell.y, 1)
	if editor and editor.has_method("_invalidate_and_rebuild"):
		editor._invalidate_and_rebuild(cell.x, cell.y)
	if feat_layer and feat_layer.has_method("refresh_cell"):
		feat_layer.refresh_cell(cell.x, cell.y)
	_actions.append({"op": name, "cell": [cell.x, cell.y]})
	await _idle(cm)
	if insp:
		insp.pin_cell = cell
	for _f in 4:
		await process_frame
	_classify(name, cell, _LiveWorldQuery.inspect_cell(self, cell.x, cell.y))


func _unload_reload(cm, insp, cell: Vector2i) -> void:
	var key := Vector2i(
		int(floor(float(cell.x) / float(_ChunkData.SIZE))),
		int(floor(float(cell.y) / float(_ChunkData.SIZE)))
	)
	var before: Dictionary = _LiveWorldQuery.inspect_cell(self, cell.x, cell.y)
	if not cm.chunks.has(key):
		_note("bug", "unload_reload chunk not resident %s" % str(key))
		return
	cm._unload_chunk_view(key)
	cm.request_chunk(key, true)
	var waited := 0
	while waited < 180 and not cm.chunks.has(key):
		await process_frame
		waited += 1
	await _idle(cm)
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	for _a in 24:
		await process_frame
		if feat_layer and feat_layer.has_method("get_anchor_at") and feat_layer.get_anchor_at(cell.x, cell.y) != null:
			break
	_look_at(cell.x, cell.y)
	if insp:
		insp.pin_cell = cell
	for _f in 4:
		await process_frame
	var after: Dictionary = _LiveWorldQuery.inspect_cell(self, cell.x, cell.y)
	_classify("unload_reload", cell, after)
	if str(before.get("build_id", "")) != str(after.get("build_id", "")):
		_note("disagree", "unload_reload lost build_id %s → %s" % [before.get("build_id"), after.get("build_id")])
	if int(before.get("structure_count", 0)) == 1 and int(after.get("structure_count", 0)) != 1:
		_note("disagree", "unload_reload lost WorldObject")
	await _shot("audit_stream_restore")


func _classify(tag: String, cell: Vector2i, snap: Dictionary) -> void:
	_snaps[tag] = _slim(snap)
	var disc = snap.get("discrepancies", [])
	var items: Array = []
	if disc is PackedStringArray or disc is Array:
		for d in disc:
			items.append(str(d))
	var row := {
		"tag": tag,
		"cell": [cell.x, cell.y],
		"ok": bool(snap.get("ok", false)),
		"voxel_id": snap.get("voxel_id", ""),
		"visual_id": snap.get("visual_id", ""),
		"build_id": snap.get("build_id", ""),
		"origin": snap.get("origin", ""),
		"chunk_lifecycle": snap.get("chunk_lifecycle", ""),
		"covered": snap.get("column_mesh_covered", false),
		"collision_kind": snap.get("collision_kind", ""),
		"structure_count": snap.get("structure_count", 0),
		"has_ramp": snap.get("has_ramp", false),
		"has_crystal": snap.get("has_crystal", false),
		"is_water": snap.get("is_water", false),
		"disc": items,
	}
	_actions.append({"op": "inspect", "tag": tag, "row": row})
	if not items.is_empty():
		_note("disagree", "%s %s,%s %s" % [tag, str(cell.x), str(cell.y), ",".join(PackedStringArray(items))], row)
	# Logical vs rendered: feature claims a WorldObject the inspector cannot see.
	if str(snap.get("build_id", "")) != "" and int(snap.get("structure_count", 0)) != 1:
		_note("disagree", "%s feature %s structure_count=%s" % [tag, snap.get("build_id"), str(snap.get("structure_count"))], row)
	if bool(snap.get("streamed", false)) and not bool(snap.get("column_mesh_covered", false)) and not bool(snap.get("has_ramp", false)):
		_note("disagree", "%s streamed MESH_HOLE" % tag, row)


func _observe_hud_and_vegetation(origin: Vector2i) -> void:
	var overlay = get_first_node_in_group("game_overlay")
	var hud_text := ""
	if overlay:
		var hud = overlay.get_node_or_null("GameHud")
		if hud:
			hud_text = str(hud.text)
	_snaps["game_hud"] = hud_text
	var crystal = get_first_node_in_group("crystal_manager")
	var tiles := 0
	if crystal and "covered_cells" in crystal:
		tiles = int(crystal.covered_cells)
	if tiles > 0 and "0.0%" in hud_text:
		_note("disagree", "HUD still prints 0.0%% while tiles=%d: %s" % [tiles, hud_text])
	elif tiles > 0 and ("%dc" % tiles) not in hud_text and ("Crystal %d" % tiles) not in hud_text:
		_note("disagree", "HUD hides live crystal tiles=%d: %s" % [tiles, hud_text])
	else:
		_note("observe", "HUD %s" % hud_text)
	var plants := 0
	var visuals := 0
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	for dz in range(0, 16):
		for dx in range(0, 16):
			var wx := origin.x + dx
			var wz := origin.y + dz
			var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
			if str(feat.get("plant_id", "")) != "":
				plants += 1
				if feat_layer and feat_layer.has_method("get_anchor_at") and feat_layer.get_anchor_at(wx, wz) != null:
					visuals += 1
	_snaps["plants_near_origin"] = plants
	_snaps["plant_visuals_near_origin"] = visuals
	_note("observe", "vegetation overlay plants=%d visuals=%d in 16x16 at origin" % [plants, visuals])
	if crystal and crystal.has_method("get_origin_cell"):
		var oc: Vector2i = crystal.get_origin_cell()
		_snaps["crystal_origin"] = [oc.x, oc.y]
		var cm = get_first_node_in_group("chunk_manager")
		if cm and cm.has_method("start_stream_coords"):
			var ck := Vector2i(
				int(floor(float(oc.x) / float(_ChunkData.SIZE))),
				int(floor(float(oc.y) / float(_ChunkData.SIZE)))
			)
			var in_start := false
			for v in cm.start_stream_coords():
				if v == ck:
					in_start = true
					break
			_snaps["crystal_origin_in_start_stream"] = in_start
			if not in_start:
				_note("disagree", "crystal origin chunk %s not in start stream ring" % str(ck))
			else:
				_note("observe", "crystal origin %s chunk %s in start stream" % [str(oc), str(ck)])


func _observe_crystal() -> void:
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal == null:
		_note("observe", "no crystal_manager")
		return
	var stats: Dictionary = crystal.get_debug_stats() if crystal.has_method("get_debug_stats") else {}
	_snaps["crystal"] = stats
	var tiles := int(stats.get("tiles", 0))
	_note("observe", "crystal tiles=%d power=%s spawns=%s/%s" % [
		tiles, str(stats.get("power", 0)), str(stats.get("spawns_active", 0)), str(stats.get("spawns_total", 0))
	])
	if tiles <= 0:
		_note("bug", "crystal has no covered cells after stream-ready")
	if crystal.has_method("has_crystal_at"):
		var player = get_first_node_in_group("player")
		var px := 0
		var pz := 0
		if player and player.has_method("get_voxel_position"):
			var pv: Vector3 = player.get_voxel_position()
			px = floori(pv.x)
			pz = floori(pv.z)
		for dz in range(-24, 25, 3):
			for dx in range(-24, 25, 3):
				if crystal.has_crystal_at(px + dx, pz + dz):
					var cc := Vector2i(px + dx, pz + dz)
					_classify("crystal_cell", cc, _LiveWorldQuery.inspect_cell(self, cc.x, cc.y))
					return


func _observe_entities() -> void:
	var enemies: Array = get_nodes_in_group("crystal_enemy")
	var ents: Array = get_nodes_in_group("world_entity")
	_snaps["enemy_n"] = enemies.size()
	_snaps["entity_n"] = ents.size()
	_note("observe", "enemies=%d world_entities=%d" % [enemies.size(), ents.size()])
	if enemies.is_empty() and ents.is_empty():
		_note("observe", "no entities in start region (grade F until travel/time)")
	elif not enemies.is_empty():
		var e: Node = enemies[0]
		if e is Node3D:
			var col: Vector2 = _WorldVisualCoords.column_from_node(e)
			_snaps["enemy0_col"] = [col.x, col.y]


func _sample_natural_water(world, origin: Vector2i) -> void:
	var found := Vector2i(-1, -1)
	for dz in range(-12, 20, 2):
		for dx in range(-12, 20, 2):
			var wx := origin.x + dx
			var wz := origin.y + dz
			var tile: int = int(world.get_tile_type(float(wx), float(wz)))
			if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3, _VoxelTypes.RIVER, _VoxelTypes.WATER]:
				found = Vector2i(wx, wz)
				break
		if found.x >= 0:
			break
	if found.x >= 0:
		_classify("natural_water", found, _LiveWorldQuery.inspect_cell(self, found.x, found.y))
	else:
		_note("observe", "no natural water tile in ±20 of origin")


func _look_at(wx: int, wz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(wx) + 0.5
	player.voxel_position.z = float(wz) - 2.0
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()


func _idle(cm) -> void:
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	for _w in 4:
		await process_frame


func _dump_f3() -> String:
	var panel = get_first_node_in_group("debug_panel")
	if panel == null:
		return ""
	if panel.has_method("set_overlay_visible"):
		panel.set_overlay_visible(true)
	if panel.has_method("refresh_now"):
		return str(panel.refresh_now())
	if panel.has_method("get_overlay_text"):
		return str(panel.get_overlay_text())
	return ""


func _perf_slim() -> Dictionary:
	var profiler = root.get_node_or_null("/root/PerfProfiler")
	if profiler == null or not profiler.has_method("get_snapshot"):
		return {}
	var snap: Dictionary = profiler.get_snapshot()
	var secs: Dictionary = snap.get("sections", {})
	var hot: Array = []
	for k in secs.keys():
		var e: Dictionary = secs[k]
		var ms: float = float(e.get("last_ms", 0.0))
		if ms <= 0.0 and e.has("last_us"):
			ms = float(e.last_us) / 1000.0
		if ms > 0.2:
			hot.append({"name": str(k), "ms": ms})
	hot.sort_custom(func(a, b): return float(a.ms) > float(b.ms))
	if hot.size() > 8:
		hot = hot.slice(0, 8)
	return {
		"frame_ms": snap.get("frame_ms", 0.0),
		"worker_ms": snap.get("worker_ms", 0.0),
		"hot": hot,
		"mem_mb": (snap.get("gauges", {}) as Dictionary).get("mem_current_mb", 0.0),
	}


func _slim(s: Dictionary) -> Dictionary:
	return {
		"wx": s.get("wx", 0), "wz": s.get("wz", 0),
		"visual_id": s.get("visual_id", ""),
		"build_id": s.get("build_id", ""),
		"origin": s.get("origin", ""),
		"chunk_lifecycle": s.get("chunk_lifecycle", ""),
		"covered": s.get("column_mesh_covered", false),
		"disc": s.get("discrepancies", []),
		"structure_count": s.get("structure_count", 0),
		"has_ramp": s.get("has_ramp", false),
		"collision_kind": s.get("collision_kind", ""),
		"has_crystal": s.get("has_crystal", false),
		"is_water": s.get("is_water", false),
		"surf": s.get("surface_height", 0.0),
		"walk": s.get("walkable_height", 0.0),
	}


func _find_dry_origin(world, cm) -> Vector2i:
	if world == null:
		return Vector2i(8, 8)
	for oz in range(8, 48, 4):
		for ox in range(8, 48, 4):
			var wet := false
			for dx in range(0, 16):
				for dz in range(0, 8):
					var tile: int = int(world.get_tile_type(float(ox + dx), float(oz + dz)))
					if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3, _VoxelTypes.RIVER, _VoxelTypes.WATER]:
						wet = true
						break
					if cm and not _ActionTargeting._is_solid_column(world, cm, ox + dx, oz + dz):
						wet = true
						break
				if wet:
					break
			if not wet:
				return Vector2i(ox, oz)
	return Vector2i(8, 8)


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw()
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _scratch.path_join("%s.png" % name)
	img.save_png(path)
	_shots.append(path)
	print("SHOT %s" % path)


func _write_reports() -> void:
	var json_path := _scratch.path_join("autonomous_audit.json")
	var data := {
		"findings": _findings,
		"actions": _actions,
		"snaps": _snaps,
		"shots": _shots,
		"windowed": _windowed,
		"failed": _failed,
	}
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(data, "\t"))
		jf.close()
		print("WROTE %s" % json_path)
	var md := FileAccess.open(_scratch.path_join("autonomous_audit.md"), FileAccess.WRITE)
	if md:
		md.store_string(_format_md())
		md.close()
		print("WROTE %s" % _scratch.path_join("autonomous_audit.md"))


func _format_md() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Autonomous gameplay audit")
	lines.append("")
	lines.append("windowed=%s  findings=%d  fails=%d" % [str(_windowed), _findings.size(), _failed])
	lines.append("")
	lines.append("## F3")
	lines.append("```")
	lines.append(_f3_text)
	lines.append("```")
	if not _f3_pause.is_empty():
		lines.append("### F3 while paused")
		lines.append("```")
		lines.append(_f3_pause)
		lines.append("```")
	lines.append("")
	lines.append("## Findings")
	for f in _findings:
		lines.append("- **%s**: %s" % [str(f.get("kind")), str(f.get("msg"))])
	lines.append("")
	lines.append("## Acted-on cells (F4 / LiveWorldQuery)")
	for tag in _snaps.keys():
		var v = _snaps[tag]
		if v is Dictionary and v.has("wx"):
			lines.append("- `%s` (%s,%s) origin=%s life=%s visual=%s build=%s covered=%s disc=%s" % [
				str(tag), str(v.get("wx")), str(v.get("wz")),
				str(v.get("origin")), str(v.get("chunk_lifecycle")),
				str(v.get("visual_id")), str(v.get("build_id")),
				str(v.get("covered")), str(v.get("disc")),
			])
	lines.append("")
	lines.append("## Crystal / entities / water")
	lines.append("- crystal: %s" % str(_snaps.get("crystal", {})))
	lines.append("- enemies=%s entities=%s" % [str(_snaps.get("enemy_n", 0)), str(_snaps.get("entity_n", 0))])
	lines.append("- water_diag: %s" % str(_snaps.get("water_diag", {})))
	lines.append("- stream: %s" % str(_snaps.get("stream", {})))
	lines.append("- bake: %s" % str(_snaps.get("bake", {})))
	lines.append("- perf: %s" % str(_snaps.get("perf", {})))
	lines.append("")
	lines.append("## Shots")
	for s in _shots:
		lines.append("- %s" % s)
	return "\n".join(lines)


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All autonomous gameplay audit OK")
	else:
		_ProbeExit.finish_tree(self, 1, "AUTONOMOUS GAMEPLAY AUDIT FAILED")
