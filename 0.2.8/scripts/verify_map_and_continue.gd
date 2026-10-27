extends SceneTree

const _GI = preload("res://helpers/gameplay_input.gd")
const _SG = preload("res://systems/save_game_service.gd")
const _WM = preload("res://systems/world_manager.gd")

const PLAYABLE_SEC := 120.0
const MAP_TEX_SEC := 15.0

var _failed := 0
var _t0 := 0


func _init() -> void:
	call_deferred("_run")


func _g(group: String) -> Node:
	return root.get_tree().get_first_node_in_group(group)


func _log(msg: String) -> void:
	print("[%.1fs] %s" % [float(Time.get_ticks_msec() - _t0) / 1000.0, msg])


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _ok(msg: String) -> void:
	_log("OK " + msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press_map() -> void:
	Input.action_press("toggle_map")
	await process_frame
	Input.action_release("toggle_map")
	await process_frame


func _playable() -> bool:
	var pl := _g("player")
	var sv := _g("save_game_service")
	return pl != null and bool(pl.get("world_ready")) and not _GI.world_loading \
		and (sv == null or not sv.is_transaction_active()) and not _SG.pending_continue


func _wait_until_loaded(label: String) -> bool:
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < PLAYABLE_SEC:
		if current_scene != null and current_scene.name == "Game" and not _GI.world_loading and _g("topographical_map") != null:
			return true
		await process_frame
	_fail("%s: loading screen never cleared" % label)
	return false


func _wait_playable(label: String) -> bool:
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < PLAYABLE_SEC:
		if _playable():
			_ok("%s playable after %.1fs" % [label, float(Time.get_ticks_msec() - start) / 1000.0])
			return true
		await process_frame
	var pl := _g("player")
	var sv := _g("save_game_service")
	_fail("%s softlock: world_ready=%s save_stage=%s" % [
		label, str(pl.get("world_ready")) if pl else "-", str(sv.get_transaction_stage()) if sv else "-"])
	return false


func _check_map(label: String) -> void:
	var m := _g("topographical_map")
	if m == null:
		_fail("%s: no map" % label)
		return
	if m.is_fullscreen_open():
		await _press_map()
	await _press_map()
	if not m.is_fullscreen_open():
		_fail("%s: M did not open the map" % label)
		return
	var start := Time.get_ticks_msec()
	var rect: TextureRect = m.get("_fullscreen_rect")
	while float(Time.get_ticks_msec() - start) / 1000.0 < MAP_TEX_SEC:
		if rect != null and rect.texture != null and rect.is_visible_in_tree():
			break
		await process_frame
	if rect == null or rect.texture == null or not rect.is_visible_in_tree():
		_fail("%s: map opened but showed no picture in %.0fs" % [label, MAP_TEX_SEC])
	else:
		_ok("%s map shown after %.2fs" % [label, float(Time.get_ticks_msec() - start) / 1000.0])
	await _press_map()
	if m.is_fullscreen_open():
		_fail("%s: M did not close the map" % label)


func _to_menu() -> void:
	var game := _g("game")
	game.return_to_world_select()
	await _frames(30)


func _menu_continue(label: String, expect_launch: bool) -> bool:
	if current_scene == null or current_scene.name != "Frontend":
		_fail("%s: not at the menu" % label)
		return false
	var fr := current_scene
	fr._show(0)
	await process_frame
	fr._on_continue()
	await _frames(20)
	if not expect_launch:
		var status: Label = fr.find_child("Status", true, false)
		if current_scene != fr:
			_fail("%s: Continue left the menu" % label)
		elif status == null or status.text.strip_edges().is_empty():
			_fail("%s: no message on the menu" % label)
		else:
			_ok("%s stays at menu: %s" % [label, status.text])
		return false
	return true


func _write_continue(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var f := FileAccess.open(_SG.continue_save_path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	if not OS.get_user_data_dir().contains("verify-evidence") and OS.get_environment("CS_VERIFY_SANDBOX") != "1":
		push_error("refusing: run with APPDATA pointed at a sandbox so real saves stay untouched")
		quit(2)
		return
	_WM.start_fresh_run()
	change_scene_to_file("res://scenes/main.tscn")
	if await _wait_until_loaded("new game"):
		await _check_map("right after boot")
		var cm := _g("chunk_manager")
		await _check_map("mid chunk load (chunks=%d)" % (cm.chunks.size() if cm else -1))
	if await _wait_playable("new game"):
		await _check_map("after new game")
	await _frames(60)
	var sv := _g("save_game_service")
	if sv.save_alive_session(true) != OK:
		_fail("could not save the alive session")
	var saved_text := FileAccess.get_file_as_string(_SG.continue_save_path())
	await _to_menu()

	if await _menu_continue("continue", true):
		if await _wait_until_loaded("continue"):
			await _check_map("during continue load")
		if await _wait_playable("continue"):
			await _check_map("after continue")
		await _to_menu()

	_SG.clear_continue()
	await _menu_continue("missing continue.json", false)
	_write_continue("{ not json")
	await _menu_continue("corrupt continue.json", false)
	_write_continue("")
	await _menu_continue("empty continue.json", false)

	var data = JSON.parse_string(saved_text)
	if data is Dictionary:
		data["world_id"] = "gone_world"
		_write_continue(JSON.stringify(data))
		if not _SG.has_continue():
			await _menu_continue("stale continue.json", false)
		elif await _menu_continue("stale continue.json", true):
			if await _wait_until_loaded("stale continue"):
				if await _wait_playable("stale continue"):
					await _check_map("after stale continue")
			await _to_menu()
	else:
		_fail("saved continue was not json")

	_write_continue(saved_text)
	sv = null
	_WM.wipe_worlds()
	if _SG.has_continue() or FileAccess.file_exists(_SG.continue_save_path()):
		_fail("wipe left continue.json behind")
	else:
		_ok("wipe removes continue.json")
	var dir := DirAccess.open("user://saves")
	var left := 0
	if dir:
		for file in dir.get_files():
			if file.begins_with("world_"):
				left += 1
	if left > 0:
		_fail("wipe left %d world saves behind" % left)
	else:
		_ok("wipe removes world saves")

	if _failed > 0:
		print("verify_map_and_continue FAILED %d" % _failed)
		quit(1)
		return
	print("All map and continue tests OK")
	quit(0)
