extends SceneTree

const _PlayerSettings = preload("res://systems/player_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_PlayerSettings.settings_path = "user://verify_p7_fps_settings.json"
	if FileAccess.file_exists(_PlayerSettings.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_PlayerSettings.settings_path))
	var engine_before := Engine.max_fps
	var defs := _PlayerSettings.defaults()
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	var fresh := Engine.max_fps
	var d := _PlayerSettings.defaults()
	d["max_fps"] = 120
	_PlayerSettings.save_settings(d)
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	var set120 := Engine.max_fps
	d["max_fps"] = 77
	_PlayerSettings.save_settings(d)
	var bogus := int(_PlayerSettings.load_settings().get("max_fps", -1))
	_PlayerSettings.reset_all_to_defaults()
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	var after_reset := Engine.max_fps
	var ok: bool = int(defs.get("max_fps", -1)) == 60 and bool(defs.get("vsync", false)) and fresh == 60 and set120 == 120 and bogus == 60 and after_reset == 60
	print("P7_Q engine_start=%d default_max_fps=%s default_vsync=%s fresh=%d set120=%d bogus77->%d after_reset=%d %s" % [engine_before, str(defs.get("max_fps", "none")), str(defs.get("vsync")), fresh, set120, bogus, after_reset, "OK" if ok else "FAIL"])
	quit()