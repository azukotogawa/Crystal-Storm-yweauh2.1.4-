extends RefCounted

const _Roster = preload("res://scripts/honest_bot/honest_roster.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _Water = preload("res://helpers/water_locomotion.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Hazard = preload("res://scripts/honest_bot/honest_hazard.gd")
const _Farm = preload("res://scripts/honest_bot/honest_farm.gd")
const _Walk = preload("res://scripts/honest_bot/honest_traversal.gd")
const _World = preload("res://world/world_state.gd")
const THREAT_COLUMNS := 14.0
const CHIP_LEASH := 2.6
const HEAL_RATIO := 0.55
const AIM_WAIT := 0.35
const SITE_STAND := 6.0

var bot = _Bot.new()
var killed: Dictionary = {}
var seen: Dictionary = {}
var _down: Dictionary = {}
var age := 0.0
var _phase := "approach"
var _quiet := 0.0
var _level := 1
var _xp := 0
var _announced := false
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
var bow_phase := "off"
var bow_logged := false
var _bow_age := 0.0
var _pick := false
var _chip_cell := Vector2.INF
var _chip_swings := 0
var _chip_xp := -1
var _chip_noted := false
var _heart_at := -1.0
var _chip_gap := _Farm.HEART_GAP
var _chip_age := 0.0
var _aim_wait := 0.0
var _bound: Array = []
var _skipped: Dictionary = {}
var _foe_age := 0.0
var _demo := ""
var _demo_age := 0.0
var _demo_hold := 0.0
var _site_key := ""
var _site_at := Vector2.ZERO
var _site_age := 0.0
var _site_limit := 20.0
var _site_mark := -1
var _site_inside := 0.0
var _site_opened := false
var _site_noted := false
var _visits := 0
var _site_resumes := 0
var _pool_visit := 0.0
var _pool_done := false
var _done: Dictionary = {}


func release() -> void:
	for node in _bound:
		if not is_instance_valid(node):
			continue
		if node.has_signal("killed") and node.killed.is_connected(_on_enemy_killed):
			node.killed.disconnect(_on_enemy_killed)
		if node.has_signal("died") and node.died.is_connected(_on_wildlife_died):
			node.died.disconnect(_on_wildlife_died)
	_bound.clear()
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
	_xp = 0
	_announced = false
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
	bow_phase = "off"
	bow_logged = false
	_bow_age = 0.0
	_pick = false
	_chip_cell = Vector2.INF
	_chip_swings = 0
	_chip_xp = -1
	_chip_noted = false
	_heart_at = -1.0
	_chip_gap = _Farm.HEART_GAP
	_chip_age = 0.0
	_aim_wait = 0.0
	_skipped = {}
	_foe_age = 0.0
	_demo = ""
	_demo_age = 0.0
	_demo_hold = 0.0
	_site_key = ""
	_site_at = Vector2.ZERO
	_site_age = 0.0
	_site_limit = 20.0
	_site_mark = -1
	_site_inside = 0.0
	_site_opened = false
	_site_noted = false
	_visits = 0
	_site_resumes = 0
	_pool_visit = 0.0
	_pool_done = false
	_done = {}
	bot.extra_held = PackedStringArray()


func outcome(kind: String) -> String:
	return _Roster.kind_status(kind, killed, seen)


func level_now() -> int:
	return _level


func remainder_now() -> int:
	return _xp


func chapter_feature() -> String:
	if _demo != "":
		return _demo
	if _site_key != "":
		return "treasure_open_%d" % (_visits + 1)
	return ""


func skip_site(at: Vector2) -> void:
	if at == Vector2.ZERO:
		return
	_done[_Farm.site_key(at)] = true


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


func _approach(_dt: float, tree: SceneTree, player: Node, origin: Vector2) -> String:
	if tree == null or player == null:
		print("FAIL farm missing player")
		return "fail"
	_phase = "hunt"
	_quiet = 0.0
	age = 0.0
	bot.release()
	print("SHOWCASE farm before crystal dist %.0f" % _xz(player).distance_to(origin))
	return ""


func _recover(pos: Vector2, origin: Vector2) -> void:
	if not _unstuck:
		if bot.input.pulse("unstuck"):
			_unstuck = true
		return
	_unstuck = false
	bot.set_target(_Roster.pool_goal(pos, origin, _Roster.POOL_STAND))


func _hunt(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> String:
	var pos := _xz(player)
	var rows := _usable(_sense(tree))
	if _foe_id != "" and not _alive.has(_foe_id):
		_note_down()
	if _demo_hold > 0.0:
		_demo_hold = maxf(_demo_hold - dt, 0.0)
		_demo_age += dt
		bot.release()
		if _demo_hold <= 0.0:
			_demo = ""
		return ""
	var ready := _Farm.ready(_level, _xp)
	var demo := _Farm.demo_ready(_level)
	var need_mite := int(killed.get("crystal_mite", 0)) <= 0
	var farming := not ready or need_mite or not _bow_clear()
	if farming:
		var choice: Dictionary = _Roster.pick(rows, pos, _Roster.SCAN_COLUMNS, killed, true)
		if choice.is_empty():
			choice = _Farm.pick_seek(rows, pos, killed, _Farm.SEEK_COLUMNS, _skipped, true)
		if choice.is_empty():
			choice = _Farm.pick_seek(rows, pos, killed, 48.0, _skipped, false)
		if not choice.is_empty():
			_quiet = 0.0
			return _fight(dt, tree, player, choice, origin)
		if age >= _Farm.FARM_LIMIT:
			print("FAIL farm short level %d earned %d" % [_level, _Farm.earned(_level, _xp)])
			bot.release()
			return "fail"
		return _seek_xp(dt, tree, player, origin, pos)
	if not demo:
		_chip_age += dt
		if _chip_age >= _Farm.CHIP_LIMIT:
			print("FAIL farm short of skill points level %d earned %d" % [_level, _Farm.earned(_level, _xp)])
			bot.release()
			return "fail"
		var threat: Dictionary = _Farm.pick_seek(rows, pos, killed, CHIP_LEASH, _skipped, false)
		if not threat.is_empty():
			_pick = false
			_quiet = 0.0
			return _fight(dt, tree, player, threat, origin)
		return _chip(dt, tree, player, origin)
	if not _pool_done:
		_pool_visit += dt
		_hold_pool(dt, tree, player, origin)
		if _pool_visit >= 25.0:
			_pool_done = true
			bot.release()
		return ""
	bot.release()
	return _mite_result()


func _mite_result() -> String:
	var status := outcome("crystal_mite")
	var total := _Farm.earned(_level, _xp)
	print("SHOWCASE kills mite %d level %d earned %d" % [int(killed.get("crystal_mite", 0)), _level, total])
	if not _Farm.ready(_level, _xp):
		print("FAIL farm short of level 3")
		return "fail"
	return status


func _bow_clear() -> bool:
	return bow_phase == "off" or bow_phase == "done"


func _chip(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> String:
	var pos := _xz(player)
	if not _chip_noted:
		_chip_noted = true
		_heart_at = _heart_hp(tree)
		print("SHOWCASE mass chip level %d earned %d heart %.0f" % [_level, _Farm.earned(_level, _xp), _heart_at])
	if _Hazard.burning(tree, pos):
		_exit_hazard(dt, tree, player, origin, origin)
		return ""
	if _ratio(player) <= HEAL_RATIO and _herbs(player) > 0:
		_back_off(dt, player, pos, origin)
		_heal_idle()
		return ""
	var heart := _heart_hp(tree)
	if _heart_at >= 0.0 and heart >= 0.0 and _heart_at - heart > 8.0:
		_chip_gap = maxf(_chip_gap, 8.0)
		_heart_at = heart
		_chip_cell = Vector2.INF
		print("SHOWCASE mass chip widen gap %.1f heart %.0f" % [_chip_gap, heart])
	if _chip_cell != Vector2.INF and not _Farm.chip_cell_ok(_chip_cell, origin, _depth(tree, _chip_cell)):
		_chip_cell = Vector2.INF
	if _chip_cell == Vector2.INF:
		_chip_cell = _find_mass(tree, pos, origin)
		_chip_swings = 0
		_chip_xp = _xp
	if _chip_xp >= 0 and _xp > _chip_xp:
		_chip_xp = _xp
		_chip_swings = 0
		_chip_cell = Vector2.INF
	if _chip_cell == Vector2.INF:
		var closer := pos
		if pos.distance_to(origin) > 10.0:
			var away := pos - origin
			closer = origin + away.normalized() * 10.0
		else:
			closer = _Hazard.leave_goal(tree, pos, origin)
		if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(closer) > 1.5:
			bot.set_target(closer)
		bot.extra_held = PackedStringArray(["sprint"])
		bot.tick(pos, _yaw(player), dt)
		return ""
	var stand := _chip_stand(tree, _chip_cell, pos)
	if stand == Vector2.INF:
		_chip_cell = Vector2.INF
		return ""
	if pos.distance_to(stand) > 0.7:
		if not bot.has_target or bot.gave_up or bot.target.distance_to(stand) > 0.75:
			bot.set_target(stand)
		var extras := PackedStringArray()
		if pos.distance_to(stand) > 6.0:
			extras.append("sprint")
		bot.extra_held = extras
		bot.tick(pos, _yaw(player), dt)
		return ""
	bot.release()
	bot.input.begin_tick()
	bot.input.aim_column(player, _chip_cell.x, _chip_cell.y)
	if not _aim_on_foe(player, _chip_cell):
		_aim_wait += dt
		if _aim_wait < AIM_WAIT:
			return ""
	else:
		_aim_wait = 0.0
	if not _pick:
		if bot.input.pulse("hotbar_2"):
			_pick = true
		return ""
	_attack_wait -= dt
	if _attack_wait > 0.0:
		return ""
	if not bot.input.pulse("attack"):
		return ""
	_attack_wait = 0.35
	_chip_swings += 1
	if _xp > _chip_xp:
		_chip_xp = _xp
		_chip_swings = 0
		_chip_cell = Vector2.INF
		return ""
	if _chip_swings >= 8:
		_chip_cell = Vector2.INF
		_chip_swings = 0
		_pick = false
	return ""


func _find_mass(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := 1.0e9
	var ox := floori(pos.x)
	var oz := floori(pos.y)
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var at := Vector2(float(ox + dx) + 0.5, float(oz + dz) + 0.5)
			if not _Farm.chip_cell_ok(at, origin, _depth(tree, at)):
				continue
			if at.distance_to(origin) < _chip_gap:
				continue
			if _chip_stand(tree, at, pos) == Vector2.INF:
				continue
			var dist := pos.distance_to(at)
			if dist < best_d:
				best_d = dist
				best = at
	return best


func _chip_stand(tree: SceneTree, cell: Vector2, pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := 1.0e9
	var cx := floori(cell.x)
	var cz := floori(cell.y)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var at := Vector2(float(cx + dx) + 0.5, float(cz + dz) + 0.5)
			if at.distance_to(cell) > 2.4 or at.distance_to(cell) < 1.15:
				continue
			if _Hazard.burning(tree, at):
				continue
			var walk := at.distance_to(pos)
			if walk < best_d:
				best_d = walk
				best = at
	return best


func _depth(tree: SceneTree, at: Vector2) -> float:
	return _Hazard.depth_at(tree, at)


func _heart_hp(tree: SceneTree) -> float:
	if tree == null:
		return -1.0
	var crystal := tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return -1.0
	var prog: Dictionary = crystal.get_spawn_progress()
	return float(prog.get("crystal_health", -1.0))


func _note_down() -> void:
	if _demo != "":
		var hold := _Pace.RESULT_HOLD + _Pace.SETTLE
		if _demo_age < 9.0:
			hold = maxf(hold, 9.0 - _demo_age)
		_demo_hold = hold
	_foe_id = ""
	_foe_age = 0.0
	_sword = false


func _usable(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if _skipped.has(str(row.get("id", ""))):
			continue
		out.append(row)
	return out


func _seek_xp(dt: float, tree: SceneTree, player: Node, origin: Vector2, pos: Vector2) -> String:
	if _site_key == "" and _visits < _Farm.SITE_CAP:
		var world = _World.get_active()
		var sites: Array = []
		if world != null:
			sites = _Walk.treasure_sites(world.feature_cells)
		var site := _Farm.next_site(pos, sites, _done, _visits)
		if not site.is_empty():
			_arm_site(site, tree)
	if _site_key != "":
		return _tick_site(dt, tree, player, pos)
	_quiet += dt
	_hold_pool(dt, tree, player, origin)
	return ""


func _arm_site(site: Dictionary, tree: SceneTree) -> void:
	_site_key = str(site.get("key", ""))
	_site_at = site.get("xz", Vector2.ZERO)
	_site_age = 0.0
	_site_limit = _Walk.leg_limit(float(site.get("distance", 0.0)))
	_site_mark = _ruin_count(tree)
	_site_inside = 0.0
	_site_opened = false
	_site_noted = false
	_site_resumes = 0
	bot.stuck_limit = 12
	bot.release()
	print("SHOWCASE treasure seek %s dist %.0f" % [_site_key, float(site.get("distance", 0.0))])


func _tick_site(dt: float, tree: SceneTree, player: Node, pos: Vector2) -> String:
	_site_age += dt
	if _Hazard.burning(tree, pos):
		_exit_hazard(dt, tree, player, _site_at, _site_at)
		return ""
	if pos.distance_to(_site_at) > SITE_STAND:
		_site_inside = 0.0
		var plan: Dictionary = _Walk.approach(pos, _site_at, SITE_STAND)
		var goal: Vector2 = plan.get("goal", _site_at)
		if not bot.has_target or bot.gave_up or bot.target.distance_to(goal) > 2.0:
			if bot.gave_up and _site_resumes < 4 and _site_age < _site_limit:
				_site_resumes += 1
			elif bot.gave_up or _site_age >= _site_limit:
				_drop_site(false)
				return ""
			bot.set_target(goal)
		var extras := PackedStringArray()
		if pos.distance_to(goal) > 6.0:
			extras.append("sprint")
		if _submerged(player):
			extras.append("jump")
		bot.extra_held = extras
		bot.tick(pos, _yaw(player), dt)
		return ""
	bot.release()
	bot.input.begin_tick()
	var rot := _Nav.face_action(pos, _site_at, _yaw(player))
	if rot != "":
		bot.input.set_held(PackedStringArray([rot]))
	else:
		bot.input.set_held(PackedStringArray())
	if _site_mark < 0:
		_site_mark = _ruin_count(tree)
	_site_inside += dt
	if not _site_opened and _ruin_count(tree) > _site_mark:
		_site_opened = true
	if _site_opened and not _site_noted:
		_site_noted = true
		print("SHOWCASE treasure open pass %s" % _site_key)
	var held := _site_opened and _site_inside >= _Pace.PRE_PAUSE + _Pace.RESULT_HOLD
	var missed := not _site_opened and _site_inside >= 8.0
	if (held or missed) and _site_age >= 10.0:
		if missed:
			print("SHOWCASE treasure open miss %s" % _site_key)
		_drop_site(true)
	return ""


func _drop_site(keep: bool) -> void:
	if _site_key != "":
		_done[_site_key] = true
	if keep:
		_visits += 1
	_site_key = ""
	_site_at = Vector2.ZERO
	_site_mark = -1
	bot.stuck_limit = 0
	bot.release()


func _ruin_count(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var director := tree.get_first_node_in_group("living_world_director")
	if director != null and director.has_method("get_discovered_ruin_count"):
		return int(director.get_discovered_ruin_count())
	return 0


func _fight(dt: float, tree: SceneTree, player: Node, choice: Dictionary, origin: Vector2) -> String:
	var kind := str(choice.get("kind", ""))
	var foe: Vector2 = choice.get("xz", Vector2.ZERO)
	var fid := str(choice.get("id", ""))
	if fid != _foe_id:
		_foe_id = fid
		_foe_age = 0.0
		_sword = false
		_attack_wait = 0.0
		if _bow > 0 and _bow < 4:
			_bow = 0
		if kind != "" and kind != "crystal_mite":
			_demo = "combat_%s" % kind
			_demo_age = 0.0
			_demo_hold = 0.0
	_foe_age += dt
	if _demo != "":
		_demo_age += dt
	if _foe_age > 28.0:
		_skipped[fid] = true
		_foe_id = ""
		_foe_age = 0.0
		if _demo != "" and _demo_age < 9.0:
			_demo_hold = 9.0 - _demo_age
		bot.release()
		return ""
	var pos := _xz(player)
	bot.input.aim_column(player, foe.x, foe.y)
	if _Hazard.burning(tree, pos):
		_exit_hazard(dt, tree, player, foe, origin)
		return ""
	if _ratio(player) <= HEAL_RATIO and _herbs(player) > 0:
		return _heal_or_leave(dt, player, foe)
	if _ratio(player) <= 0.30:
		return _heal_or_leave(dt, player, foe)
	if pos.distance_to(foe) < 1.1:
		_back_off(dt, player, pos, foe)
		return ""
	var stand := _Hazard.strike_stand(tree, pos, foe)
	if stand == Vector2.INF:
		_exit_hazard(dt, tree, player, foe, origin)
		return ""
	if pos.distance_to(stand) > 0.65 or pos.distance_to(foe) > _Hazard.HIT_COLUMNS:
		_close_in(dt, player, stand, pos.distance_to(stand))
		return ""
	_strike(dt, player, pos, foe, kind)
	return ""


func _heal_or_leave(dt: float, player: Node, foe: Vector2) -> String:
	var pos := _xz(player)
	_back_off(dt, player, pos, foe)
	if _herbs(player) <= 0 or _heal_wait > 0.0:
		return ""
	if _heal == 0:
		if bot.input.pulse("hotbar_6"):
			_heal = 1
		return ""
	if not bot.input.pulse("build_place"):
		return ""
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
		_aim_wait = 0.0
		return
	if pos.distance_to(foe) > _Hazard.HIT_COLUMNS:
		return
	if not _aim_on_foe(player, foe):
		_aim_wait += dt
		if _aim_wait < AIM_WAIT:
			return
	else:
		_aim_wait = 0.0
	if kind == "crystal_mite" and bow_phase != "off":
		if bow_phase == "wait":
			return
		if bow_phase == "run":
			_bow_beat(dt)
			return
	if kind == "crystal_mite" and _bow == 0 and bow_phase == "off":
		if age < 4.2:
			return
		bow_phase = "wait"
		return
	if _demo != "" and _demo_age < _Pace.PRE_PAUSE:
		return
	if not _sword:
		if bot.input.pulse("hotbar_1"):
			_sword = true
		return
	_attack_wait -= dt
	if _attack_wait > 0.0:
		return
	if bot.input.pulse("attack"):
		_attack_wait = 0.48


func arm_bow() -> void:
	bow_phase = "run"
	_bow = 1
	_bow_age = 0.0


func finish_bow() -> void:
	bow_phase = "off"
	_bow = 4
	_sword = false
	_attack_wait = 0.48


func _bow_beat(dt: float) -> void:
	if _bow == 1:
		if not bot.input.pulse("hotbar_3"):
			return
		_bow = 2
		_bow_age = 0.0
		return
	if _bow == 2:
		_bow_age += dt
		if _bow_age < _Pace.PRE_PAUSE:
			return
		if not bot.input.pulse("attack"):
			return
		print("SHOWCASE bow attack")
		bow_logged = true
		_bow = 3
		_bow_age = 0.0
		return
	if _bow == 3:
		_bow_age += dt
		if _bow_age < _Pace.RESULT_HOLD:
			return
		_bow = 4
		_bow_age = 0.0
		return
	_bow_age += dt
	if _bow_age < _Pace.SETTLE:
		return
	bow_phase = "done"
	_sword = false
	_attack_wait = 0.48


func _hold_pool(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> void:
	var pos := _xz(player)
	var goal := _safe_pool(tree, pos, origin)
	if _Hazard.burning(tree, pos) or pos.distance_to(goal) > 0.8:
		if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(goal) > 1.2:
			bot.set_target(goal)
		bot.extra_held = PackedStringArray(["sprint"])
		bot.tick(pos, _yaw(player), dt)
		if _ratio(player) < 0.72 and _herbs(player) > 0 and _heal_wait <= 0.0:
			_heal_idle()
		return
	bot.release()
	if _ratio(player) < 0.72 and _herbs(player) > 0 and _heal_wait <= 0.0:
		_heal_idle()


func _heal_idle() -> void:
	if _heal == 0:
		if bot.input.pulse("hotbar_6"):
			_heal = 1
		return
	if not bot.input.pulse("build_place"):
		return
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
			continue
		if not node.killed.is_connected(_on_enemy_killed):
			node.killed.connect(_on_enemy_killed)
			_bound.append(node)
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
	for node in tree.get_nodes_in_group("world_entity"):
		if not is_instance_valid(node):
			continue
		var wild := str(node.get("entity_kind"))
		if _Farm.prefer_kind(wild, {}) < 0:
			continue
		if float(node.get("health")) <= 0.0:
			continue
		if node.has_signal("died") and not node.died.is_connected(_on_wildlife_died):
			node.died.connect(_on_wildlife_died)
			_bound.append(node)
		var body := node as Node3D
		if body == null:
			continue
		var wild_id := str(node.get_instance_id())
		still[wild_id] = wild
		var wild_col := _Move.column_pos(body.global_position)
		rows.append({
			"id": wild_id,
			"kind": wild,
			"xz": Vector2(float(wild_col.x) + 0.5, float(wild_col.y) + 0.5),
		})
	_alive = still
	return rows


func _on_wildlife_died(body: Node, _at: Vector2i) -> void:
	if body == null or not is_instance_valid(body):
		return
	var kind := str(body.get("entity_kind"))
	if _Farm.prefer_kind(kind, {}) < 0:
		return
	var source := str(body.get("_last_damage_source"))
	if not _Hazard.accepts_kill(kind, source != ""):
		return
	killed[kind] = int(killed.get(kind, 0)) + 1
	seen[kind] = true
	print("KILL %s" % kind)


func _on_enemy_killed(enemy_id: StringName, _world_pos: Vector2i, player_killed: bool) -> void:
	var kind := str(enemy_id)
	if not _Hazard.accepts_kill(kind, player_killed):
		return
	killed[kind] = int(killed.get(kind, 0)) + 1
	seen[kind] = true
	print("KILL %s" % kind)


func _exit_hazard(dt: float, tree: SceneTree, player: Node, foe: Vector2, origin: Vector2) -> void:
	var pos := _xz(player)
	var goal := _Hazard.leave_goal(tree, pos, origin)
	if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(goal) > 1.2:
		bot.set_target(goal)
	bot.extra_held = PackedStringArray(["sprint"])
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, foe.x, foe.y)
	if _ratio(player) <= 0.8 and _herbs(player) > 0 and _heal_wait <= 0.0:
		_heal_idle()


func _safe_pool(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	var goal := _Roster.pool_goal(pos, origin, _Roster.POOL_STAND)
	if tree == null:
		return goal
	if _Hazard.burning(tree, pos) or _Hazard.burning(tree, goal):
		return _Hazard.leave_goal(tree, pos, origin)
	return goal


func _aim_on_foe(player: Node, foe: Vector2) -> bool:
	if player == null:
		return false
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return true
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return true
	var cell := Vector2(float(floori(shared.x)) + 0.5, float(floori(shared.z)) + 0.5)
	var want := Vector2(float(floori(foe.x)) + 0.5, float(floori(foe.y)) + 0.5)
	return cell.distance_to(want) <= 1.15


func _watch_level(tree: SceneTree) -> void:
	var node := tree.get_first_node_in_group("progression_service")
	if node == null:
		return
	_xp = int(node.xp)
	var level := int(node.level)
	if level > _level:
		_level = level
		print("LEVEL %d" % level)
	if _announced or not _Farm.ready(_level, _xp):
		return
	_announced = true
	print("SHOWCASE xp ready level %d earned %d" % [_level, _Farm.earned(_level, _xp)])


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
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	return 0.0
