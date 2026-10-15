extends SceneTree


const _PlayerSettings = preload("res://systems/player_settings.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")
const _SettingsMenu = preload("res://ui/settings_menu.gd")
const _Juice = preload("res://systems/juice.gd")
const _VfxPool = preload("res://systems/vfx_pool.gd")
const _CrystalPalette = preload("res://ui/crystal_palette.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")

const _TEST_PATH := "user://verify_ui_settings.json"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _run() -> void:
	await process_frame
	var old_path := _PlayerSettings.settings_path
	_PlayerSettings.settings_path = _TEST_PATH
	_delete_test_file()
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	_check_keybinds()
	await _check_audio_and_scale()
	_check_display()
	await _check_reduce_motion()
	_check_palette()
	_check_tutorial()
	_restore(old_path)
	if _failed:
		quit(1)
	else:
		print("All UI settings checks OK")
		quit(0)


func _check_keybinds() -> void:
	var jump := _key(KEY_J)
	var warning := _PlayerSettings.bind_action("jump", jump)
	if warning != "":
		_fail("rebinding jump to J reported a conflict: %s" % warning)
	_InputBindings.apply_saved({})
	if _physical("jump") != int(KEY_SPACE):
		_fail("empty apply_saved did not restore Space, got %d" % _physical("jump"))
	var display_calls := _PlayerSettings.display_apply_count
	var input_calls := _InputBindings.apply_saved_count
	_PlayerSettings.load_settings()
	if _PlayerSettings.display_apply_count != display_calls or _InputBindings.apply_saved_count != input_calls:
		_fail("load_settings called display or InputMap apply")
	if _physical("jump") != int(KEY_SPACE):
		_fail("load_settings changed the live jump bind, got %d" % _physical("jump"))
	_PlayerSettings.apply_runtime()
	if _physical("jump") != int(KEY_J):
		_fail("saved jump bind did not reload as J, got %d" % _physical("jump"))
	display_calls = _PlayerSettings.display_apply_count
	input_calls = _InputBindings.apply_saved_count
	_PlayerSettings.load_settings()
	_PlayerSettings.set_bus_volume("SFX", 0.4)
	if _PlayerSettings.display_apply_count != display_calls or _InputBindings.apply_saved_count != input_calls:
		_fail("load_settings/set_bus_volume called display or InputMap apply (%d -> %d display, %d -> %d input)" % [
			display_calls, _PlayerSettings.display_apply_count, input_calls, _InputBindings.apply_saved_count
		])
	if _physical("jump") != int(KEY_J):
		_fail("volume save cleared the jump bind, got %d" % _physical("jump"))
	var conflict := _PlayerSettings.bind_action("move_left", _key(KEY_W))
	if conflict == "":
		_fail("rebinding move_left to W did not warn")
	if _physical("move_left") != int(KEY_A):
		_fail("conflicted move_left bind changed the key, got %d" % _physical("move_left"))
	_PlayerSettings.reset_bindings()
	if _physical("jump") != int(KEY_SPACE):
		_fail("reset did not restore Space jump, got %d" % _physical("jump"))
	if _physical("move_forward") != int(KEY_W) or _physical("move_left") != int(KEY_A):
		_fail("reset did not restore WASD")
	if _physical("move_back") != int(KEY_S) or _physical("move_right") != int(KEY_D):
		_fail("reset did not restore S/D")
	if _physical("rotate_left") != int(KEY_Q) or _physical("rotate_right") != int(KEY_E):
		_fail("reset did not restore Q/E yaw")


func _check_audio_and_scale() -> void:
	var menu := _SettingsMenu.new()
	root.add_child(menu)
	await process_frame
	if menu.get_node_or_null("ConflictWarning") == null and menu.find_child("ConflictWarning", true, false) == null:
		_fail("settings menu has no ConflictWarning label")
	menu.set_volume("SFX", 0.35)
	var audio := root.get_node_or_null("AudioManager")
	if audio == null or not audio.has_method("get_bus_linear"):
		_fail("AudioManager missing")
	elif absf(float(audio.get_bus_linear("SFX")) - 0.35) > 0.02:
		_fail("SFX slider did not set the bus (got %.3f)" % float(audio.get_bus_linear("SFX")))
	var loaded := _PlayerSettings.load_settings()
	if absf(float(loaded.get("volume_sfx", 1.0)) - 0.35) > 0.02:
		_fail("SFX volume did not persist")
	menu.set_ui_scale(1.25)
	if absf(_PlayerSettings.ui_scale - 1.25) > 0.001:
		_fail("UI scale static is %.3f, want 1.25" % _PlayerSettings.ui_scale)
	if absf(root.content_scale_factor - 1.25) > 0.001:
		_fail("content_scale_factor is %.3f, want 1.25" % root.content_scale_factor)
	loaded = _PlayerSettings.load_settings()
	if absf(float(loaded.get("ui_scale", 1.0)) - 1.25) > 0.001:
		_fail("ui_scale did not persist")
	if absf(root.content_scale_factor - 1.25) > 0.001:
		_fail("reload cleared content_scale_factor")
	menu.queue_free()


func _check_display() -> void:
	var data := _PlayerSettings.load_settings()
	data["fullscreen"] = true
	data["vsync"] = false
	data["resolution"] = "1920x1080"
	if not _PlayerSettings.save_settings(data):
		_fail("display save failed")
		return
	var loaded := _PlayerSettings.load_settings()
	if not bool(loaded.get("fullscreen", false)) or not _PlayerSettings.fullscreen:
		_fail("fullscreen did not persist")
	if bool(loaded.get("vsync", true)) or _PlayerSettings.vsync_enabled:
		_fail("vsync off did not persist")
	if str(loaded.get("resolution", "")) != "1920x1080" or _PlayerSettings.resolution != "1920x1080":
		_fail("resolution did not persist")
	data = loaded
	data["fullscreen"] = false
	data["vsync"] = true
	data["resolution"] = "1280x720"
	_PlayerSettings.save_settings(data)


func _check_reduce_motion() -> void:
	var data := _PlayerSettings.load_settings()
	data["reduce_motion"] = true
	data["screen_shake_enabled"] = true
	data["hit_stop_enabled"] = true
	data["flash_effects_enabled"] = true
	if not _PlayerSettings.save_settings(data):
		_fail("reduce_motion save failed")
		return
	if not _PlayerSettings.reduce_motion:
		_fail("reduce_motion did not load")
	if not _PlayerSettings.hit_stop_enabled or not _PlayerSettings.screen_shake_enabled:
		_fail("reduce_motion save cleared the M5 toggles")
	Engine.time_scale = 1.0
	_Juice.clear_shake()
	if _Juice.request_hit_stop(0.04, self, true):
		_fail("hit-stop ran while reduce motion is on")
	if absf(Engine.time_scale - 1.0) > 0.001:
		_fail("reduce-motion hit-stop changed time_scale")
		Engine.time_scale = 1.0
	_Juice.request_shake(0.5, true)
	if _Juice.shake_offset(0.0).length() > 0.0001:
		_fail("shake offset while reduce motion is on")
	_Juice.clear_shake()
	if _Juice.walk_bob_allowed():
		_fail("walk bob allowed while reduce motion is on")
	var pool := _VfxPool.new()
	root.add_child(pool)
	await process_frame
	if pool.burst(_VfxPool.Kind.SHATTER, Vector3.ZERO):
		_fail("shatter burst ran while reduce motion is on")
	if not pool.burst(_VfxPool.Kind.DUST, Vector3(1, 0, 0)):
		_fail("dust burst was suppressed by reduce motion")
	pool.queue_free()
	data = _PlayerSettings.load_settings()
	data["reduce_motion"] = false
	_PlayerSettings.save_settings(data)
	if _PlayerSettings.reduce_motion:
		_fail("reduce_motion stayed on after restore")
	Engine.time_scale = 1.0
	_Juice.clear_shake()


func _check_palette() -> void:
	var plain := StandardMaterial3D.new()
	var marked := StandardMaterial3D.new()
	_CrystalPalette.paint_mass(plain, false)
	var default_mass := plain.albedo_color
	_CrystalPalette.paint_mass(plain, true)
	var alt_mass := plain.albedo_color
	_CrystalPalette.paint_marker(marked, true)
	if default_mass.is_equal_approx(alt_mass):
		_fail("colour-blind mass albedo matches the default")
	var mass_l := _CrystalPalette.luminance(alt_mass)
	var marker_l := _CrystalPalette.luminance(marked.albedo_color)
	if absf(mass_l - marker_l) < 0.15:
		_fail("colour-blind mass and marker luminance are too close (%.3f vs %.3f)" % [mass_l, marker_l])
	if _CrystalPalette.luminance(default_mass) >= mass_l:
		_fail("colour-blind mass is not brighter than the default mass")
	var crystal := _CrystalManager.new()
	crystal._crystal_material = StandardMaterial3D.new()
	crystal._marker_material = StandardMaterial3D.new()
	crystal.apply_color_palette(false)
	var before: Color = crystal._crystal_material.albedo_color
	crystal.apply_color_palette(true)
	var after: Color = crystal._crystal_material.albedo_color
	if before.is_equal_approx(after):
		_fail("CrystalManager.apply_color_palette did not recolour the mass")
	var marker_after: Color = crystal._marker_material.albedo_color
	if absf(_CrystalPalette.luminance(after) - _CrystalPalette.luminance(marker_after)) < 0.15:
		_fail("live colour-blind mass and marker luminance are too close")
	crystal.free()
	var data := _PlayerSettings.load_settings()
	data["colorblind_palette"] = true
	_PlayerSettings.save_settings(data)
	var loaded := _PlayerSettings.load_settings()
	if not bool(loaded.get("colorblind_palette", false)) or not _PlayerSettings.colorblind_palette:
		_fail("colorblind_palette did not persist")
	data = loaded
	data["colorblind_palette"] = false
	_PlayerSettings.save_settings(data)


func _check_tutorial() -> void:
	_PlayerSettings.set_tutorial_completed(false)
	if not _Tutorial.wants_tutorial():
		_fail("tutorial wanted to stay hidden before the flag is set")
	if _Tutorial.should_show():
		_fail("tutorial should_show is true in headless")
	_PlayerSettings.set_tutorial_completed(true)
	var loaded := _PlayerSettings.load_settings()
	if not bool(loaded.get("tutorial_completed", false)) or not _PlayerSettings.tutorial_completed:
		_fail("tutorial_completed did not persist")
	if _Tutorial.wants_tutorial():
		_fail("tutorial still wants to show after the flag is set")
	_PlayerSettings.set_tutorial_completed(false)
	if not _Tutorial.wants_tutorial():
		_fail("clearing tutorial_completed did not restore wants_tutorial")


func _restore(old_path: String) -> void:
	Engine.time_scale = 1.0
	_Juice.clear_shake()
	_PlayerSettings.reduce_motion = false
	_PlayerSettings.colorblind_palette = false
	_PlayerSettings.hit_stop_enabled = true
	_PlayerSettings.screen_shake_enabled = true
	_delete_test_file()
	_PlayerSettings.settings_path = old_path
	_PlayerSettings.load_settings()
	_PlayerSettings.apply_runtime()
	var audio := root.get_node_or_null("AudioManager")
	if audio and audio.has_method("apply_saved_volumes"):
		audio.apply_saved_volumes()


func _delete_test_file() -> void:
	if FileAccess.file_exists(_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_PATH))


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	return ev


func _physical(action: String) -> int:
	if not InputMap.has_action(action):
		return -1
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var key := ev as InputEventKey
			if key.physical_keycode != 0:
				return int(key.physical_keycode)
			return int(key.keycode)
	return -1
