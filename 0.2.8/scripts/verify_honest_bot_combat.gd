extends SceneTree

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Fight = preload("res://scripts/honest_bot/honest_combat.gd")
const _Player = preload("res://player/player.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Capture = preload("res://helpers/probe_capture.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0

var _failed := 0
var _live_player: Node = null
var _live_fight = null
var _live_sense_id := ""
var _live_sense_xz := Vector2.ZERO
var _live_swung := false


class _Pace extends Node:
	var host = null

	func _process(delta: float) -> void:
		if host != null:
			host._on_live_frame(delta)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sources()
	_check_nearest()
	_check_engage()
	_check_retreat()
	_check_kill_and_death()
	if _failed == 0:
		await _check_live_fight()
	await _Capture.capture_step("honest-bot-combat")
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "HONEST BOT COMBAT OK")
	else:
		_ProbeExit.finish_tree(self, 1, "HONEST BOT COMBAT FAIL")


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
		"res://scripts/honest_bot/honest_combat.gd",
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
	var fight := FileAccess.get_file_as_string("res://scripts/honest_bot/honest_combat.gd")
	if not ("attack" in fight and "skill_1" in fight and "hotbar_1" in fight):
		_fail("combat must use attack, skill, and sword hotbar actions")
		return
	_ok("combat source is input-only")


func _check_nearest() -> void:
	var fight = _Fight.new()
	fight.observe([
		{"id": "mite-far", "xz": Vector2(0.0, -20.0)},
		{"id": "mite-near", "xz": Vector2(3.0, 1.0)},
	])
	if fight.nearest_id(Vector2.ZERO) != "mite-near":
		_fail("nearest enemy want mite-near got %s" % fight.nearest_id(Vector2.ZERO))
		fight.release()
		return
	fight.release()
	_ok("targets the nearest enemy")


func _check_engage() -> void:
	var fight = _Fight.new()
	fight.set_vitals(80.0, 100.0)
	var foe := Vector2(0.0, -6.0)
	fight.observe([{"id": "mite-a", "xz": foe}])
	var pos := Vector2.ZERO
	var yaw := 0.0
	var sword_frame := -1
	var attack_frame := -1
	for i in 400:
		fight.tick(pos, yaw, STEP)
		if sword_frame < 0 and fight.bot.input.is_held("hotbar_1"):
			sword_frame = i
		if attack_frame < 0 and fight.bot.input.is_held("attack"):
			attack_frame = i
		var stepped: Array = _integrate(pos, yaw, fight.bot, STEP)
		if not fight.striking:
			pos = stepped[0]
		yaw = float(stepped[1])
		if fight.swings >= 1 and fight.skills_used >= 1:
			break
	var skill_held := false
	if fight.bot.input.is_held("skill_1") or fight.bot.input.is_held("skill_2") or fight.bot.input.is_held("skill_3"):
		skill_held = true
	fight.release()
	if sword_frame < 0 or attack_frame < 0 or sword_frame >= attack_frame:
		_fail("sword hotbar should pulse before attack (sword %d attack %d)" % [sword_frame, attack_frame])
		return
	if fight.swings < 1 or fight.skills_used < 1 or not skill_held:
		_fail("close facing enemy should swing and use a skill")
		return
	if pos.distance_to(foe) > _Fight.ENGAGE_COLUMNS:
		_fail("strike started outside engage range at %s" % pos)
		return
	_ok("swings and uses a skill inside engage range")


func _check_retreat() -> void:
	var fight = _Fight.new()
	fight.set_vitals(20.0, 100.0)
	var foe := Vector2(0.0, -1.0)
	fight.observe([{"id": "mite-a", "xz": foe}])
	var pos := Vector2.ZERO
	var yaw := 0.0
	var attacked := false
	for _i in 180:
		fight.tick(pos, yaw, STEP)
		if fight.bot.input.is_held("attack") or fight.swings > 0:
			attacked = true
		var stepped: Array = _integrate(pos, yaw, fight.bot, STEP)
		pos = stepped[0]
		yaw = float(stepped[1])
	var away := pos.distance_to(foe)
	fight.release()
	if not fight.retreating or attacked or away < 3.0:
		_fail("low hp should retreat without attacking (away %.2f retreating %s attacked %s)" % [
			away, fight.retreating, attacked
		])
		return
	_ok("retreats at low hp")


func _check_kill_and_death() -> void:
	var fight = _Fight.new()
	fight.set_vitals(90.0, 100.0)
	fight.observe([
		{"id": "mite-a", "xz": Vector2(2.0, 0.0)},
		{"id": "mite-b", "xz": Vector2(-4.0, 1.0)},
	])
	fight.observe([{"id": "mite-b", "xz": Vector2(-4.0, 1.0)}])
	if fight.kills != 1 or fight.lines.is_empty() or fight.lines[0] != "KILL mite-a":
		_fail("missing foe should report one kill, got %s" % [fight.lines])
		fight.release()
		return
	fight.set_vitals(0.0, 100.0)
	fight.set_vitals(0.0, 100.0)
	if fight.deaths != 1 or fight.lines.size() < 2 or not fight.lines[1].begins_with("DEATH"):
		_fail("zero hp should report one death, got %s" % [fight.lines])
		fight.release()
		return
	fight.tick(Vector2.ZERO, 0.0, STEP)
	if fight.bot.input.is_held("move_forward") or fight.bot.input.is_held("attack"):
		_fail("death should release movement and attacks")
		fight.release()
		return
	print(fight.lines[0])
	print(fight.lines[1])
	print(fight.summary_line())
	fight.release()
	_ok("reports kills and deaths")


func _check_live_fight() -> void:
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
	var weapon = player.get_node_or_null("WeaponController")
	if weapon == null or not weapon.has_method("get_active_hotbar_index"):
		_fail("no weapon controller")
		return
	var bearings: Array[Vector2] = [
		Vector2(0.0, -6.0), Vector2(6.0, 0.0), Vector2(0.0, 6.0), Vector2(-6.0, 0.0),
	]
	var pace := _Pace.new()
	pace.host = self
	pace.process_priority = -128
	root.add_child(pace)
	var proved := false
	var fight = _Fight.new()
	for bearing in bearings:
		var start := _xz(player)
		var sense_id := "sense-%.0f-%.0f" % [bearing.x, bearing.y]
		var goal := start + bearing
		_live_player = null
		fight.release()
		await process_frame
		fight = _Fight.new()
		_live_fight = fight
		_live_sense_id = sense_id
		_live_sense_xz = goal
		_live_swung = false
		_live_player = player
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 7000:
			await process_frame
			if fight.deaths > 0:
				break
			if not _live_swung:
				continue
			_live_swung = false
			var idx := int(weapon.get_active_hotbar_index())
			var cool := float(weapon.get("_cooldown_timer"))
			if idx == 0 and cool > 0.0:
				proved = true
				print("OK live swing hotbar %d cooldown %.2f" % [idx, cool])
				break
		_live_player = null
		fight.release()
		await process_frame
		if proved or fight.deaths > 0:
			break
	if not proved:
		_fail("live sword swing did not land through the attack action")
		fight.release()
		return
	var tagged := "sense-live"
	fight = _Fight.new()
	fight.set_vitals(float(player.health), float(player.max_health))
	fight.observe(_seen_now(tagged, _xz(player) + Vector2(1.0, 0.0)))
	fight.observe(_seen_now("", Vector2.ZERO))
	var kill_line := ""
	for line in fight.lines:
		if line.begins_with("KILL "):
			kill_line = line
			print(line)
	if kill_line != "KILL %s" % tagged:
		_fail("live sense drop want KILL %s got %s" % [tagged, kill_line])
		fight.release()
		return
	fight.set_vitals(0.0, float(player.max_health))
	var death_line := ""
	for line in fight.lines:
		if line.begins_with("DEATH"):
			death_line = line
			print(line)
	print(fight.summary_line())
	fight.tick(_xz(player), _yaw(player), STEP)
	fight.release()
	await process_frame
	if death_line == "":
		_fail("live vital zero did not report a death")
		return
	_live_player = null
	_live_fight = null
	if pace != null and is_instance_valid(pace):
		pace.queue_free()
	_ok("live sword swing, kill, and death")


func _on_live_frame(delta: float) -> void:
	if _live_player == null or _live_fight == null:
		return
	var hp := float(_live_player.health)
	var hp_max := float(_live_player.max_health)
	_live_fight.set_vitals(hp, hp_max)
	if _live_fight.deaths > 0:
		return
	var step := delta
	if step <= 0.0:
		step = STEP
	_live_fight.observe(_seen_now(_live_sense_id, _live_sense_xz))
	_live_fight.tick(_xz(_live_player), _yaw(_live_player), step)
	if _live_fight.bot.input.is_held("attack"):
		_live_swung = true


func _seen_now(sense_id: String, sense_xz: Vector2) -> Array:
	var out: Array = []
	for node in get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node):
			continue
		if float(node.get("health")) <= 0.0:
			continue
		out.append({
			"id": "enemy-%d" % node.get_instance_id(),
			"xz": _Coords.column_from_node(node),
		})
	if sense_id != "":
		out.append({"id": sense_id, "xz": sense_xz})
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
