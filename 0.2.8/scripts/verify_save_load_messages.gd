extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _SGS = preload("res://systems/save_game_service.gd")
const TEST_SLOT := 17
const SENTINEL := "{\"sentinel\": \"previous save\"}"

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("OK " + msg)
	else:
		_failed += 1
		print("FAIL " + msg)


func _toast_text() -> String:
	for overlay in get_nodes_in_group("game_overlay"):
		var lbl = overlay.find_child("ToastLabel", true, false)
		if lbl:
			print("TOAST %s visible=%s text='%s'" % [overlay.get_path(), lbl.visible, lbl.text])
			if lbl.visible:
				return str(lbl.text)
	return ""


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	var game: Node = packed.instantiate()
	root.add_child(game)
	var svc = null
	for _i in 600:
		svc = get_first_node_in_group("save_game_service")
		if svc and get_first_node_in_group("game_overlay"):
			break
		await process_frame
	if svc == null:
		print("FAIL boot timeout")
		quit(1)
		return
	if svc.config:
		svc.config.auto_save_enabled = false
	for _w in 30:
		await process_frame

	var path: String = svc.slot_path(TEST_SLOT)
	var tmp_abs := ProjectSettings.globalize_path(path + ".tmp")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(SENTINEL)
	f.close()
	DirAccess.make_dir_recursive_absolute(tmp_abs)
	var err: int = svc.save_slot(TEST_SLOT, true)
	_check(err != OK, "forced save failure returns error (%d)" % err)
	_check(svc.last_player_message == _SGS.MSG_SAVE_FAILED, "save failure message set: '%s'" % svc.last_player_message)
	_check(_toast_text() == _SGS.MSG_SAVE_FAILED, "save failure toast visible: '%s'" % _toast_text())
	_check(FileAccess.get_file_as_string(path) == SENTINEL, "previous save untouched")
	DirAccess.remove_absolute(tmp_abs)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	svc.last_player_message = ""
	var ok: bool = await svc.load_slot(TEST_SLOT)
	_check(not ok, "load of missing slot fails")
	_check(svc.last_player_message == _SGS.MSG_LOAD_MISSING, "missing load message: '%s'" % svc.last_player_message)

	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("{\"not\": \"a save\"}")
	bad.close()
	svc.last_player_message = ""
	ok = await svc.load_slot(TEST_SLOT)
	_check(not ok, "load of corrupt slot fails")
	_check(svc.last_player_message == _SGS.MSG_LOAD_FAILED, "corrupt load message: '%s'" % svc.last_player_message)
	_check(_toast_text() == _SGS.MSG_LOAD_FAILED, "corrupt load toast visible: '%s'" % _toast_text())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	if _failed == 0:
		print("All save load message tests OK")
		quit(0)
	else:
		print("save load message tests failed: %d" % _failed)
		quit(1)
