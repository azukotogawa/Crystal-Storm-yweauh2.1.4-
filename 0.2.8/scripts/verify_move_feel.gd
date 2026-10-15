extends SceneTree

const _InputBindings = preload("res://systems/input_bindings.gd")
const _MoveFeel = preload("res://player/move_feel.gd")

const DT := 1.0 / 60.0
const WALK := 16.0
const ACCEL := 95.0
const FRICTION := 85.0

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	_test_gates()
	_test_integration()
	_test_jump_feel()
	_test_binds()
	_test_source()
	if _failed == 0:
		print("All move feel tests OK")
		quit(0)
	else:
		push_error("verify_move_feel: %d failure(s)" % _failed)
		quit(1)


func _drive(seconds: float, sprinting: bool, airborne: bool, start: Vector2, desired_speed: float) -> Vector2:
	var vel := start
	var desired := Vector2(desired_speed, 0.0)
	var steps := int(round(seconds / DT))
	for _i in steps:
		var has_input := desired.length_squared() > 0.0001
		var reversing := has_input and vel.dot(desired) < 0.0
		var rate := _MoveFeel.accel_rate(ACCEL, FRICTION, has_input, airborne, reversing, sprinting)
		vel = vel.move_toward(desired, rate * DT)
	return vel


func _distance(seconds: float, sprinting: bool, desired_speed: float) -> float:
	var vel := Vector2.ZERO
	var desired := Vector2(desired_speed, 0.0)
	var travelled := 0.0
	var steps := int(round(seconds / DT))
	for _i in steps:
		var has_input := true
		var reversing := vel.dot(desired) < 0.0
		var rate := _MoveFeel.accel_rate(ACCEL, FRICTION, has_input, false, reversing, sprinting)
		vel = vel.move_toward(desired, rate * DT)
		travelled += vel.x * DT
	return travelled


func _test_gates() -> void:
	var dry := _MoveFeel.apply_sprint(WALK, true, false, false)
	var wade := _MoveFeel.apply_sprint(WALK * 0.68, true, false, true)
	var swim := _MoveFeel.apply_sprint(WALK * 0.42, true, true, false)
	if dry < WALK * 1.5:
		_fail("sprint should be at least 1.5x walk, got %.2f" % dry)
	elif swim > WALK * 0.42 + 0.01:
		_fail("submerged sprint must stay at swim speed, got %.2f" % swim)
	elif wade >= dry:
		_fail("wade sprint %.2f should stay under dry sprint %.2f" % [wade, dry])
	elif absf(_MoveFeel.apply_sprint(WALK, false, false, false) - WALK) > 0.001:
		_fail("walk speed changed when sprint is off")
	else:
		print("OK sprint %.2f wade %.2f swim %.2f" % [dry, wade, swim])


func _test_integration() -> void:
	var walk_v := _drive(0.5, false, false, Vector2.ZERO, WALK)
	var sprint_speed := _MoveFeel.apply_sprint(WALK, true, false, false)
	var sprint_v := _drive(0.5, true, false, Vector2.ZERO, sprint_speed)
	if walk_v.x < WALK - 1.0:
		_fail("walk did not reach speed, x=%.2f" % walk_v.x)
	elif sprint_v.x < sprint_speed - 1.5:
		_fail("sprint did not reach speed, x=%.2f want %.2f" % [sprint_v.x, sprint_speed])
	else:
		print("OK half-second speed walk %.2f sprint %.2f" % [walk_v.x, sprint_v.x])

	var walk_d := _distance(1.0, false, WALK)
	var sprint_d := _distance(1.0, true, sprint_speed)
	if sprint_d < walk_d * 1.45:
		_fail("one second sprint %.2f is not clearly faster than walk %.2f" % [sprint_d, walk_d])
	else:
		print("OK one second distance walk %.2f sprint %.2f" % [walk_d, sprint_d])

	var stopped := _drive(8.0 * DT, false, false, Vector2(WALK, 0.0), 0.0)
	var old_stop := WALK - FRICTION * 8.0 * DT
	if stopped.x > 1.5 or stopped.x >= old_stop:
		_fail("ground stop still glides, left %.2f old friction would leave %.2f" % [stopped.x, old_stop])
	else:
		print("OK ground stop left %.2f" % stopped.x)

	var air := _drive(0.3, true, true, Vector2.ZERO, sprint_speed)
	var ground := _drive(0.3, true, false, Vector2.ZERO, sprint_speed)
	if air.x > ground.x * 0.75:
		_fail("air steering %.2f is as strong as the ground %.2f" % [air.x, ground.x])
	else:
		print("OK air accel %.2f under ground %.2f" % [air.x, ground.x])

	var turned := _drive(0.1, false, false, Vector2(WALK, 0.0), -WALK)
	if turned.x >= 0.0:
		_fail("reverse did not flip in a tenth of a second, x=%.2f" % turned.x)
	else:
		print("OK reverse x=%.2f" % turned.x)


func _test_jump_feel() -> void:
	var armed := _MoveFeel.coyote_after(0.0, true, DT)
	if absf(armed - _MoveFeel.COYOTE_SEC) > 0.0001:
		_fail("grounded coyote did not arm")
	var early := _MoveFeel.coyote_after(_MoveFeel.COYOTE_SEC, false, 0.08)
	var late := _MoveFeel.coyote_after(_MoveFeel.COYOTE_SEC, false, 0.2)
	if not _MoveFeel.can_jump(false, early):
		_fail("coyote expired before 0.08s")
	elif _MoveFeel.can_jump(false, late):
		_fail("coyote still open after 0.2s")
	elif not _MoveFeel.can_jump(true, 0.0):
		_fail("supported feet could not jump")
	else:
		print("OK coyote %.3f then closed" % early)

	var cut := _MoveFeel.release_jump(100.0)
	if absf(cut - 100.0 * _MoveFeel.JUMP_RELEASE_MULT) > 0.01 or cut >= 100.0:
		_fail("tap jump did not shorten the rise, got %.2f" % cut)
	elif _MoveFeel.release_jump(-4.0) != -4.0:
		_fail("release cut a fall")
	elif _MoveFeel.gravity_scale(-1.0) <= 1.0 or _MoveFeel.gravity_scale(8.0) != 1.0:
		_fail("fall gravity scale is wrong")
	elif _MoveFeel.LAND_SPEED_KEEP <= 0.65 or _MoveFeel.LAND_SPEED_KEEP >= 1.0:
		_fail("landing keep should sit between the old dump and a full keep")
	else:
		print("OK tap cut %.1f fall scale %.2f land keep %.2f" % [cut, _MoveFeel.gravity_scale(-1.0), _MoveFeel.LAND_SPEED_KEEP])

	if _MoveFeel.bob_rate(true) <= _MoveFeel.bob_rate(false):
		_fail("sprint bob is not faster than the walk")
	else:
		print("OK sprint bob faster")


func _test_binds() -> void:
	if not InputMap.has_action("sprint"):
		_fail("sprint action missing")
		return
	var found := false
	for ev in InputMap.action_get_events("sprint"):
		if ev is InputEventKey:
			var key := ev as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if int(code) == int(KEY_SHIFT):
				found = true
	if not found:
		_fail("sprint is not bound to Shift")
	elif not _InputBindings.ACTIONS.has("sprint"):
		_fail("controls list omits sprint")
	elif _InputBindings.label_of("sprint") != "Sprint":
		_fail("sprint label is %s" % _InputBindings.label_of("sprint"))
	else:
		print("OK sprint bound to Shift")

	var proj := FileAccess.get_file_as_string("res://project.godot")
	if proj.contains("physics_ticks_per_second=") and not proj.contains("physics_ticks_per_second=60"):
		_fail("physics tick is not the 60 Hz default")
	else:
		print("OK physics tick stays 60")


func _test_source() -> void:
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	var tutorial := FileAccess.get_file_as_string("res://ui/tutorial_overlay.gd")
	var needles: PackedStringArray = [
		"is_action_pressed(\"sprint\")",
		"not submerged",
		"_MoveFeel.apply_sprint",
		"_MoveFeel.accel_rate",
		"_MoveFeel.coyote_after",
		"_MoveFeel.release_jump",
		"_MoveFeel.gravity_scale",
		"_MoveFeel.LAND_SPEED_KEEP",
		"first_contact",
		"_soft_follow_ground",
	]
	var missing := ""
	for needle in needles:
		if not body.contains(needle):
			missing += needle + " "
	if missing != "":
		_fail("player step dropped: " + missing)
	elif not tutorial.contains("Sprint with"):
		_fail("tutorial does not mention sprint")
	elif not body.contains("max_step_up_walk") or not body.contains("max_step_up_jump"):
		_fail("player step dropped the ramp step limits")
	else:
		print("OK player step uses the feel numbers and still soft-follows the ground")
