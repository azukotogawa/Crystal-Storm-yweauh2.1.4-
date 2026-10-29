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
	OS.set_environment("CRYSTALSTORM_DEV_ASSISTANT_DIR", OS.get_environment("TEMP").replace("\\", "/") + "/p7o_assistant")
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
	var da = get_first_node_in_group("developer_assistant")
	var player = get_first_node_in_group("player")
	var coord = get_first_node_in_group("dev_tools_coordinator")
	var insp = get_first_node_in_group("live_world_inspector")
	var world = get_first_node_in_group("world")
	if da == null or player == null:
		_fail("no assistant/player")
		_finish()
		return
	var r := ""
	r = _say(da, "/help")
	_check("help", "/give" in r and "/spawn" in r and "/debug" in r and "/kill" in r and "/seed" in r and "/god" in r and "/time" in r and "/heal" in r and "/tp" in r)
	r = _say(da, "/tp 1010 -940")
	_check("tp", absf(player.voxel_position.x - 1010.5) < 0.01 and absf(player.voxel_position.z + 939.5) < 0.01)
	for _f in 20:
		await process_frame
	var before: int = player.inventory.count_item("stone")
	r = _say(da, "/give stone 5")
	_check("give", player.inventory.count_item("stone") == before + 5)
	r = _say(da, "/give unobtainium 2")
	_check("give_unknown", "Unknown item" in r)
	player.health = 10.0
	r = _say(da, "/heal")
	_check("heal", is_equal_approx(player.health, player.max_health))
	r = _say(da, "/god on")
	player.take_damage(50.0, &"dev_test")
	_check("god_on", player.dev_god and is_equal_approx(player.health, player.max_health))
	r = _say(da, "/god off")
	for _f in 90:
		await process_frame
	player.take_damage(50.0, &"dev_test")
	_check("god_off", not player.dev_god and player.health < player.max_health)
	_say(da, "/heal")
	r = _say(da, "/time 2")
	_check("time_set", is_equal_approx(Engine.time_scale, 2.0) and "scale 2.00" in r)
	r = _say(da, "/time 1")
	_check("time_reset", is_equal_approx(Engine.time_scale, 1.0))
	var e0 := get_nodes_in_group("crystal_enemy").size()
	r = _say(da, "/spawn crystal_mite 3")
	await process_frame
	var e1 := get_nodes_in_group("crystal_enemy").size()
	_check("spawn_enemy", e1 - e0 == 3)
	var a0 := get_nodes_in_group("world_entity").size()
	r = _say(da, "/spawn deer 2")
	await process_frame
	var a1 := get_nodes_in_group("world_entity").size()
	_check("spawn_animal", a1 - a0 == 2)
	r = _say(da, "/spawn dragon")
	_check("spawn_unknown", "Unknown entity" in r)
	r = _say(da, "/kill all")
	for _f in 120:
		await process_frame
	var e2 := 0
	for e in get_nodes_in_group("crystal_enemy"):
		if not e.is_queued_for_deletion():
			e2 += 1
	print("P7_O kill_counts before=%d after_spawn=%d after_kill=%d" % [e0, e1, e2])
	_check("kill", "Killed %d" % e1 in r and e2 == 0)
	r = _say(da, "/seed")
	_check("seed", world != null and r == "Seed %d" % int(world.world_seed))
	r = _say(da, "/debug view on")
	_check("debug_view_on", coord.is_debug_view_visible() and insp.panel_open)
	r = _say(da, "/debug view off")
	_check("debug_view_off", not coord.is_debug_view_visible())
	r = _say(da, "/debug water_cells on")
	_check("debug_toggle_on", bool(insp.toggles["water_cells"]) and insp.panel_open)
	r = _say(da, "/debug water_cells off")
	_check("debug_toggle_off", not bool(insp.toggles["water_cells"]))
	r = _say(da, "/debug overlay on")
	_check("debug_overlay", coord.is_debug_overlay_visible())
	_say(da, "/debug overlay off")
	r = _say(da, "/debug sparkles")
	_check("debug_unknown", "Unknown toggle" in r)
	r = _say(da, "/frobnicate")
	_check("unknown_cmd", "Unknown command" in r and "/help" in r)
	r = _say(da, "hello assistant")
	_check("non_slash", "Sent to AI assistant" in r)
	_finish()


func _say(da, text: String) -> String:
	var r: String = da.send_message(text)
	print("P7_O > %s => %s" % [text, r.replace("\n", " | ")])
	return r


func _check(name: String, ok: bool) -> void:
	print("P7_O %s %s" % ["OK" if ok else "FAIL", name])
	if not ok:
		_fail(name)

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
		_ProbeExit.finish_tree(self, 0, "P7_O OK")
	else:
		_ProbeExit.finish_tree(self, 1, "P7_O FAILED %d" % _failed)
