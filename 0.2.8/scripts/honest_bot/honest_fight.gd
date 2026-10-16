extends RefCounted

const _Roster = preload("res://scripts/honest_bot/honest_roster.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _Water = preload("res://helpers/water_locomotion.gd")
const THREAT_COLUMNS := 14.0

var bot = _Bot.new()
var killed: Dictionary = {}
var seen: Dictionary = {}
var _down: Dictionary = {}
var age := 0.0
var _phase := "approach"
var _quiet := 0.0
var _level := 1
var _bow := 0
var _attack_wait := 0.0
var _sword := false
var _foe_id := ""
var _unstuck := false
var _heal := 0
var _heal_wait := 0.0
var _dead := false
var _approach_limit := -1.0
var _alive: Dictionary = {}


func release() -> void:
	bot.release()


func reset() -> void:
	release()
	killed = {}
	seen = {}
	_down = {}
	age = 0.0
	_phase = "approach"
	_quiet = 0.0
	_level = 1
	_bow = 0
	_attack_wait = 0.0
	_sword = false
	_foe_id = ""
	_unstuck = false
	_heal = 0
	_heal_wait = 0.0
	_dead = false
	_approach_limit = -1.0
	_alive = {}
	bot.extra_held = PackedStringArray()


func outcome(kind: String) -> String:
	return _Roster.kind_status(kind, killed, seen)


func tick(step: float, tree: SceneTree, player: Node, origin: Vector2) -> String:
	var dt := step
	if dt <= 0.0:
		dt = 1.0 / 60.0
	age += dt
	_heal_wait = maxf(_heal_wait - dt, 0.0)
	_flush_stuck()
	if player == null or tree == null:
		print("FAIL combat missing player")
		return "fail"
	if _dead or float(player.health) <= 0.0:
		if not _dead:
			_dead = true
			print("DEATH hp %.1f" % float(player.health))
		bot.release()
		return "fail"
	_watch_level(tree)
	if _phase == "approach":
		return _approach(dt, tree, player, origin)
	return _hunt(dt, tree, player, origin)


func _approach(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> String:
	var pos := _xz(player)
	if _approach_limit < 0.0:
		var trip := pos.distance_to(origin)
		_approach_limit = clampf(trip / 8.0 + 12.0, _Roster.APPROACH_LIMIT, 180.0)
	if pos.distance_to(origin) <= _Roster.POOL_STAND or age >= _approach_limit:
		_phase = "hunt"
		_quiet = 0.0
		age = 0.0
		bot.release()
		print("SHOWCASE pool %.1f columns from origin" % pos.distance_to(origin))
		return ""
	if bot.gave_up:
		_recover(pos, origin)
		return ""
	if _level < _Roster.LEVEL_GOAL:
		var mite := _nearest_mite(tree, pos)
		if not mite.is_empty():
			return _fight(dt, player, mite)
	var threat := _nearest_foe(tree, pos)
	var threatened := not threat.is_empty() and float(threat.get("dist", 99.0)) < THREAT_COLUMNS
	if not threatened and _ratio(player) < 0.72 and _herbs(player) > 0 and _heal_wait <= 0.0:
		_heal_idle()
		return ""
	var goal := _Roster.pool_goal(pos, origin, _Roster.POOL_STAND)
	var extras := PackedStringArray()
	if threatened:
		var foe: Vector2 = threat.get("xz", pos)
		var away := pos - foe
		if away.length_squared() < 0.04:
			away = Vector2(1.0, 0.0)
		else:
			away = away.normalized()
		var home := origin - pos
		if home.length_squared() < 0.04:
			home = away
		else:
			home = home.normalized()
		goal = pos + away * 6.0 + home * 4.0
		extras.append("sprint")
		extras.append("move_left" if fmod(age, 1.2) < 0.6 else "move_right")
	elif pos.distance_to(goal) > 6.0:
		extras.append("sprint")
	if _submerged(player):
		extras.append("jump")
	if not bot.has_target or bot.target.distance_to(goal) > 2.0:
		bot.set_target(goal)
	bot.extra_held = extras
	bot.tick(pos, _yaw(player), dt)
	return ""


func _recover(pos: Vector2, origin: Vector2) -> void:
	if not _unstuck:
		bot.input.pulse("unstuck")
		_unstuck = true
		return
	_unstuck = false
	bot.set_target(_Roster.pool_goal(pos, origin, _Roster.POOL_STAND))


func _hunt(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> String:
	var pos := _xz(player)
	if _level >= _Roster.LEVEL_GOAL and _ratio(player) < 0.70:
		bot.release()
		return _mite_result()
	var rows := _sense(tree)
	var goal := _level < _Roster.LEVEL_GOAL
	var choice: Dictionary = _Roster.pick(rows, pos, _Roster.SCAN_COLUMNS, killed, goal)
	var pending := not choice.is_empty() and not killed.has(str(choice.get("kind", "")))
	var endangered := _ratio(player) <= 0.30 and _herbs(player) <= 0
	if not _Roster.keep_hunting(_level, _Roster.LEVEL_GOAL, _quiet, _Roster.QUIET_LIMIT, age, _Roster.HUNT_LIMIT, pending, endangered):
		bot.release()
		return _mite_result()
	if choice.is_empty():
		_quiet += dt
		_hold_pool(dt, player, origin)
		return ""
	_quiet = 0.0
	return _fight(dt, player, choice)


func _mite_result() -> String:
	var status := outcome("crystal_mite")
	print("SHOWCASE kills mite %d level %d" % [int(killed.get("crystal_mite", 0)), _level])
	return status


func _fight(dt: float, player: Node, choice: Dictionary) -> String:
	var kind := str(choice.get("kind", ""))
	var foe: Vector2 = choice.get("xz", Vector2.ZERO)
	var fid := str(choice.get("id", ""))
	if fid != _foe_id:
		_foe_id = fid
		_sword = false
		_attack_wait = 0.0
		if _bow > 0 and _bow < 4:
			_bow = 0
	var pos := _xz(player)
	bot.input.aim_column(player, foe.x, foe.y)
	if _ratio(player) <= 0.55 and _herbs(player) > 0:
		return _heal_or_leave(dt, player, foe)
	if _ratio(player) <= 0.30:
		return _heal_or_leave(dt, player, foe)
	var dist := pos.distance_to(foe)
	if dist < _Roster.KITE_COLUMNS:
		_back_off(dt, player, pos, foe)
		return ""
	if dist > _Roster.ENGAGE_COLUMNS:
		_close_in(dt, player, foe, dist)
		return ""
	_strike(dt, player, pos, foe, kind)
	return ""


func _heal_or_leave(dt: float, player: Node, foe: Vector2) -> String:
	var pos := _xz(player)
	_back_off(dt, player, pos, foe)
	if _herbs(player) <= 0 or _heal_wait > 0.0:
		return ""
	if _heal == 0:
		bot.input.pulse("hotbar_6")
		_heal = 1
		return ""
	bot.input.pulse("build_place")
	_heal = 0
	_heal_wait = 0.45
	_sword = false
	return ""


func _back_off(dt: float, player: Node, pos: Vector2, foe: Vector2) -> void:
	var away := pos - foe
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	var goal := pos + away * 4.0
	if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	bot.extra_held = PackedStringArray(["sprint"])
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, foe.x, foe.y)


func _close_in(dt: float, player: Node, foe: Vector2, dist: float) -> void:
	if not bot.has_target or bot.gave_up or bot.target.distance_to(foe) > 0.75:
		bot.set_target(foe)
	var extras := PackedStringArray()
	if dist > 6.0:
		extras.append("sprint")
	bot.extra_held = extras
	bot.tick(_xz(player), _yaw(player), dt)


func _strike(dt: float, player: Node, pos: Vector2, foe: Vector2, kind: String) -> void:
	seen[kind] = true
	bot.input.begin_tick()
	var held := PackedStringArray()
	var rot := _Nav.face_action(pos, foe, _yaw(player))
	if rot != "":
		held.append(rot)
	bot.input.set_held(held)
	bot.input.aim_column(player, foe.x, foe.y)
	if rot != "":
		return
	if kind == "crystal_mite" and _bow < 4:
		_bow_beat(dt)
		return
	if not _sword:
		bot.input.pulse("hotbar_1")
		_sword = true
		return
	_attack_wait -= dt
	if _attack_wait > 0.0:
		return
	bot.input.pulse("attack")
	_attack_wait = 0.48


func _bow_beat(dt: float) -> void:
	_attack_wait = maxf(_attack_wait - dt, 0.0)
	if _bow == 0:
		bot.input.pulse("hotbar_1")
		_bow = 1
		return
	if _bow == 1:
		bot.input.pulse("attack")
		_bow = 2
		_attack_wait = 0.48
		return
	if _attack_wait > 0.0:
		return
	if _bow == 2:
		bot.input.pulse("hotbar_3")
		_bow = 3
		return
	bot.input.pulse("attack")
	print("SHOWCASE bow attack")
	_bow = 4
	_sword = false
	_attack_wait = 0.48


func _hold_pool(dt: float, player: Node, origin: Vector2) -> void:
	var pos := _xz(player)
	if pos.distance_to(origin) <= _Roster.POOL_STAND + 2.0:
		bot.release()
		if _ratio(player) < 0.72 and _herbs(player) > 0 and _heal_wait <= 0.0:
			_heal_idle()
		return
	if not bot.has_target or bot.arrived or bot.gave_up:
		bot.set_target(_Roster.pool_goal(pos, origin, _Roster.POOL_STAND))
	bot.extra_held = PackedStringArray(["sprint"])
	bot.tick(pos, _yaw(player), dt)


func _heal_idle() -> void:
	if _heal == 0:
		bot.input.pulse("hotbar_6")
		_heal = 1
		return
	bot.input.pulse("build_place")
	_heal = 0
	_heal_wait = 0.45
	_sword = false


func _nearest_mite(tree: SceneTree, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := _Roster.SCAN_COLUMNS
	for row in _sense(tree):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("kind", "")) != "crystal_mite":
			continue
		var xz: Vector2 = row.get("xz", pos)
		var dist := pos.distance_to(xz)
		if dist < best_d:
			best_d = dist
			best = row
	return best


func _nearest_foe(tree: SceneTree, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	if tree == null:
		return best
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var kind := str(node.get("enemy_id"))
		if kind == "" or kind == "origin_warden":
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		var xz := Vector2(float(col.x) + 0.5, float(col.y) + 0.5)
		var dist := pos.distance_to(xz)
		if dist < best_d:
			best_d = dist
			best = {"xz": xz, "dist": dist}
	return best


func _sense(tree: SceneTree) -> Array:
	var rows: Array = []
	var still := {}
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node):
			continue
		var kind := str(node.get("enemy_id"))
		if kind == "" or kind == "origin_warden":
			continue
		var iid := str(node.get_instance_id())
		if float(node.get("health")) <= 0.0:
			_count_kill(iid, kind)
			continue
		still[iid] = kind
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		rows.append({
			"id": iid,
			"kind": kind,
			"xz": Vector2(float(col.x) + 0.5, float(col.y) + 0.5),
		})
	for iid in _alive.keys():
		if still.has(iid):
			continue
		_count_kill(str(iid), str(_alive[iid]))
	_alive = still
	return rows


func _count_kill(iid: String, kind: String) -> void:
	if _down.has(iid):
		return
	_down[iid] = true
	killed[kind] = int(killed.get(kind, 0)) + 1
	seen[kind] = true
	print("KILL %s" % kind)


func _watch_level(tree: SceneTree) -> void:
	var node := tree.get_first_node_in_group("progression_service")
	if node == null:
		return
	var level := int(node.level)
	if level <= _level:
		return
	_level = level
	print("LEVEL %d" % level)


func _flush_stuck() -> void:
	for line in bot.stuck_lines:
		print(line)
	if not bot.stuck_lines.is_empty():
		bot.stuck_lines = PackedStringArray()


func _ratio(player: Node) -> float:
	return clampf(float(player.health) / maxf(float(player.max_health), 1.0), 0.0, 1.0)


func _herbs(player: Node) -> int:
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return 0
	return int(inv.count_item("herb"))


func _submerged(player: Node) -> bool:
	var world = player.get("world")
	var feet: Vector3 = player.voxel_position
	if world == null:
		return false
	var col_x := floori(feet.x)
	var col_z := floori(feet.z)
	if not _Water.column_has_water(world, col_x, col_z):
		return false
	var info: Dictionary = _Water.sample(world, col_x, col_z, feet.y, feet.y, 1.6)
	return bool(info.get("submerged", false))


func _xz(player: Node) -> Vector2:
	var feet: Vector3 = player.voxel_position
	return Vector2(feet.x, feet.z)


func _yaw(player: Node) -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	return 0.0
