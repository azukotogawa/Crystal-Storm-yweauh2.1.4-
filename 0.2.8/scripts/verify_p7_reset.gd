extends SceneTree

const _PlayerSettings = preload("res://systems/player_settings.gd")
const _SettingsMenu = preload("res://ui/settings_menu.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const _TEST_PATH := "user://verify_p7_reset_settings.json"

var _fails: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _hash_tree(path: String, out: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		var full := path.path_join(f)
		if full == _TEST_PATH or full.get_file() == "player_settings.json":
			continue
		out[full] = FileAccess.get_sha256(full)
	for d in dir.get_directories():
		if d == "logs" or d == "shader_cache" or d == "vulkan":
			continue
		_hash_tree(path.path_join(d), out)


func _jump_key() -> int:
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey:
			return int((ev as InputEventKey).physical_keycode)
	return -1


func _run() -> void:
	await process_frame
	var old_path := _PlayerSettings.settings_path
	_PlayerSettings.settings_path = _TEST_PATH
	if FileAccess.file_exists(_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_PATH))
	var saves_before := {}
	_hash_tree("user://", saves_before)
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	var default_jump := _jump_key()
	var menu = _SettingsMenu.new()
	root.add_child(menu)
	await process_frame
	var changed := _PlayerSettings.defaults()
	changed["volume_master"] = 0.3
	changed["volume_music"] = 0.2
	changed["ui_scale"] = 1.25
	changed["reduce_motion"] = true
	changed["screen_shake_enabled"] = false
	changed["colorblind_palette"] = true
	changed["camera_cutaway_enabled"] = false
	changed["render_distance"] = 5
	changed["vegetation_scatter_multiplier"] = 0.4
	changed["texture_set"] = "batch1"
	changed["tutorial_completed"] = true
	_PlayerSettings.save_settings(changed)
	_PlayerSettings.bind_action("jump", _key(KEY_J))
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	menu.sync_from_settings()
	var pre := _PlayerSettings.load_settings()
	var differing := 0
	for k in _PlayerSettings.defaults().keys():
		if str(pre[k]) != str(_PlayerSettings.defaults()[k]):
			differing += 1
	if differing < 8:
		_fails.append("only %d settings changed" % differing)
	if _jump_key() != int(KEY_J):
		_fails.append("jump rebind not live")
	menu.visible = true
	await process_frame
	var blocked_open := _GameplayInput.blocks_world()
	if not blocked_open:
		_fails.append("settings open does not block world input")
	menu.request_reset_all()
	await process_frame
	var dlg := menu.find_child("ResetAllConfirm", true, false) as ConfirmationDialog
	var dlg_ok := dlg != null and dlg.visible and dlg.dialog_text == "Reset all settings to defaults?" and dlg.ok_button_text == "Yes" and dlg.cancel_button_text == "No"
	if not dlg_ok:
		_fails.append("confirm dialog missing or wrong")
	var unchanged := _PlayerSettings.load_settings()
	if float(unchanged["volume_master"]) != 0.3:
		_fails.append("reset happened before confirm")
	dlg.get_ok_button().pressed.emit()
	await process_frame
	await process_frame
	var defs := _PlayerSettings.defaults()
	defs["tutorial_completed"] = true
	var mem := {
		"volume_master": _PlayerSettings.volume_master, "volume_music": _PlayerSettings.volume_music,
		"volume_sfx": _PlayerSettings.volume_sfx, "volume_ui": _PlayerSettings.volume_ui,
		"ui_scale": _PlayerSettings.ui_scale, "reduce_motion": _PlayerSettings.reduce_motion,
		"screen_shake_enabled": _PlayerSettings.screen_shake_enabled, "hit_stop_enabled": _PlayerSettings.hit_stop_enabled,
		"flash_effects_enabled": _PlayerSettings.flash_effects_enabled, "hit_markers_enabled": _PlayerSettings.hit_markers_enabled,
		"crack_overlay_enabled": _PlayerSettings.crack_overlay_enabled, "colorblind_palette": _PlayerSettings.colorblind_palette,
		"fullscreen": _PlayerSettings.fullscreen, "vsync": _PlayerSettings.vsync_enabled, "resolution": _PlayerSettings.resolution,
		"camera_cutaway_enabled": _PlayerSettings.camera_cutaway_enabled, "camera_pitch_degrees": _PlayerSettings.camera_pitch_degrees,
		"texture_blueprint": _PlayerSettings.texture_blueprint, "texture_set": _PlayerSettings.texture_set,
		"keybinds": _PlayerSettings.keybinds, "control_profile": _PlayerSettings.control_profile,
		"tutorial_completed": _PlayerSettings.tutorial_completed,
	}
	var mem_bad := 0
	for k in mem.keys():
		if str(mem[k]) != str(defs[k]):
			mem_bad += 1
			_fails.append("memory %s=%s want %s" % [k, str(mem[k]), str(defs[k])])
	if _jump_key() != default_jump:
		mem_bad += 1
		_fails.append("live jump key %d want %d" % [_jump_key(), default_jump])
	var vol_ui = menu.find_child("VolumeMaster", true, false)
	var raw = JSON.parse_string(FileAccess.get_file_as_string(_TEST_PATH))
	var file_bad := 0
	if not raw is Dictionary:
		file_bad = 99
		_fails.append("saved file unreadable")
	else:
		for k in defs.keys():
			var rv = raw.get(k)
			var same := (float(rv) == float(defs[k])) if (defs[k] is int or defs[k] is float) else str(rv) == str(defs[k])
			if not same:
				file_bad += 1
				_fails.append("file %s=%s want %s" % [k, str(raw.get(k)), str(defs[k])])
	_PlayerSettings.volume_master = 0.0
	var reload := _PlayerSettings.load_settings()
	var reload_bad := 0
	for k in defs.keys():
		if str(reload[k]) != str(defs[k]):
			reload_bad += 1
			_fails.append("reload %s=%s want %s" % [k, str(reload[k]), str(defs[k])])
	var saves_after := {}
	_hash_tree("user://", saves_after)
	var save_bad := 0
	for k in saves_before.keys():
		if str(saves_after.get(k, "")) != str(saves_before[k]):
			save_bad += 1
			_fails.append("save file changed %s" % k)
	menu.visible = false
	await process_frame
	var released := not _GameplayInput.panel_open()
	if not released:
		_fails.append("settings close did not release panel block")
	print("P7_RESET differing_before=%d blocked_open=%s dialog=%s mem_bad=%d file_bad=%d reload_bad=%d saves_hashed=%d saves_changed=%d released=%s %s" % [
		differing, str(blocked_open), str(dlg_ok), mem_bad, file_bad, reload_bad, saves_before.size(), save_bad, str(released),
		"OK" if _fails.is_empty() else "FAIL"])
	for f in _fails:
		print("P7_RESETFAIL ", f)
	if FileAccess.file_exists(_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_PATH))
	_PlayerSettings.settings_path = old_path
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	quit(0 if _fails.is_empty() else 1)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e