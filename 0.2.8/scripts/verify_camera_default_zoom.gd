extends SceneTree
## Default ortho zoom is closer than the old 24. Wheel limits, the rig, and iso pitch stay.

const _PlayerSettings = preload("res://systems/player_settings.gd")

const OLD_ZOOM := 24.0
const SETTINGS := "user://verify_camera_default_zoom.json"

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_PlayerSettings.settings_path = SETTINGS
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	_PlayerSettings.load_settings()
	var cam: Camera3D = Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	root.add_child(cam)
	await process_frame
	_check_default(cam)
	_check_wheel(cam)
	_check_rig(cam)
	_check_scene_leaves_zoom()
	_check_tick()
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	if _failed == 0:
		print("All camera default zoom tests OK")
		quit(0)
	else:
		push_error("verify_camera_default_zoom: %d failure(s)" % _failed)
		quit(1)


func _check_default(cam: Camera3D) -> void:
	var zoom := float(cam.zoom_level)
	var closer := (OLD_ZOOM - zoom) / OLD_ZOOM
	if cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
		_fail("camera is not orthographic")
	elif absf(zoom - 16.0) > 0.001:
		_fail("default zoom %.2f want 16" % zoom)
	elif absf(cam.size - zoom) > 0.001:
		_fail("ortho size %.2f does not match zoom %.2f" % [cam.size, zoom])
	elif closer < 0.30 or closer > 0.40:
		_fail("size 16 should sit in the 30-40%% closer band versus 24, got %.0f%%" % (closer * 100.0))
	elif absf(float(cam.MIN_ZOOM) - 8.0) > 0.001 or absf(float(cam.MAX_ZOOM) - 140.0) > 0.001:
		_fail("wheel limits changed")
	elif absf(float(cam.ZOOM_STEP) - 2.0) > 0.001:
		_fail("zoom step changed")
	else:
		print("OK default ortho size %.1f is %.0f%% closer than %.0f" % [zoom, closer * 100.0, OLD_ZOOM])


func _wheel(cam: Camera3D, button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	cam._input(ev)


func _check_wheel(cam: Camera3D) -> void:
	_wheel(cam, MOUSE_BUTTON_WHEEL_UP)
	if absf(float(cam.zoom_level) - 14.0) > 0.001 or absf(cam.size - 14.0) > 0.001:
		_fail("wheel up from default want 14 got zoom %.2f size %.2f" % [float(cam.zoom_level), cam.size])
		return
	_wheel(cam, MOUSE_BUTTON_WHEEL_DOWN)
	if absf(float(cam.zoom_level) - 16.0) > 0.001:
		_fail("wheel down did not return to 16")
		return
	cam.zoom_level = float(cam.MIN_ZOOM)
	cam.size = float(cam.zoom_level)
	_wheel(cam, MOUSE_BUTTON_WHEEL_UP)
	if absf(float(cam.zoom_level) - float(cam.MIN_ZOOM)) > 0.001:
		_fail("zoom passed the close clamp")
		return
	cam.zoom_level = float(cam.MAX_ZOOM)
	cam.size = float(cam.zoom_level)
	_wheel(cam, MOUSE_BUTTON_WHEEL_DOWN)
	if absf(float(cam.zoom_level) - float(cam.MAX_ZOOM)) > 0.001:
		_fail("zoom passed the far clamp")
	else:
		print("OK wheel step 2 clamps at 8 and 140")


func _check_rig(cam: Camera3D) -> void:
	if absf(float(cam.distance) - 100.0) > 0.001 or absf(float(cam.height_offset) - 101.0) > 0.001:
		_fail("camera rig distance or height changed")
	elif absf(float(cam.pitch_degrees) - float(cam.ISO_PITCH_DEG)) > 0.02:
		_fail("default pitch drifted to %.3f" % float(cam.pitch_degrees))
	else:
		print("OK rig distance 100 height 101 iso pitch unchanged")


func _check_scene_leaves_zoom() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var at := text.find("[node name=\"Camera3D\"")
	if at < 0:
		_fail("main scene has no Camera3D")
		return
	var end := text.find("\n[node ", at + 10)
	var block := text.substr(at, (end - at) if end > at else (text.length() - at))
	if "zoom_level" in block or "size =" in block:
		_fail("main scene overrides the camera zoom")
	else:
		print("OK main scene leaves the default zoom to the camera script")


func _check_tick() -> void:
	var proj := FileAccess.get_file_as_string("res://project.godot")
	if proj.contains("physics_ticks_per_second=") and not proj.contains("physics_ticks_per_second=60"):
		_fail("physics tick is not the 60 Hz default")
	else:
		print("OK physics tick stays 60")
