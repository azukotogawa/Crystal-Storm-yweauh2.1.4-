extends SceneTree

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _run() -> void:
	var body := Node3D.new()
	body.add_to_group("player")
	root.add_child(body)
	var cam: Camera3D = Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	root.add_child(cam)
	await process_frame
	var yaw0: float = cam.yaw_target_degrees
	var pitch0: float = cam.pitch_target_degrees
	var zoom0: float = cam.zoom_level

	_key(KEY_E, true)
	await process_frame
	await process_frame
	_key(KEY_E, false)
	for i in 90:
		await process_frame
	var dy := fposmod(cam.yaw_degrees - yaw0 + 180.0, 360.0) - 180.0
	if absf(dy - 90.0) > 1.0:
		_fail("tap E yaw %.2f want 90" % dy)

	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(0, 40)
	mv.alt_pressed = true
	cam._input(mv)
	for i in 30:
		await process_frame
	if absf(cam.pitch_degrees - pitch0) < 1.0:
		_fail("alt pointer did not change pitch")

	_key(KEY_EQUAL, true)
	_key(KEY_EQUAL, false)
	if cam.zoom_level >= zoom0:
		_fail("= did not zoom in")
	_key(KEY_HOME, true)
	_key(KEY_HOME, false)
	for i in 90:
		await process_frame
	if absf(cam.zoom_level - zoom0) > 0.01 or absf(cam.size - zoom0) > 0.01:
		_fail("Home zoom %.2f want %.2f" % [cam.zoom_level, zoom0])
	if absf(cam.pitch_degrees - pitch0) > 0.5:
		_fail("Home pitch not restored")
	if absf(fposmod(cam.yaw_degrees - yaw0 + 180.0, 360.0) - 180.0) > 0.5:
		_fail("Home yaw not restored")

	if _failed == 0:
		print("All camera controls OK")
		quit(0)
	else:
		quit(1)
