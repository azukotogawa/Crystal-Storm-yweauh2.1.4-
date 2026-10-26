extends SceneTree

const _Inventory = preload("res://inventory/inventory.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _key(code: int, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.shift_pressed = shift
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _wheel(up: bool, ctrl: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var up_ev := ev.duplicate() as InputEventMouseButton
	up_ev.pressed = false
	Input.parse_input_event(up_ev)


func _release_all() -> void:
	for code in [KEY_1, KEY_2, KEY_3, KEY_0, KEY_PERIOD, KEY_COMMA]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		ev.keycode = code as Key
		ev.pressed = false
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _expect(w: Node, want: int, label: String) -> void:
	await process_frame
	await process_frame
	_release_all()
	await process_frame
	if w.get_active_hotbar_index() != want:
		_fail("%s hotbar %d want %d" % [label, w.get_active_hotbar_index(), want])


func _run() -> void:
	if _Inventory.HOTBAR_SIZE != 10:
		_fail("hotbar size %d" % _Inventory.HOTBAR_SIZE)
	var cam := Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	root.add_child(cam)
	var w := Node.new()
	w.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(w)
	w.inventory = _Inventory.new()
	await process_frame
	var zoom0: float = cam.zoom_level

	_key(KEY_3)
	await _expect(w, 2, "key 3")
	_key(KEY_0)
	await _expect(w, 9, "key 0")
	_wheel(false)
	await _expect(w, 0, "wheel down wraps to 1")
	_wheel(true)
	await _expect(w, 9, "wheel up wraps to 10")
	_key(KEY_PERIOD)
	await _expect(w, 0, "period wraps")
	_key(KEY_COMMA)
	await _expect(w, 9, "comma wraps")
	_key(KEY_2, true)
	await _expect(w, 9, "shift+2 keeps slot")
	if absf(cam.zoom_level - zoom0) > 0.001:
		_fail("plain wheel zoomed")
	_wheel(true, true)
	await process_frame
	if cam.zoom_level >= zoom0:
		_fail("ctrl+wheel did not zoom")

	if _failed == 0:
		print("All hotbar controls OK")
		quit(0)
	else:
		quit(1)
