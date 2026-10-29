extends SceneTree

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
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 30:
		await process_frame
	var coord = _game.find_child("DevToolsCoordinator", true, false)
	if coord == null:
		coord = get_first_node_in_group("dev_tools_coordinator")
	var panel = get_first_node_in_group("debug_panel")
	var insp = get_first_node_in_group("live_world_inspector")
	var pm = get_first_node_in_group("pause_menu")
	print("P7_N nodes coord=%s panel=%s insp=%s pause=%s" % [coord != null, panel != null, insp != null, pm != null])
	var has_action := InputMap.has_action("debug_panel_toggle")
	var f7 := false
	if has_action:
		for e in InputMap.action_get_events("debug_panel_toggle"):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_F7:
				f7 = true
	print("P7_N action=%s f7=%s" % [has_action, f7])
	if not f7:
		_fail("no F7 action")
	print("P7_N start panel_visible=%s insp_open=%s" % [_vis(panel), _open(insp)])
	await _press_f7()
	var txt := str(panel.get_overlay_text()) if panel and panel.has_method("get_overlay_text") else ""
	print("P7_N f7_on panel_visible=%s insp_open=%s text_len=%d" % [_vis(panel), _open(insp), txt.length()])
	print("P7_N text_head %s" % txt.substr(0, 160).replace("\n", " | "))
	if not _vis(panel) or not _open(insp) or txt.length() < 20:
		_fail("F7 did not open debug view")
	await _press_f7()
	print("P7_N f7_off panel_visible=%s insp_open=%s" % [_vis(panel), _open(insp)])
	if _vis(panel) or _open(insp):
		_fail("F7 did not close debug view")
	var btn_found := false
	if pm:
		pm.open()
		await process_frame
		for b in pm.find_children("*", "Button", true, false):
			if str(b.text) == "Debug view (F7)":
				btn_found = true
				b.emit_signal("pressed")
		await process_frame
		await process_frame
	print("P7_N pause_button found=%s panel_visible=%s insp_open=%s paused=%s" % [btn_found, _vis(panel), _open(insp), paused])
	if not btn_found or not _vis(panel) or paused:
		_fail("pause menu debug view button")
	_finish()


func _vis(panel) -> bool:
	return panel != null and bool(panel.is_overlay_visible())


func _open(insp) -> bool:
	return insp != null and bool(insp.panel_open)


func _press_f7() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F7
		ev.keycode = KEY_F7
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame
	for _k in 3:
		await process_frame

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


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "P7_N OK")
	else:
		_ProbeExit.finish_tree(self, 1, "P7_N FAILED")
