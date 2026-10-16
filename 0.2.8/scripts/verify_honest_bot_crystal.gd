extends SceneTree

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Run = preload("res://scripts/honest_bot/honest_crystal.gd")
const _Fight = preload("res://scripts/honest_bot/honest_combat.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Capture = preload("res://helpers/probe_capture.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0
const SWORD_CHIP := 5.0
const CRYSTAL_MAX := 500.0

var _failed := 0
var _live_player: Node = null
var _live_run = null
var _live_crystal: Node = null


class _Pace extends Node:
	var host = null

	func _process(delta: float) -> void:
		if host != null:
			host._on_live_frame(delta)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sources()
	_check_walk()
	_check_chip()
	_check_boss_priority()
	_check_destroy_and_boss()
	if _failed == 0:
		await _check_live_crystal()
	await _Capture.capture_step("honest-bot-crystal")
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "HONEST BOT CRYSTAL OK")
	else:
		_ProbeExit.finish_tree(self, 1, "HONEST BOT CRYSTAL FAIL")


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
		"damage_crystal_at",
		"damage_spawn",
	]
	var paths := [
		"res://scripts/honest_bot/honest_nav.gd",
		"res://scripts/honest_bot/honest_input.gd",
		"res://scripts/honest_bot/honest_play_bot.gd",
		"res://scripts/honest_bot/honest_combat.gd",
		"res://scripts/honest_bot/honest_progress.gd",
		"res://scripts/honest_bot/honest_crystal.gd",
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
	var crystal := FileAccess.get_file_as_string("res://scripts/honest_bot/honest_crystal.gd")
	if not ("strike_point" in crystal and "BOSS_PREFIX" in crystal and "CRYSTAL DESTROYED" in crystal):
		_fail("crystal bot must strike the crystal, fight a boss prefix, and announce destroy")
		return
	_ok("crystal source is input-only")


func _check_walk() -> void:
	var run = _Run.new()
	run.set_vitals(100.0, 100.0)
	var crystal := Vector2(0.0, -10.0)
	run.observe_crystal(crystal, CRYSTAL_MAX, CRYSTAL_MAX)
	var pos := Vector2.ZERO
	var yaw := 0.0
	var moved := false
	for _i in 240:
		run.observe_crystal(crystal, CRYSTAL_MAX, CRYSTAL_MAX)
		run.observe_foes([])
		run.tick(pos, yaw, STEP)
		if run.fight.bot.input.is_held("move_forward") or run.fight.bot.input.is_held("rotate_left") or run.fight.bot.input.is_held("rotate_right"):
			moved = true
		var stepped: Array = _integrate(pos, yaw, run.fight.bot, STEP)
		pos = stepped[0]
		yaw = float(stepped[1])
		if run.striking_crystal:
			break
	var dist := pos.distance_to(crystal)
	run.release()
	if not moved:
		_fail("crystal walk never held a move or rotate")
		return
	if dist > 8.5:
		_fail("crystal walk did not close, dist %.2f" % dist)
		return
	_ok("walks toward the crystal")


func _check_chip() -> void:
	var run = _Run.new()
	run.set_vitals(100.0, 100.0)
	var crystal := Vector2(0.0, -1.5)
	run.observe_crystal(crystal, CRYSTAL_MAX, CRYSTAL_MAX)
	var pos := Vector2.ZERO
	var yaw := 0.0
	var attack_frame := -1
	for i in 180:
		run.observe_crystal(crystal, CRYSTAL_MAX, CRYSTAL_MAX)
		run.observe_foes([])
		run.tick(pos, yaw, STEP)
		if attack_frame < 0 and run.fight.bot.input.is_held("attack"):
			attack_frame = i
		if run.fight.swings >= 1:
			break
	var striking: bool = run.striking_crystal
	var swings: int = int(run.fight.swings)
	run.release()
	if not striking or attack_frame < 0 or swings < 1:
		_fail("close crystal should be attacked via input (striking %s swings %d attack %d)" % [
			striking, swings, attack_frame
		])
		return
	_ok("attacks the crystal through input")


func _check_boss_priority() -> void:
	var run = _Run.new()
	run.set_vitals(90.0, 100.0)
	var crystal := Vector2(0.0, -1.5)
	var boss := Vector2(1.0, -1.0)
	run.observe_crystal(crystal, CRYSTAL_MAX * _Run.BOSS_LINE, CRYSTAL_MAX)
	run.observe_foes([{"id": "boss-warden", "xz": boss}])
	var pos := Vector2.ZERO
	var yaw := 0.0
	var chipped := false
	for _i in 90:
		run.observe_crystal(crystal, CRYSTAL_MAX * _Run.BOSS_LINE, CRYSTAL_MAX)
		run.observe_foes([{"id": "boss-warden", "xz": boss}])
		run.tick(pos, yaw, STEP)
		if run.striking_crystal:
			chipped = true
		var stepped: Array = _integrate(pos, yaw, run.fight.bot, STEP)
		if not run.fight.striking:
			pos = stepped[0]
		yaw = float(stepped[1])
		if run.fight.swings >= 1:
			break
	var spawn_line := _first_prefix(run.lines, "BOSS SPAWN")
	var line_line := _first_prefix(run.lines, "BOSS LINE")
	print(line_line)
	print(spawn_line)
	run.release()
	if not run.fighting_boss or chipped:
		_fail("boss should take priority over the crystal")
		return
	if spawn_line == "" or line_line == "":
		_fail("missing boss spawn or boss line, got %s" % [run.lines])
		return
	if run.fight.swings < 1:
		_fail("boss in range should be attacked")
		return
	_ok("fights the boss before the crystal")


func _check_destroy_and_boss() -> void:
	var run = _Run.new()
	run.set_vitals(100.0, 100.0)
	var crystal := Vector2(0.0, -2.0)
	var pos := Vector2.ZERO
	var yaw := 0.0
	var hp := CRYSTAL_MAX
	var last_swings := 0
	var boss_alive := false
	var boss_done := false
	var boss_hits := 0
	var boss_frames := 0
	for _i in 9000:
		run.observe_crystal(crystal, hp, CRYSTAL_MAX)
		var foes: Array = []
		if boss_alive:
			foes.append({"id": "boss-warden", "xz": crystal + Vector2(1.0, 0.0)})
		run.observe_foes(foes)
		run.tick(pos, yaw, STEP)
		var swings: int = int(run.fight.swings)
		if swings > last_swings:
			if run.striking_crystal:
				hp = maxf(hp - SWORD_CHIP * float(swings - last_swings), 0.0)
			elif run.fighting_boss:
				boss_hits += swings - last_swings
		last_swings = swings
		if boss_alive:
			boss_frames += 1
			if boss_hits >= 3 or boss_frames >= 90:
				boss_alive = false
				boss_done = true
		if not boss_done and not boss_alive and hp > 0.0 and hp <= CRYSTAL_MAX * _Run.BOSS_LINE:
			boss_alive = true
		var stepped: Array = _integrate(pos, yaw, run.fight.bot, STEP)
		if not run.striking_crystal and not run.fight.striking:
			pos = stepped[0]
		yaw = float(stepped[1])
		if run.destroyed and run.boss_kills >= 1:
			break
	for line in run.lines:
		if line.begins_with("BOSS") or line.begins_with("CRYSTAL") or line.begins_with("KILL"):
			print(line)
	print(run.summary_line())
	var destroyed: bool = run.destroyed
	var boss_kills: int = int(run.boss_kills)
	run.release()
	if not destroyed:
		_fail("simulated crystal was not destroyed hp %.1f swings %d boss_kills %d" % [
			hp, int(run.fight.swings), boss_kills
		])
		return
	if boss_kills < 1:
		_fail("boss did not vanish after being fought")
		return
	_ok("destroys the crystal after the boss fight")


func _check_live_crystal() -> void:
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
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		_fail("no crystal origin")
		return
	var origin: Vector2i = crystal.get_origin_cell()
	var origin_xz := Vector2(float(origin.x), float(origin.y))
	var start := _xz(player)
	var start_remaining := start.distance_to(origin_xz)
	print("ORIGIN %.2f,%.2f" % [origin_xz.x, origin_xz.y])
	print("START %.2f,%.2f remaining %.2f" % [start.x, start.y, start_remaining])
	var run = _Run.new()
	var pace := _Pace.new()
	pace.host = self
	pace.process_priority = -128
	root.add_child(pace)
	_live_player = player
	_live_crystal = crystal
	_live_run = run
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await process_frame
		if run.destroyed or run.fight.deaths > 0 or run.fight.bot.gave_up:
			break
	_live_player = null
	_live_run = null
	_live_crystal = null
	var end := _xz(player)
	var hp_now := _crystal_hp(crystal)
	var remaining := end.distance_to(origin_xz)
	var gained := start_remaining - remaining
	var stuck_n := run.stuck_lines().size()
	for line in run.stuck_lines():
		print(line)
	for line in run.lines:
		print(line)
	print("STOP live reach remaining %.2f gained %.2f stuck %d at %.2f,%.2f toward %.2f,%.2f hp %.1f/%.1f" % [
		remaining, gained, stuck_n, end.x, end.y, origin_xz.x, origin_xz.y, hp_now.x, hp_now.y
	])
	print(run.summary_line())
	run.release()
	if pace != null and is_instance_valid(pace):
		pace.queue_free()
	if run.destroyed:
		_ok("live crystal destroyed")
		return
	if start_remaining < 4.0:
		_fail("player spawned on the crystal but did not destroy it")
		return
	_ok("live crystal not reached; remaining %.2f" % remaining)


func _on_live_frame(delta: float) -> void:
	if _live_player == null or _live_run == null or _live_crystal == null:
		return
	if _live_run.fight.deaths > 0:
		return
	var step := delta
	if step <= 0.0:
		step = STEP
	_live_run.set_vitals(float(_live_player.health), float(_live_player.max_health))
	var origin: Vector2i = _live_crystal.get_origin_cell()
	var hp := _crystal_hp(_live_crystal)
	_live_run.observe_crystal(Vector2(float(origin.x), float(origin.y)), hp.x, hp.y)
	_live_run.observe_foes(_bosses_now())
	_live_run.tick(_xz(_live_player), _yaw(_live_player), step)


func _crystal_hp(crystal: Node) -> Vector2:
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return Vector2(0.0, 0.0)
	var prog: Dictionary = crystal.get_spawn_progress()
	return Vector2(float(prog.get("crystal_health", 0.0)), float(prog.get("crystal_max_health", 0.0)))


func _bosses_now() -> Array:
	var out: Array = []
	for node in get_nodes_in_group("origin_boss"):
		if not is_instance_valid(node):
			continue
		if float(node.get("health")) <= 0.0:
			continue
		out.append({
			"id": "boss-%d" % node.get_instance_id(),
			"xz": _Coords.column_from_node(node),
		})
	return out


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


func _first_prefix(rows: PackedStringArray, prefix: String) -> String:
	for line in rows:
		if line.begins_with(prefix):
			return line
	return ""
