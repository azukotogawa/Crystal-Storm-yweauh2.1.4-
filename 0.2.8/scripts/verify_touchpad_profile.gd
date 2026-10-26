extends SceneTree

const _Inventory = preload("res://inventory/inventory.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _Camera = preload("res://player/camera.gd")
const SETTINGS := "user://verify_touchpad_profile.json"

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _key(code: int, pressed: bool, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.shift_pressed = shift
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _wheel(up: bool, factor: float = 1.0) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.factor = factor
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var up_ev := ev.duplicate() as InputEventMouseButton
	up_ev.pressed = false
	Input.parse_input_event(up_ev)
	Input.flush_buffered_events()


func _settle() -> void:
	await process_frame
	await process_frame


func _run() -> void:
	_PlayerSettings.settings_path = SETTINGS
	_PlayerSettings.set_control_profile("standard")
	var cam := Camera3D.new()
	cam.set_script(_Camera)
	root.add_child(cam)
	var w := Node.new()
	w.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(w)
	w.inventory = _Inventory.new()
	await _settle()

	var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in digits.size():
		_key(digits[i], true)
		await _settle()
		_key(digits[i], false)
		if w.get_active_hotbar_index() != i:
			_fail("digit slot %d got %d" % [i + 1, w.get_active_hotbar_index()])
	_key(KEY_3, true)
	await _settle()
	_key(KEY_3, false)
	_key(KEY_1, true, true)
	await _settle()
	_key(KEY_1, false, true)
	if w.get_active_hotbar_index() != 2:
		_fail("Shift+1 changed slot to %d" % w.get_active_hotbar_index())

	var z0: float = cam.zoom_level
	_wheel(false)
	await _settle()
	if w.get_active_hotbar_index() != 3:
		_fail("standard wheel down slot %d want 3" % w.get_active_hotbar_index())
	if absf(cam.zoom_level - z0) > 0.001:
		_fail("standard wheel zoomed")

	_PlayerSettings.set_control_profile("laptop")
	await _settle()
	var slot: int = w.get_active_hotbar_index()
	_wheel(true)
	await _settle()
	if cam.zoom_level >= z0:
		_fail("laptop wheel up did not zoom in")
	var z1: float = cam.zoom_level
	_wheel(false)
	await _settle()
	if cam.zoom_level <= z1:
		_fail("laptop wheel down did not zoom out")
	if w.get_active_hotbar_index() != slot:
		_fail("laptop wheel changed hotbar to %d" % w.get_active_hotbar_index())
	_key(KEY_PERIOD, true)
	await _settle()
	_key(KEY_PERIOD, false)
	if w.get_active_hotbar_index() != (slot + 1) % 10:
		_fail("laptop period did not step hotbar")

	_PlayerSettings.set_control_profile("standard")
	cam.zoom_level = z0
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 4)
	cam._input(pan)
	if _PlayerSettings.control_profile != "laptop":
		_fail("pan gesture did not switch to laptop")
	if cam.zoom_level <= z0:
		_fail("pan down did not zoom out")
	pan.delta = Vector2(0, -400)
	cam._input(pan)
	if absf(cam.zoom_level - _Camera.MIN_ZOOM) > 0.001:
		_fail("pan zoom not clamped to MIN_ZOOM")

	_PlayerSettings.set_control_profile("standard")
	await _settle()
	slot = w.get_active_hotbar_index()
	cam.zoom_level = z0
	_wheel(true, 0.25)
	await _settle()
	if _PlayerSettings.control_profile != "laptop":
		_fail("fractional wheel did not switch to laptop")
	if cam.zoom_level >= z0:
		_fail("fractional wheel did not zoom")
	z1 = cam.zoom_level
	_wheel(true, 0.25)
	await _settle()
	if cam.zoom_level >= z1:
		_fail("second fractional wheel did not zoom")
	if w.get_active_hotbar_index() != (slot + 9) % 10 and w.get_active_hotbar_index() != slot:
		_fail("touchpad wheel moved hotbar more than the switch event")
	var after_switch: int = w.get_active_hotbar_index()
	_wheel(true, 0.25)
	await _settle()
	if w.get_active_hotbar_index() != after_switch:
		_fail("touchpad wheel changed hotbar after switch")

	var menu = load("res://ui/settings_menu.gd").new()
	root.add_child(menu)
	await _settle()
	if menu.has_method("sync_from_settings"):
		menu.sync_from_settings()
	var picker = menu.get("_profile")
	if picker == null:
		_fail("settings menu has no profile picker")
	else:
		if picker.selected != _PlayerSettings.PROFILES.find("laptop"):
			_fail("settings picker shows %d not laptop" % picker.selected)
		menu._on_profile_selected(_PlayerSettings.PROFILES.find("standard"))
		if _PlayerSettings.control_profile != "standard":
			_fail("settings picker did not switch back to standard")
	slot = w.get_active_hotbar_index()
	_wheel(false)
	await _settle()
	if w.get_active_hotbar_index() == slot:
		_fail("standard wheel after switch back did not change hotbar")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	if _failed == 0:
		print("All touchpad profile checks OK")
		quit(0)
	else:
		quit(1)