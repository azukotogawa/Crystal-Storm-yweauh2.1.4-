extends SceneTree

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Player = preload("res://player/player.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Capture = preload("res://helpers/probe_capture.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sources()
	_check_formula()
	_check_choose()
	_check_input_press()
	_check_reach()
	_check_nudge()
	_check_stuck()
	if _failed == 0:
		await _check_live_walk()
	await _Capture.capture_step("honest-bot-nav")
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "HONEST BOT NAV OK")
	else:
		_ProbeExit.finish_tree(self, 1, "HONEST BOT NAV FAIL")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _check_sources() -> void:
	var banned := [
		"voxel_position =",
		"global_position =",
		".position =",
		"take_damage",
		"add_xp",
		"grant_xp",
		"dig_cell",
		"health =",
	]
	var paths := [
		"res://scripts/honest_bot/honest_nav.gd",
		"res://scripts/honest_bot/honest_input.gd",
		"res://scripts/honest_bot/honest_play_bot.gd",
	]
	var joined := ""
	for path in paths:
		joined += FileAccess.get_file_as_string(path)
	for token in banned:
		if token in joined:
			_fail("bot source contains %s" % token)
			return
	var hands := FileAccess.get_file_as_string("res://scripts/honest_bot/honest_input.gd")
	if not ("Input.action_press" in hands and "InputEventAction" in hands):
		_fail("input driver must use action_press and InputEventAction")
		return
	_ok("bot source is input-only")


func _check_formula() -> void:
	var body = _Player.new()
	var yaw := 37.0
	var stick := Vector2(0.6, -0.8).normalized()
	var from_player: Vector2 = body.rotate_input_to_world(stick, yaw)
	var from_nav: Vector2 = _Nav.world_delta(stick, yaw)
	body.free()
	if from_player.distance_to(from_nav) > 0.0001:
		_fail("world_delta drifted from Player.rotate_input_to_world")
		return
	var forward: Vector2 = _Nav.world_delta(Vector2(0.0, -1.0), 0.0)
	if forward.distance_to(Vector2(0.0, -1.0)) > 0.0001:
		_fail("yaw 0 forward want -Z got %s" % forward)
		return
	_ok("heading matches player move")


func _check_choose() -> void:
	var side: Dictionary = _Nav.choose(Vector2.ZERO, Vector2(10.0, 0.0), 0.0)
	if str(side.get("rotate", "")) != "rotate_left" or str(side.get("move", "")) != "":
		_fail("east of a north facing should only rotate_left, got %s" % side)
		return
	var home: Dictionary = _Nav.choose(Vector2.ZERO, Vector2(0.4, -0.2), 0.0)
	if not bool(home.get("arrived", false)):
		_fail("close target should count as arrived")
		return
	var ahead: Dictionary = _Nav.choose(Vector2.ZERO, Vector2(0.0, -10.0), 0.0)
	if str(ahead.get("move", "")) != "move_forward":
		_fail("aligned target should move_forward, got %s" % ahead)
		return
	_ok("steer rotate, arrive, and forward")


func _check_input_press() -> void:
	var hands = _Hands.new()
	hands.set_held(_pack(["move_forward"]))
	if not Input.is_action_pressed("move_forward"):
		_fail("action_press did not hold move_forward")
		hands.release_all()
		return
	hands.pulse(&"jump")
	if not Input.is_action_pressed("jump"):
		_fail("InputEventAction did not press jump")
		hands.release_all()
		return
	hands.begin_tick()
	if Input.is_action_pressed("jump"):
		_fail("jump pulse stayed down")
		hands.release_all()
		return
	hands.release_all()
	if Input.is_action_pressed("move_forward"):
		_fail("release_all left move_forward down")
		return
	_ok("press, pulse, and release")


func _check_reach() -> void:
	var bot = _Bot.new()
	var pos := Vector2.ZERO
	var yaw := 45.0
	var goal := Vector2(10.0, -3.0)
	bot.set_target(goal)
	for _i in 600:
		bot.tick(pos, yaw, STEP)
		var stepped: Array = _integrate(pos, yaw, bot, STEP)
		pos = stepped[0]
		yaw = float(stepped[1])
		if bot.arrived:
			break
	bot.release()
	if not bot.arrived or pos.distance_to(goal) > _Nav.ARRIVE_COLUMNS:
		_fail("sim walk did not arrive (pos %s arrived %s)" % [pos, bot.arrived])
		return
	if bot.stuck_lines.size() != 0:
		_fail("open sim walk reported stuck")
		return
	_ok("sim walk reached %s" % pos)


func _check_nudge() -> void:
	var slow = _Bot.new()
	var pos := Vector2.ZERO
	slow.set_target(Vector2(0.0, -10.0))
	for _i in 40:
		slow.tick(pos, 0.0, STEP)
		pos += Vector2(0.0, -0.002)
	if not (slow.input.is_held("move_forward") and _strafing(slow)):
		_fail("slow crawl should keep forward and add a sidestep")
		slow.release()
		return
	slow.release()
	var fast = _Bot.new()
	pos = Vector2.ZERO
	var yaw := 0.0
	fast.set_target(Vector2(0.0, -10.0))
	for _i in 40:
		fast.tick(pos, yaw, STEP)
		var stepped: Array = _integrate(pos, yaw, fast, STEP)
		pos = stepped[0]
		yaw = float(stepped[1])
	if _strafing(fast):
		_fail("a clear walk should not sidestep")
		fast.release()
		return
	fast.release()
	_ok("sidestep only when progress stalls")


func _check_stuck() -> void:
	var bot = _Bot.new()
	var pos := Vector2(3.0, 4.0)
	bot.set_target(Vector2(3.0, -20.0))
	for _i in 260:
		bot.tick(pos, 0.0, STEP)
	bot.release()
	if bot.stuck_lines.is_empty() or not bot.stuck_lines[0].begins_with("STUCK nav"):
		_fail("frozen body produced no STUCK nav line")
		return
	if not bot.gave_up or bot.stuck_lines.size() < _Nav.MAX_STUCK_REPORTS:
		_fail("frozen body should give up after %d reports, got %d" % [
			_Nav.MAX_STUCK_REPORTS, bot.stuck_lines.size()
		])
		return
	print(bot.stuck_lines[0])
	_ok("stuck reported and gave up")


func _check_live_walk() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 2400:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		return
	for _w in 120:
		await process_frame
		if not _GI.blocks_actions():
			break
	if _GI.blocks_actions():
		_fail("actions still blocked after stream ready")
		return
	var player = get_first_node_in_group("player")
	if player == null or not bool(player.get("world_ready")):
		_fail("player not world_ready")
		return
	var bot = _Bot.new()
	var bearings: Array[Vector2] = [
		Vector2(8.0, 0.0), Vector2(-8.0, 0.0), Vector2(0.0, 8.0), Vector2(0.0, -8.0),
	]
	var walked := false
	for bearing in bearings:
		var start := _xz(player)
		var goal := start + bearing
		bot.set_target(goal)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 5000:
			var delta := root.get_physics_process_delta_time()
			if delta <= 0.0:
				delta = STEP
			bot.tick(_xz(player), _yaw(player), delta)
			await process_frame
			if bot.arrived or bot.gave_up:
				break
		bot.release()
		await process_frame
		var end := _xz(player)
		var moved := start.distance_to(end)
		var gained := start.distance_to(goal) - end.distance_to(goal)
		print("OK live bearing %.0f,%.0f moved %.2f gained %.2f" % [
			bearing.x, bearing.y, moved, gained
		])
		for line in bot.stuck_lines:
			print(line)
		if moved >= 3.0 and gained >= 2.5:
			walked = true
			break
	if not walked:
		_fail("live walk never closed 3 columns on a target")
		return
	_ok("live walk moved by held actions")


func _integrate(pos: Vector2, yaw: float, bot, delta: float) -> Array:
	var stick := Vector2.ZERO
	if bot.input.is_held("move_right"):
		stick.x += 1.0
	if bot.input.is_held("move_left"):
		stick.x -= 1.0
	if bot.input.is_held("move_back"):
		stick.y += 1.0
	if bot.input.is_held("move_forward"):
		stick.y -= 1.0
	if stick.length_squared() > 0.0:
		pos += _Nav.world_delta(stick.normalized(), yaw) * 10.0 * delta
	if bot.input.is_held("rotate_right"):
		yaw += _Nav.YAW_SPEED_DEG * delta
	if bot.input.is_held("rotate_left"):
		yaw -= _Nav.YAW_SPEED_DEG * delta
	return [pos, yaw]


func _strafing(bot) -> bool:
	return bot.input.is_held("move_left") or bot.input.is_held("move_right")


func _xz(player: Node) -> Vector2:
	var v: Vector3 = player.voxel_position
	return Vector2(v.x, v.z)


func _yaw(player: Node) -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	return 0.0


func _pack(names: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for name in names:
		out.append(String(name))
	return out
