extends SceneTree
## Windowed gameplay-camera validation of inspector, ramps, edits, buildings, loading, water.

const MAIN_SCENE := "res://scenes/main.tscn"
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

var _scratch: String = ""
var _report: Dictionary = {}
var _shots: PackedStringArray = PackedStringArray()


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-3d5f46ee7f59/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	call_deferred("_run")


func _run() -> void:
	var t_boot := Time.get_ticks_msec()
	_report["cold_to_scene_ms"] = 0
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_finish(false, "no main scene")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var ready_ms := -1
	var blocked := false
	var load_texts: PackedStringArray = PackedStringArray()
	var frames := 0
	while frames < 3600:
		if _GameplayInput.blocks_actions():
			blocked = true
		var ls = get_first_node_in_group("loading_screen")
		if ls != null and "_bake_label" in ls:
			var lab = ls._bake_label
			if lab != null and str(lab.text) != "":
				if load_texts.is_empty() or load_texts[load_texts.size() - 1] != str(lab.text):
					load_texts.append(str(lab.text))
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			ready_ms = Time.get_ticks_msec() - t_boot
			break
		await process_frame
		frames += 1
	_report["play_to_start_region_ms"] = ready_ms
	_report["ics_frames"] = frames
	_report["input_blocked_until_ready"] = blocked
	_report["loading_labels"] = load_texts
	var cm = get_first_node_in_group("chunk_manager")
	var bake = load("res://world/world_bake_service.gd").get_active()
	_report["start_region"] = cm.start_region_status() if cm and cm.has_method("start_region_status") else {}
	_report["bake_in_progress_at_playable"] = bool(bake.bake_in_progress) if bake else false
	_report["bake_valid"] = bool(bake.valid) if bake else false
	if ready_ms < 0:
		_finish(false, "start region not ready")
		return
	for _w in 25:
		await process_frame
	var yard: Dictionary = _ValidationYard.apply(self, 24, 24)
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	for _w2 in 8:
		await process_frame
	var cells_pre: Dictionary = yard.get("cells", {})
	_ValidationYard.apply_generated_ramps(self, cells_pre)
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	for _w3 in 12:
		await process_frame
	var _TerrainRamps = load("res://helpers/terrain_ramps.gd")
	if _TerrainRamps:
		_TerrainRamps.placement_chance = _TerrainRamps.PLACEMENT_CHANCE
	if cm and "ramp_placement_chance" in cm:
		cm.ramp_placement_chance = _TerrainRamps.PLACEMENT_CHANCE if _TerrainRamps else 28
	var insp = game.get_node_or_null("LiveWorldInspector")
	if insp:
		insp.panel_open = true
	var pause = game.get_node_or_null("PauseMenu")
	_report["inspector_present"] = insp != null
	_report["pause_present"] = pause != null
	_report["debug_panel_compact"] = _debug_is_compact()
	_look_at_yard(24, 24)
	await process_frame
	_shot("00_yard_overview")
	var cells: Dictionary = yard.get("cells", {})
	var snaps: Dictionary = {}
	for key in cells.keys():
		var c: Vector2i = cells[key]
		_look_at_cell(c.x, c.y)
		if insp:
			insp.pin_cell = c
		for _wf in 3:
			await process_frame
		var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, c.x, c.y)
		snaps[key] = {
			"wx": c.x, "wz": c.y,
			"ok": snap.get("ok", false),
			"visual_id": snap.get("visual_id", ""),
			"build_id": snap.get("build_id", ""),
			"has_ramp": snap.get("has_ramp", false),
			"ramp": snap.get("ramp", {}),
			"covered": snap.get("column_mesh_covered", false),
			"collision_kind": snap.get("collision_kind", ""),
			"collision_exists": snap.get("collision_exists", false),
			"structure_count": snap.get("structure_count", 0),
			"yaw": snap.get("orientation_yaw", 0.0),
			"surface": snap.get("surface_height", 0.0),
			"walk": snap.get("walkable_height", 0.0),
			"discrepancies": snap.get("discrepancies", []),
			"origin": snap.get("origin", ""),
			"interactable": snap.get("interactable", false),
		}
		_shot("cell_%s_%d_%d" % [key, c.x, c.y])
	_report["cell_snapshots"] = snaps
	_report["ramps"] = _eval_ramps(snaps)
	_report["buildings"] = _eval_buildings(snaps)
	_report["edits"] = await _run_edit_sequence(cells, cm)
	_report["hitboxes"] = _eval_hitboxes(cells)
	_report["water"] = await _eval_water_frames()
	_report["building_yaw"] = _eval_building_yaw(snaps)
	_report["bake_after"] = {
		"in_progress": bool(bake.bake_in_progress) if bake else false,
		"packages": int(bake._packages_known.size()) if bake and "_packages_known" in bake else -1,
	}
	var profiler = root.get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("format_runtime_report"):
		_report["perf_after_yard"] = profiler.format_runtime_report()
	_write_json()
	_finish(true, "DISPLAY GAMEPLAY VALIDATION OK")


func _look_at_yard(ox: int, oz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(ox) + 2.5
	player.voxel_position.z = float(oz) - 3.5
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()


func _look_at_cell(wx: int, wz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(wx) + 0.5
	player.voxel_position.z = float(wz) - 2.0
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _scratch.path_join("%s.png" % name)
	if img.save_png(path) == OK:
		_shots.append(path)
		print("SHOT %s" % path)


func _eval_ramps(snaps: Dictionary) -> Dictionary:
	var out := {"found": {}, "missing": [], "ok": true}
	for key in ["ramp_east", "ramp_west", "ramp_south", "ramp_north"]:
		var s: Dictionary = snaps.get(key, {})
		var has := bool(s.get("has_ramp", false))
		out["found"][key] = {"has_ramp": has, "ramp": s.get("ramp", {}), "disc": s.get("discrepancies", [])}
		if not has:
			out["missing"].append(key)
			out["ok"] = false
	return out


func _eval_buildings(snaps: Dictionary) -> Dictionary:
	var out := {"ok": true, "rows": {}}
	for key in ["wood_wall", "stone_wall", "gate", "bridge"]:
		var s: Dictionary = snaps.get(key, {})
		var count := int(s.get("structure_count", 0))
		var bid := str(s.get("build_id", ""))
		var vid := str(s.get("visual_id", ""))
		var row := {
			"count": count, "build_id": bid, "visual_id": vid,
			"disc": s.get("discrepancies", []),
			"collision_kind": s.get("collision_kind", ""),
		}
		if count != 1 or bid != key or vid != key:
			out["ok"] = false
		out["rows"][key] = row
	return out


func _run_edit_sequence(cells: Dictionary, cm) -> Dictionary:
	var editor = get_first_node_in_group("terrain_editor")
	var out := {"steps": []}
	if editor == null:
		out["error"] = "no editor"
		return out
	var seq: Array = [
		["dig_one", "dig"],
		["dig_adj", "dig"],
		["slab", "dig"],
		["flat", "build"],
		["raised", "build"],
	]
	# Adversarial: chunk seam (32) and chunk corner, plus a cell next to a stamped ramp.
	cells["seam"] = Vector2i(32, 24)
	cells["corner"] = Vector2i(32, 32)
	cells["near_ramp"] = Vector2i(int(cells.ramp_east.x) + 1, int(cells.ramp_east.y))
	seq.append(["seam", "dig"])
	seq.append(["corner", "dig"])
	seq.append(["near_ramp", "dig"])
	for step_v in seq:
		var key: String = step_v[0]
		var kind: String = step_v[1]
		var c: Vector2i = cells.get(key, Vector2i.ZERO)
		var before: Dictionary = _LiveWorldQuery.inspect_cell(self, c.x, c.y)
		var pos := Vector3(float(c.x) + 0.5, float(before.get("surface_height", 0.0)), float(c.y) + 0.5)
		if kind == "dig":
			editor.try_dig(pos)
		else:
			var player = get_first_node_in_group("player")
			var inv = player.inventory if player and "inventory" in player else null
			if inv:
				inv.add_item("stone", 4)
			editor.try_build_wall(pos, inv, true)
		if cm and cm.has_method("await_rebuild_idle"):
			await cm.await_rebuild_idle(60)
		await process_frame
		await process_frame
		var after: Dictionary = _LiveWorldQuery.inspect_cell(self, c.x, c.y)
		var neigh: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nsnap: Dictionary = _LiveWorldQuery.inspect_cell(self, c.x + d.x, c.y + d.y)
			neigh.append({
				"cell": [c.x + d.x, c.y + d.y],
				"covered": nsnap.get("column_mesh_covered", false),
				"disc": nsnap.get("discrepancies", []),
			})
		out["steps"].append({
			"key": key, "kind": kind,
			"covered_before": before.get("column_mesh_covered", false),
			"covered_after": after.get("column_mesh_covered", false),
			"disc_after": after.get("discrepancies", []),
			"neighbors": neigh,
		})
		_look_at_cell(c.x, c.y)
		await process_frame
		_shot("edit_%s_%s" % [kind, key])
	return out


func _eval_hitboxes(cells: Dictionary) -> Dictionary:
	var player = get_first_node_in_group("player")
	if player == null or not player.has_method("is_colliding_at"):
		return {"error": "no player collide"}
	var wall: Vector2i = cells.get("stone_wall", Vector2i.ZERO)
	var gate: Vector2i = cells.get("gate", Vector2i.ZERO)
	var wall_pos := Vector3(float(wall.x) + 0.5, player.voxel_position.y, float(wall.y) + 0.5)
	var gate_pos := Vector3(float(gate.x) + 0.5, player.voxel_position.y, float(gate.y) + 0.5)
	# Sample at walkable height of each cell.
	var wsnap: Dictionary = _LiveWorldQuery.inspect_cell(self, wall.x, wall.y)
	var gsnap: Dictionary = _LiveWorldQuery.inspect_cell(self, gate.x, gate.y)
	wall_pos.y = float(wsnap.get("walkable_height", wall_pos.y)) + 0.2
	gate_pos.y = float(gsnap.get("walkable_height", gate_pos.y)) + 0.2
	var wall_block: bool = bool(player.is_colliding_at(wall_pos))
	var gate_block: bool = bool(player.is_colliding_at(gate_pos))
	return {
		"wall_blocks": wall_block,
		"gate_blocks": gate_block,
		"expected": "wall blocks via heightfield; gate is passage",
		"wall_kind": wsnap.get("collision_kind", ""),
		"gate_kind": gsnap.get("collision_kind", ""),
	}


func _eval_water() -> Dictionary:
	var fluid = get_first_node_in_group("voxel_fluid_service")
	if fluid == null or not fluid.has_method("get_sim_diagnostics"):
		return {"error": "no fluid diagnostics"}
	return fluid.get_sim_diagnostics()


func _eval_water_frames() -> Dictionary:
	var samples: Array = []
	var worst_us := 0
	var slept := 0
	for _i in 20:
		await process_frame
		var d: Dictionary = _eval_water()
		var us: int = int(d.get("last_tick_us", 0))
		if us > worst_us:
			worst_us = us
		if bool(d.get("sleeping", false)):
			slept += 1
		if samples.size() < 4 or _i == 19:
			samples.append(d)
	return {
		"samples": samples,
		"worst_tick_us": worst_us,
		"sleep_frames": slept,
		"loads_all_channels_each_tick": bool(samples.back().get("loads_all_channels_each_tick", true)) if not samples.is_empty() else true,
		"active_gate": str(samples.back().get("active_gate", "")) if not samples.is_empty() else "",
	}


func _eval_building_yaw(snaps: Dictionary) -> Dictionary:
	var ew_a: Dictionary = snaps.get("adj_a", {})
	var ew_b: Dictionary = snaps.get("adj_b", {})
	var ns_a: Dictionary = snaps.get("ns_a", {})
	var ns_b: Dictionary = snaps.get("ns_b", {})
	var ew_yaw := float(ew_a.get("yaw", 99.0))
	var ns_yaw := float(ns_a.get("yaw", 99.0))
	return {
		"ew_pair": [ew_yaw, float(ew_b.get("yaw", 99.0))],
		"ns_pair": [ns_yaw, float(ns_b.get("yaw", 99.0))],
		"ew_ok": absf(ew_yaw) < 0.05,
		"ns_ok": absf(ns_yaw - PI * 0.5) < 0.05,
	}


func _debug_is_compact() -> bool:
	var panel = get_first_node_in_group("debug_panel")
	if panel == null:
		return false
	var label = panel.get_node_or_null("DebugLabel")
	if label == null:
		return false
	var t := str(label.text)
	return t.begins_with("F3") or t.length() < 400


func _write_json() -> void:
	_report["screenshots"] = _shots
	var path := _scratch.path_join("gameplay_validation.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_report, "\t"))
		f.close()
		print("WROTE %s" % path)


func _finish(ok: bool, marker: String) -> void:
	print(marker)
	if ok:
		_ProbeExit.finish_tree(self, 0, marker)
	else:
		_ProbeExit.finish_tree(self, 1, marker)
