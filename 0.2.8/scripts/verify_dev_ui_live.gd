extends SceneTree
## Live dump of compact F3 / sectioned F4 / loading-bake / pause input.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")


var _failed: int = 0
var _scratch: String = ""
var _windowed: bool = false
var _game: Node = null


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


func _fail(m: String) -> void:
	_failed += 1
	push_error(m)
	print("FAIL %s" % m)


func _ok(m: String) -> void:
	print("OK %s" % m)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961e51b3a68c/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	_windowed = DisplayServer.get_name() != "headless"
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	_game = packed.instantiate()
	root.add_child(_game)
	var compose = _game.get_node_or_null("CompositionRoot")
	var loading = _capture_loading(compose)
	var frames := 0
	var loading_shot := false
	while frames < 3600:
		var mid := _capture_loading(compose)
		var phase := str(mid.get("phase_label", "")).to_lower()
		if str(mid.get("bake_label", "")).begins_with("Start region") or "cannot play" in phase or "nearby chunks" in phase:
			loading = mid
		if _windowed and not loading_shot:
			var ls = _game.find_child("LoadingScreen", true, false) if _game else null
			if ls and ls.visible and float(ls.modulate.a) > 0.5 and "nearby chunks" in phase:
				for _lw in 4:
					await process_frame
				await _shot("dev_ui_loading")
				loading_shot = true
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	if _windowed and not loading_shot:
		var ls_late = _game.find_child("LoadingScreen", true, false) if _game else null
		if ls_late and ls_late.visible and float(ls_late.modulate.a) > 0.15:
			await _shot("dev_ui_loading")
			loading_shot = true
	for _w in 40:
		await process_frame
		if not _GameplayInput.world_loading:
			break
	for _settle in 8:
		await process_frame

	var f3_text := _dump_f3()
	_write_text("dev_ui_f3.txt", f3_text)
	if "fps" not in f3_text.to_lower() or "chunks" not in f3_text.to_lower():
		_fail("F3 missing fps/chunks")
	else:
		_ok("F3 compact status")
	if "Crystal Volume" in f3_text or "evolution" in f3_text.to_lower():
		_fail("F3 still mixed combat/save wall")
	if "streamQ" not in f3_text and "stream" not in f3_text.to_lower():
		_fail("F3 missing stream queue")
	if "bake" not in f3_text.to_lower():
		_fail("F3 missing bake")
	if "water" not in f3_text.to_lower():
		_fail("F3 missing water")
	if "LOADING" in f3_text and not _GameplayInput.world_loading:
		_fail("F3 still says LOADING after overlay dismiss")
	elif "PLAY" in f3_text or "LOCKED" in f3_text:
		_ok("F3 interact flag after ready")

	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var origin := _find_dry_origin(world, cm)
	var yard: Dictionary = _ValidationYard.apply(self, origin.x, origin.y)
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(60)
	var cells: Dictionary = yard.get("cells", {})
	var insp = _game.get_node_or_null("LiveWorldInspector")
	if insp == null:
		insp = get_first_node_in_group("live_world_inspector")
	if insp == null:
		_fail("no inspector")
		_finish()
		return
	insp.panel_open = true
	var wall: Vector2i = cells.get("stone_wall", origin)
	insp.pin_cell = wall
	for _p in 6:
		await process_frame
	var f4a: Dictionary = insp.last_snapshot
	_assert_f4_matches(wall, f4a, "pin wall")
	_assert_f4_source(f4a, "pin wall")
	var gate: Vector2i = cells.get("gate", origin + Vector2i(4, 3))
	insp.pin_cell = gate
	for _p2 in 6:
		await process_frame
	var f4b: Dictionary = insp.last_snapshot
	if int(f4b.get("wx", -1)) != gate.x or int(f4b.get("wz", -1)) != gate.y:
		_fail("F4 leftover pin: want %s got %s,%s" % [str(gate), str(f4b.get("wx")), str(f4b.get("wz"))])
	else:
		_ok("F4 pin replace not merge")
	_assert_f4_source(f4b, "pin gate")
	_write_json("dev_ui_f4.json", {
		"pin_wall": _slim(f4a),
		"pin_gate": _slim(f4b),
	})

	var after := _capture_loading(compose)
	after["after_ready_world_loading"] = _GameplayInput.world_loading
	after["stage_name"] = str(compose.get_stage_name()) if compose.has_method("get_stage_name") else ""
	after["can_interact"] = not _GameplayInput.blocks_actions()
	var bake_chip := ""
	var overlay = get_first_node_in_group("game_overlay")
	if overlay:
		var chip = overlay.get_node_or_null("BakeChip")
		if chip:
			bake_chip = str(chip.text) if chip.visible else ""
	after["background_bake_chip"] = bake_chip
	loading["after_ready"] = after
	loading["after_ready_world_loading"] = after["after_ready_world_loading"]
	loading["stage_name"] = after["stage_name"]
	loading["can_interact"] = after["can_interact"]
	loading["background_bake_chip"] = bake_chip
	if _GameplayInput.world_loading:
		_fail("world_loading still true after stream ready + settle")
	else:
		_ok("interact unlocked after overlay dismiss")
	_write_json("dev_ui_loading.json", loading)

	insp.panel_open = false
	for _hide in 2:
		await process_frame
	var pause = get_first_node_in_group("pause_menu")
	var f3p = get_first_node_in_group("debug_panel")
	if pause and pause.has_method("open"):
		pause.open()
		if not _GameplayInput.pause_open:
			_fail("ESC pause_open not set")
		else:
			_ok("pause open")
		if f3p and f3p.has_method("refresh_now"):
			f3p.refresh_now()
		for _pw in 4:
			await process_frame
		var pause_text := _dump_f3()
		_write_text("dev_ui_f3_pause.txt", pause_text)
		if "PAUSE" not in pause_text:
			_fail("F3 missing PAUSE while pause open: %s" % pause_text.replace("\n", " | "))
		else:
			_ok("F3 PAUSE while pause open")
		if _windowed:
			await _shot("dev_ui_pause")
		pause.close()
		if _GameplayInput.pause_open:
			_fail("pause still open after close")
		else:
			_ok("pause close")
		if f3p and f3p.has_method("refresh_now"):
			f3p.refresh_now()
		for _pc in 2:
			await process_frame
	else:
		_fail("no pause menu")

	if _windowed:
		insp.panel_open = false
		if f3p:
			f3p.set_overlay_visible(true)
			if f3p.has_method("refresh_now"):
				f3p.refresh_now()
		for _s0 in 4:
			await process_frame
		await _shot("dev_ui_f3")
		insp.panel_open = true
		insp.pin_cell = wall
		for _s in 6:
			await process_frame
		await _shot("dev_ui_f4")

	print("DEV_UI_LIVE failed=%d" % _failed)
	_finish()


func _capture_loading(compose) -> Dictionary:
	var ls = _game.find_child("LoadingScreen", true, false) if _game else null
	var phase := ""
	var bake_l := ""
	var pct := ""
	if ls:
		var ph = ls.get_node_or_null("Center/PhaseLabel")
		if ph == null:
			ph = ls.find_child("PhaseLabel", true, false)
		if ph:
			phase = str(ph.text)
		var bl = ls.find_child("BakeLabel", true, false)
		if bl:
			bake_l = str(bl.text)
		var pc = ls.find_child("Percent", true, false)
		if pc:
			pct = str(pc.text)
	return {
		"stage": int(compose.stage) if compose else -1,
		"phase_label": phase,
		"bake_label": bake_l,
		"percent": pct,
		"world_loading": _GameplayInput.world_loading,
		"progress_source": "start_region_status + fill_status",
	}


func _dump_f3() -> String:
	var panel = get_first_node_in_group("debug_panel")
	if panel == null:
		return ""
	if panel.has_method("set_overlay_visible"):
		panel.set_overlay_visible(true)
	if panel.has_method("refresh_now"):
		return str(panel.refresh_now())
	if panel.has_method("_process"):
		panel._process(0.016)
	if panel.has_method("get_overlay_text"):
		return str(panel.get_overlay_text())
	var lab = panel.get_node_or_null("DebugLabel")
	return str(lab.text) if lab else ""


func _assert_f4_matches(cell: Vector2i, snap: Dictionary, tag: String) -> void:
	var q: Dictionary = _LiveWorldQuery.inspect_cell(self, cell.x, cell.y)
	if int(snap.get("wx", -9)) != cell.x or int(snap.get("wz", -9)) != cell.y:
		_fail("%s cell mismatch" % tag)
		return
	if str(snap.get("visual_id", "")) != str(q.get("visual_id", "")):
		_fail("%s visual_id overlay=%s query=%s" % [tag, snap.get("visual_id"), q.get("visual_id")])
	else:
		_ok("%s visual_id=%s" % [tag, snap.get("visual_id")])


func _assert_f4_source(snap: Dictionary, tag: String) -> void:
	var src := str(snap.get("column_source", ""))
	if src in ["bake", "generate", "blocked", "dirty", "resident", "none"]:
		_fail("%s column_source is global last job '%s'" % [tag, src])
		return
	var origin := str(snap.get("origin", ""))
	if origin.is_empty():
		_fail("%s missing cell origin" % tag)
		return
	var life := str(snap.get("chunk_lifecycle", ""))
	if life not in ["resident", "queued", "baking", "missing", "rebuild", "unloading"]:
		_fail("%s bad chunk_lifecycle '%s'" % [tag, life])
		return
	_ok("%s origin=%s lifecycle=%s" % [tag, origin, life])


func _slim(s: Dictionary) -> Dictionary:
	return {
		"wx": s.get("wx", 0), "wz": s.get("wz", 0),
		"visual_id": s.get("visual_id", ""),
		"build_id": s.get("build_id", ""),
		"covered": s.get("column_mesh_covered", false),
		"disc": s.get("discrepancies", []),
		"surface": s.get("surface_height", 0.0),
		"walk": s.get("walkable_height", 0.0),
		"origin": s.get("origin", ""),
		"column_source": s.get("column_source", ""),
		"chunk_lifecycle": s.get("chunk_lifecycle", ""),
	}


func _find_dry_origin(world, cm) -> Vector2i:
	if world == null:
		return Vector2i(8, 8)
	for oz in range(8, 40, 4):
		for ox in range(8, 40, 4):
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


func _write_text(name: String, text: String) -> void:
	var f := FileAccess.open(_scratch.path_join(name), FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		print("WROTE %s" % _scratch.path_join(name))


func _write_json(name: String, data: Dictionary) -> void:
	var f := FileAccess.open(_scratch.path_join(name), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		print("WROTE %s" % _scratch.path_join(name))


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
	img.save_png(_scratch.path_join("%s.png" % name))
	print("SHOT %s" % _scratch.path_join("%s.png" % name))


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All dev UI live tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "DEV UI LIVE FAILED")
