extends SceneTree
## Live camera: continuous 360° yaw, hold-to-rotate, isometric pitch/zoom preserved.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const ISO_PITCH := -35.264


var _failed: int = 0
var _scratch: String = ""


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-b4e8bbc86472/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 6:
		await process_frame

	var player = get_first_node_in_group("player")
	var cam: Camera3D = player.get("camera") if player else null
	if cam == null:
		cam = get_first_node_in_group("camera")
	if cam == null or player == null:
		_fail("missing player/camera")
		_finish()
		return

	cam.set("use_smoothing", false)
	if not ("yaw_degrees" in cam) or not ("yaw_target_degrees" in cam):
		_fail("camera missing continuous yaw fields")
		_finish()
		return

	# Pitch + zoom contract.
	if absf(cam.rotation_degrees.x - ISO_PITCH) > 0.05:
		_fail("pitch want %.3f got %.3f" % [ISO_PITCH, cam.rotation_degrees.x])
	else:
		_ok("pitch isometric %.3f" % cam.rotation_degrees.x)
	if absf(cam.size - float(cam.zoom_level)) > 0.05:
		_fail("zoom size %.2f != zoom_level %.2f" % [cam.size, float(cam.zoom_level)])
	else:
		_ok("zoom maps to orthogonal size %.1f" % cam.size)

	# Continuous snap, not mod-4.
	if cam.has_method("snap_yaw_degrees"):
		cam.snap_yaw_degrees(22.0)
	else:
		cam.yaw_degrees = 22.0
		cam.yaw_target_degrees = 22.0
		if cam.has_method("_update_camera_transform"):
			cam._update_camera_transform()
	await process_frame
	if absf(cam.rotation_degrees.y - 22.0) > 0.15:
		_fail("snap 22° camera yaw got %.3f" % cam.rotation_degrees.y)
	else:
		_ok("yaw is continuous (22°)")
	if absf(cam.rotation_degrees.x - ISO_PITCH) > 0.05:
		_fail("pitch drifted after yaw snap")

	# Offset is a single isometric formula (no even/odd branches).
	var src := (load("res://player/camera.gd") as GDScript).source_code
	if "orbit_rotation % 2" in src or "orbit_rotation == 1" in src:
		_fail("get_offset_from_rotation still has even/odd orbit branches")
	else:
		_ok("single isometric offset (no even/odd)")
	var off22: Vector3 = cam.get_offset_from_rotation()
	cam.snap_yaw_degrees(45.0)
	var off45: Vector3 = cam.get_offset_from_rotation()
	if off22.is_equal_approx(off45):
		_fail("offset must change with yaw")
	elif absf(off22.y - off45.y) > 0.01:
		_fail("height_offset must stay constant across yaw")
	else:
		_ok("offset y constant, xz follows yaw")

	# Tap must not jump 90°.
	cam.snap_yaw_degrees(45.0)
	cam.set("use_smoothing", false)
	Input.action_press("rotate_right")
	await process_frame
	Input.action_release("rotate_right")
	await process_frame
	var after_tap: float = float(cam.yaw_target_degrees)
	var tap_delta: float = absf(after_tap - 45.0)
	if tap_delta > 20.0:
		_fail("tap jumped yaw by %.2f (want hold-to-rotate, not 90° snap)" % tap_delta)
	else:
		_ok("tap does not snap 90° (delta=%.2f)" % tap_delta)

	# Hold rotate_right moves yaw continuously over time.
	cam.snap_yaw_degrees(10.0)
	cam.set("use_smoothing", false)
	Input.action_press("rotate_right")
	var samples: Array = []
	for _i in 20:
		await process_frame
		samples.append(float(cam.yaw_target_degrees))
	Input.action_release("rotate_right")
	var moved: float = float(samples[samples.size() - 1]) - float(samples[0])
	var jumps := 0
	for i in range(1, samples.size()):
		if absf(float(samples[i]) - float(samples[i - 1])) > 40.0:
			jumps += 1
	if moved < 5.0:
		_fail("hold rotate_right did not accumulate yaw (moved=%.2f)" % moved)
	elif jumps > 0:
		_fail("hold rotate snapped %d times" % jumps)
	else:
		_ok("hold rotate_right accumulated %.2f° with no 90° jumps" % moved)

	# Movement basis follows continuous yaw (not 4-state).
	if player.has_method("rotate_input_to_world"):
		var a: Vector2 = player.rotate_input_to_world(Vector2(0, -1), 22.0)
		var b: Vector2 = player.rotate_input_to_world(Vector2(0, -1), 45.0)
		var c: Vector2 = player.rotate_input_to_world(Vector2(0, -1), 0.0)
		if a.is_equal_approx(b) or a.is_equal_approx(c):
			_fail("movement basis not unique at 0/22/45")
		else:
			_ok("movement basis follows continuous yaw")

	var report := {
		"pitch": cam.rotation_degrees.x,
		"yaw": cam.yaw_degrees,
		"yaw_target": cam.yaw_target_degrees,
		"zoom_level": cam.zoom_level,
		"size": cam.size,
		"tap_delta": tap_delta,
		"hold_moved": moved,
		"hold_jumps": jumps,
		"offset_22": [off22.x, off22.y, off22.z],
		"offset_45": [off45.x, off45.y, off45.z],
		"failed": _failed,
	}
	var f := FileAccess.open(_scratch.path_join("camera_continuous_yaw.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE %s" % _scratch.path_join("camera_continuous_yaw.json"))
	_finish()


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All camera continuous yaw tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "CAMERA CONTINUOUS YAW FAILED")
