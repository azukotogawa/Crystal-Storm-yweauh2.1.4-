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
var _swing_left := 0.0
var _burn_wind := false
var _open_age := 0.0
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
var _chip_skip: Dictionary = {}
var _home_logged := false
var _home_arrived := false
var _home_age := 0.0
var _home_limit := 0.0
var _home_mark := -1.0
var _stand := Vector2.INF
var _dodge := Vector2.INF


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
	_swing_left = 0.0
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
	_open_age = 0.0
	_burn_wind = false
	_site_opened = false
	_site_noted = false
	_visits = 0
	_site_resumes = 0
	_pool_visit = 0.0
	_pool_done = false
	_done = {}
	_chip_skip = {}
	_home_logged = false
	_home_arrived = false
	_home_age = 0.0
	_home_limit = 0.0
	_home_mark = -1.0
	_stand = Vector2.INF
	_dodge = Vector2.INF
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
	if _Farm.farm_clock_open(_level, _xz(player).distance_to(origin)):
		age += dt
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
	if _Hazard.must_leave(tree, pos):
		_exit_hazard(dt, tree, player, pos, origin)
		return ""
	if not orbits():
		if _Hazard.ring_hot(tree, pos):
			_leave_ring(dt, tree, player, pos, origin)
			return ""
		if _off_rim(tree, pos, origin):
			var close := _nearest_mite(tree, pos)
			var foe_at: Vector2 = close.get("xz", pos)
			if not close.is_empty() and pos.distance_to(foe_at) <= 6.0 and _mite_ready(tree, pos, close, origin):
				return _fight(dt, tree, player, close, origin)
			_return_rim(dt, tree, player, origin)
			return ""
	if not _Farm.demo_ready(_level) and not _home_arrived and pos.distance_to(origin) > _Farm.HOME_COLUMNS:
		if _slip(dt, tree, player, pos, _travel_goal(pos, origin), false):
			return ""
		return _seek_xp(dt, tree, player, origin, pos)
	if _home_logged and not _home_arrived:
		_home_arrived = true
		age = 0.0
		print("SHOWCASE farm home dist %.0f" % pos.distance_to(origin))
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
		if choice.is_empty() and not orbits():
			choice = _Farm.pick_seek(rows, pos, killed, _Farm.MITE_SEEK, _skipped, false)
		choice = prefer_locked(rows, pos, _Farm.MITE_SEEK if not orbits() else _Roster.SCAN_COLUMNS, choice)
		if str(choice.get("kind", "")) == "spawn_elite":
			_skipped[str(choice.get("id", ""))] = true
			choice = {}
		if not orbits() and not choice.is_empty() and not _mite_ready(tree, pos, choice, origin):
			choice = {}
		if not choice.is_empty():
			_quiet = 0.0
			return _fight(dt, tree, player, choice, origin)
		if not orbits() and pos.distance_to(origin) > _Farm.HEART_STAND + 2.0:
			var closer := _Hazard.skirt_goal(tree, pos, _rim_goal(tree, pos, origin, _Farm.HEART_STAND))
			if closer.distance_to(origin) + 0.5 < pos.distance_to(origin):
				bot.chapter = "combat_crystal_mite"
				bot.objective = "mite approach"
				bot.stuck_limit = 24
				_step_clear(dt, tree, player, closer, origin, true)
				return ""
		if orbits() and _slip(dt, tree, player, pos, _travel_goal(pos, origin), false):
			return ""
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
		threat = prefer_locked(rows, pos, CHIP_LEASH, threat)
		if not threat.is_empty():
			_pick = false
			_quiet = 0.0
			return _fight(dt, tree, player, threat, origin)
		if orbits() and _slip(dt, tree, player, pos, _travel_goal(pos, origin), false):
			return ""
		return _chip(dt, tree, player, origin)
	if orbits() and _slip(dt, tree, player, pos, _travel_goal(pos, origin), false):
		return ""
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
	if _note_burn(tree, pos):
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
		_drop_chip()
	if _chip_cell != Vector2.INF and _chip_skip.has(_Farm.site_key(_chip_cell)):
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
			if bot.gave_up:
				var side := Vector2(-away.y, away.x)
				if side.length() < 0.05:
					side = Vector2(1.0, 0.0)
				closer = closer + side.normalized() * 6.0
		else:
			closer = _Hazard.leave_goal(tree, pos, origin)
		closer = _Hazard.skirt_goal(tree, pos, closer)
		if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(closer) > 1.5:
			bot.set_target(closer)
		bot.extra_held = _Hazard.with_sprint(tree, pos, closer, _ratio(player), PackedStringArray(), true)
		bot.tick(pos, _yaw(player), dt)
		return ""
	var stand := _chip_stand(tree, _chip_cell, pos)
	if stand == Vector2.INF:
		_skip_chip(_chip_cell)
		return ""
	if pos.distance_to(stand) > 0.7:
		if bot.gave_up and bot.target.distance_to(stand) <= 0.75:
			_skip_chip(_chip_cell)
			return ""
		stand = _Hazard.skirt_goal(tree, pos, stand)
		if not bot.has_target or bot.gave_up or bot.target.distance_to(stand) > 0.75:
			bot.set_target(stand)
		var extras := PackedStringArray()
		bot.extra_held = _Hazard.with_sprint(tree, pos, stand, _ratio(player), extras, pos.distance_to(stand) > 6.0)
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
	_attack_wait = _Pace.action_span("multi_block_break") + 0.05
	_chip_swings += 1
	if _xp > _chip_xp:
		_chip_xp = _xp
		_chip_swings = 0
		_chip_cell = Vector2.INF
		return ""
	if _chip_swings >= 8:
		_skip_chip(_chip_cell)
	return ""


func _find_mass(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	var found := _scan_mass(tree, pos, origin, floori(pos.x), floori(pos.y), 12)
	if found != Vector2.INF:
		return found
	if pos.distance_to(origin) <= 28.0:
		return _scan_mass(tree, pos, origin, floori(origin.x), floori(origin.y), 14)
	return Vector2.INF


func _scan_mass(tree: SceneTree, pos: Vector2, origin: Vector2, ox: int, oz: int, reach: int) -> Vector2:
	var best := Vector2.INF
	var best_d := 1.0e9
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var at := Vector2(float(ox + dx) + 0.5, float(oz + dz) + 0.5)
			if _chip_skip.has(_Farm.site_key(at)):
				continue
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


func _skip_chip(cell: Vector2) -> void:
	_chip_skip[_Farm.site_key(cell)] = true
	_chip_cell = Vector2.INF
	_chip_swings = 0
	_pick = false


func _drop_chip() -> void:
	_chip_cell = Vector2.INF
	_chip_swings = 0


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
	_stand = Vector2.INF


func _usable(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if _skipped.has(str(row.get("id", ""))):
			continue
		out.append(row)
	return out


func _travel_goal(pos: Vector2, origin: Vector2) -> Vector2:
	if bot.has_target:
		return bot.target
	return origin if origin.distance_to(pos) > 0.5 else pos + Vector2(12.0, 0.0)


func _leave_leash(dt: float, tree: SceneTree, player: Node, pos: Vector2, travel: Vector2) -> bool:
	var proposed := _Hazard.leash_step(pos, travel, tree)
	if proposed == Vector2.INF:
		_dodge = Vector2.INF
		return false
	var dodge := _Hazard.keep_dodge(pos, _dodge, proposed)
	_dodge = dodge
	var flee := _Hazard.flee_toward(pos, dodge, _yaw(player))
	dodge = _Hazard.skirt_goal(tree, pos, dodge)
	if not bot.has_target or bot.gave_up or bot.target.distance_to(dodge) > 1.5:
		bot.set_target(dodge)
	var held := PackedStringArray()
	held.append(flee)
	bot.extra_held = _Hazard.with_sprint(tree, pos, dodge, _ratio(player), held, true)
	bot.tick(pos, _yaw(player), dt)
	return true


func _slip(dt: float, tree: SceneTree, player: Node, pos: Vector2, travel: Vector2, bodies: bool) -> bool:
	var threats: Array = []
	for row in _Hazard.guardian_bubbles(tree):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if bodies or bool(row.get("hard", false)):
			threats.append(row)
	var proposed := _Hazard.dodge_point(pos, travel, threats)
	if proposed == Vector2.INF:
		_dodge = Vector2.INF
		return false
	var dodge := _Hazard.keep_dodge(pos, _dodge, proposed)
	_dodge = dodge
	var flee := _Hazard.flee_toward(pos, dodge, _yaw(player))
	dodge = _Hazard.skirt_goal(tree, pos, dodge)
	if not bot.has_target or bot.gave_up or bot.target.distance_to(dodge) > 1.5:
		bot.set_target(dodge)
	var held := PackedStringArray()
	held.append(flee)
	bot.extra_held = _Hazard.with_sprint(tree, pos, dodge, _ratio(player), held, true)
	bot.tick(pos, _yaw(player), dt)
	if _ratio(player) <= HEAL_RATIO and _herbs(player) > 0 and _heal_wait <= 0.0:
		_heal_idle()
	return true


func _seek_xp(dt: float, tree: SceneTree, player: Node, origin: Vector2, pos: Vector2) -> String:
	if _ratio(player) <= HEAL_RATIO and _herbs(player) > 0 and _heal_wait <= 0.0:
		_heal_idle()
	if _Hazard.must_leave(tree, pos):
		_exit_hazard(dt, tree, player, origin, origin)
		return ""
	var home := _Roster.pool_goal(pos, origin, 18.0)
	if orbits() and _leave_leash(dt, tree, player, pos, home):
		return ""
	if orbits() and _slip(dt, tree, player, pos, home, true):
		return ""
	var bite := _Farm.pick_seek(_usable(_sense(tree)), pos, killed, 8.0, _skipped, false)
	if not bite.is_empty() and str(bite.get("kind", "")) != "spawn_elite":
		_quiet = 0.0
		return _fight(dt, tree, player, bite, origin)
	if not _home_arrived and pos.distance_to(origin) > _Farm.HOME_COLUMNS:
		if _site_key != "":
			_drop_site(false)
		var dist := pos.distance_to(origin)
		if not _home_logged:
			_home_logged = true
			_home_age = 0.0
			_home_limit = _Walk.leg_limit(dist)
			_home_mark = dist
			print("SHOWCASE farm walk home dist %.0f" % dist)
		else:
			_home_age += dt
			if absf(dist - _home_mark) >= 8.0:
				print("SHOWCASE farm home progress dist %.0f" % dist)
				_home_mark = dist
		bot.chapter = "combat_crystal_mite"
		bot.objective = "farm walk home"
		if bot.gave_up or _home_age >= _home_limit:
			if not bot.gave_up:
				bot.fail_closed(pos, "walk home exceeded %.0fs at dist %.0f" % [_home_limit, dist])
			print("FAIL farm walk home dist %.0f" % dist)
			bot.release()
			return "fail"
		var goal := _Hazard.skirt_goal(tree, pos, _clear_home(tree, pos, origin))
		if not bot.has_target or bot.home.distance_to(goal) > 2.0:
			bot.set_target(goal)
		var extras := PackedStringArray()
		extras = _Hazard.with_sprint(tree, pos, goal, _ratio(player), extras, pos.distance_to(goal) > 6.0)
		if _submerged(player):
			extras.append("jump")
		bot.extra_held = extras
		bot.tick(pos, _yaw(player), dt)
		if bot.gave_up:
			print("FAIL farm walk home dist %.0f" % pos.distance_to(origin))
			bot.release()
			return "fail"
		return ""
	if _site_key == "" and _visits < _Farm.SITE_CAP:
		var world = _World.get_active()
		var sites: Array = []
		if world != null:
			sites = _Walk.treasure_sites(world.feature_cells)
		var site := _Farm.next_site(pos, sites, _done, _visits, _Farm.FARM_SITE_REACH)
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
	_open_age = 0.0
	_site_opened = false
	_site_noted = false
	_site_resumes = 0
	bot.stuck_limit = 12
	bot.release()
	print("SHOWCASE treasure seek %s dist %.0f" % [_site_key, float(site.get("distance", 0.0))])


func _tick_site(dt: float, tree: SceneTree, player: Node, pos: Vector2) -> String:
	_site_age += dt
	if _Hazard.must_leave(tree, pos):
		_exit_hazard(dt, tree, player, _site_at, _site_at)
		return ""
	if orbits() and _leave_leash(dt, tree, player, pos, _site_at):
		return ""
	if pos.distance_to(_site_at) > SITE_STAND:
		_site_inside = 0.0
		var plan: Dictionary = _Walk.approach(pos, _site_at, SITE_STAND)
		var goal: Vector2 = _Hazard.skirt_goal(tree, pos, plan.get("goal", _site_at))
		if not bot.has_target or bot.gave_up or bot.target.distance_to(goal) > 2.0:
			if bot.gave_up and _site_resumes < 4 and _site_age < _site_limit:
				_site_resumes += 1
			elif bot.gave_up or _site_age >= _site_limit:
				_drop_site(false)
				return ""
			bot.set_target(goal)
		var extras := PackedStringArray()
		extras = _Hazard.with_sprint(tree, pos, goal, _ratio(player), extras, pos.distance_to(goal) > 6.0)
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
		_open_age = 0.0
	if _site_opened:
		_open_age += dt
	if _site_opened and not _site_noted:
		_site_noted = true
		print("SHOWCASE treasure open pass %s" % _site_key)
	var held := _site_opened and _open_age >= _Pace.banner_span("treasure") and _site_inside >= _Pace.PRE_PAUSE + _Pace.beat_hold("treasure")
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
		_stand = Vector2.INF
		_dodge = Vector2.INF
		_attack_wait = _Pace.enemy_span(_telegraph_kind(kind))
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
		_stand = Vector2.INF
		if _demo != "" and _demo_age < 9.0:
			_demo_hold = 9.0 - _demo_age
		bot.release()
		return ""
	var pos := _xz(player)
	bot.input.aim_column(player, foe.x, foe.y)
	if kind == "spawn_elite":
		var home := _Roster.pool_goal(pos, origin, 18.0)
		if orbits() and _leave_leash(dt, tree, player, pos, home):
			return ""
		if orbits() and _slip(dt, tree, player, pos, home, false):
			return ""
		_back_off(dt, player, pos, foe)
		return ""
	if slips_for(kind) and _slip(dt, tree, player, pos, foe, false):
		return ""
	if _Hazard.must_leave(tree, pos) or _note_burn(tree, pos):
		_exit_hazard(dt, tree, player, foe, origin)
		return ""
	if _ratio(player) <= HEAL_RATIO and _herbs(player) > 0:
		return _heal_or_leave(dt, player, foe)
	if _ratio(player) <= 0.30:
		return _heal_or_leave(dt, player, foe)
	if _swing_left > 0.0:
		_swing_left = maxf(_swing_left - dt, 0.0)
		_attack_wait = maxf(_attack_wait - dt, 0.0)
		_face_foe(player, pos, foe)
		return ""
	if kind == "crystal_mite" and pos.distance_to(foe) < 1.1:
		_hold_mite_rim(dt, tree, player, foe, origin)
		return ""
	if pos.distance_to(foe) < 1.1:
		_back_off(dt, player, pos, foe)
		return ""
	var stand := _Hazard.keep_stand(tree, pos, foe, _stand)
	if kind == "crystal_mite":
		var rim := _Hazard.mite_rim(tree, pos, foe)
		if rim != Vector2.INF:
			stand = rim
			if _Hazard.burning(tree, stand) or _Hazard.crosses_burn(tree, pos, stand):
				stand = _Hazard.skirt_goal(tree, pos, rim)
	_stand = stand
	if stand == Vector2.INF:
		if _home_arrived and not _Hazard.burning(tree, pos):
			bot.release()
			_face_foe(player, pos, foe)
			if _foe_age >= 2.0:
				_skipped[fid] = true
				_foe_id = ""
			return ""
		_exit_hazard(dt, tree, player, foe, origin)
		return ""
	if pos.distance_to(stand) > 0.65 or pos.distance_to(foe) > _Hazard.HIT_COLUMNS:
		_close_in(dt, tree, player, stand, pos.distance_to(stand))
		return ""
	_strike(dt, player, pos, foe, kind)
	return ""


func orbits() -> bool:
	if not _home_arrived:
		return true
	return int(killed.get("crystal_mite", 0)) > 0


func slips_for(kind: String) -> bool:
	if not orbits():
		return false
	return kind != "crystal_mite"


func prefer_locked(rows: Array, pos: Vector2, radius: float, fallback: Dictionary) -> Dictionary:
	var held := _Roster.hold_row(rows, _foe_id, pos, radius)
	if held.is_empty():
		return fallback
	return held


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


func _mite_ready(tree: SceneTree, pos: Vector2, choice: Dictionary, origin: Vector2) -> bool:
	if str(choice.get("kind", "")) != "crystal_mite":
		return false
	var foe: Vector2 = choice.get("xz", pos)
	var stand := _Hazard.mite_rim(tree, pos, foe)
	if stand == Vector2.INF or _Hazard.burning(tree, stand):
		return false
	if not _Hazard.burning(tree, pos) and _Hazard.crosses_burn(tree, pos, stand):
		return false
	if _off_rim(tree, stand, origin) and pos.distance_to(foe) > 6.0:
		return false
	return true


func _off_rim(tree: SceneTree, pos: Vector2, origin: Vector2) -> bool:
	var anchor := _anchor(tree, pos, origin)
	return pos.distance_to(origin) > anchor.distance_to(origin) + 3.0


func _anchor(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	return _rim_goal(tree, pos, origin, _Farm.HEART_STAND)


func _return_rim(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> void:
	var pos := _xz(player)
	var goal := _Hazard.skirt_goal(tree, pos, _anchor(tree, pos, origin))
	if _Hazard.burning(tree, goal) or _Hazard.enters_burn(tree, pos, goal):
		goal = _Hazard.skirt_goal(tree, pos, _Hazard.leave_goal(tree, pos, origin))
	_step_clear(dt, tree, player, goal, origin, false)


func _leave_ring(dt: float, tree: SceneTree, player: Node, pos: Vector2, origin: Vector2) -> void:
	var away := pos - origin
	if away.length_squared() < 0.04:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	var reach := _ring_escape(tree, pos)
	var proposed := _Hazard.slam_exit(pos, away, reach, origin)
	proposed = _Hazard.skirt_goal(tree, pos, proposed)
	if _Hazard.burning(tree, proposed) or _Hazard.enters_burn(tree, pos, proposed):
		proposed = _ring_side(tree, pos, away, reach)
	_step_clear(dt, tree, player, proposed, origin, true)


func _ring_escape(tree: SceneTree, pos: Vector2) -> float:
	var reach := 3.0
	for row in _Hazard.guardian_bubbles(tree):
		if typeof(row) != TYPE_DICTIONARY or not bool(row.get("hard", false)):
			continue
		var at: Vector2 = row.get("xz", pos)
		var need := float(row.get("radius", 0.0)) - pos.distance_to(at) + 1.4
		if need > reach:
			reach = need
	return reach


func _ring_side(tree: SceneTree, pos: Vector2, away: Vector2, reach: float) -> Vector2:
	var side := Vector2(-away.y, away.x)
	var best := pos
	var signs: Array[float] = [1.0, -1.0]
	for sign in signs:
		var cand := _Hazard.skirt_goal(tree, pos, pos + side * sign * (reach + 1.2))
		if _Hazard.burning(tree, cand) or _Hazard.enters_burn(tree, pos, cand):
			continue
		if cand.distance_to(pos) > best.distance_to(pos):
			best = cand
	return best


func _hold_mite_rim(dt: float, tree: SceneTree, player: Node, foe: Vector2, origin: Vector2) -> void:
	var pos := _xz(player)
	if not orbits() and _off_rim(tree, pos, origin) and pos.distance_to(foe) > 6.0:
		_return_rim(dt, tree, player, origin)
		return
	if _Hazard.must_leave(tree, pos):
		_exit_hazard(dt, tree, player, foe, origin)
		return
	var radial := pos - origin
	if radial.length() < 0.2:
		radial = Vector2(1.0, 0.0)
	else:
		radial = radial.normalized()
	var side := Vector2(-radial.y, radial.x)
	var options: Array[Vector2] = [
		pos - radial * 1.6,
		pos + side * 1.8,
		pos - side * 1.8,
	]
	var best := pos
	var best_clear := -1.0
	for cand in options:
		var step := _Hazard.skirt_goal(tree, pos, cand)
		if _Hazard.burning(tree, step) or _Hazard.enters_burn(tree, pos, step):
			continue
		if not orbits() and step.distance_to(origin) > pos.distance_to(origin) + 1.25:
			continue
		var score := step.distance_to(foe)
		if score > best_clear:
			best_clear = score
			best = step
	if best.distance_to(pos) < 0.45:
		if not _Hazard.burning(tree, pos) and pos.distance_to(foe) <= _Hazard.HIT_COLUMNS:
			_strike(dt, player, pos, foe, "crystal_mite")
			return
		_face_foe(player, pos, foe)
		return
	_step_clear(dt, tree, player, best, foe, false)


func _commit_goal(tree: SceneTree, pos: Vector2, goal: Vector2) -> void:
	var unsafe := bot.has_target and (_Hazard.burning(tree, bot.home) or _Hazard.enters_burn(tree, pos, bot.home))
	var stuck := bot.arrived and _Hazard.must_leave(tree, pos)
	if not bot.has_target or bot.gave_up or bot.home.distance_to(goal) > 2.0:
		bot.set_target(goal)
	if (unsafe or stuck) and bot.home.distance_to(goal) > 0.35:
		bot.home = goal
		bot.target = goal
		bot.arrived = false
		bot.gave_up = false


func _step_clear(dt: float, tree: SceneTree, player: Node, goal: Vector2, aim: Vector2, sprint_now: bool) -> void:
	var pos := _xz(player)
	_commit_goal(tree, pos, goal)
	bot.extra_held = _Hazard.with_sprint(tree, pos, bot.home, _ratio(player), PackedStringArray(), sprint_now)
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, aim.x, aim.y)


func _back_off(dt: float, player: Node, pos: Vector2, foe: Vector2) -> void:
	var away := pos - foe
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	var goal := pos + away * 4.0
	var tree := player.get_tree() if player != null else null
	goal = _Hazard.skirt_goal(tree, pos, goal)
	if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	bot.extra_held = _Hazard.with_sprint(tree, pos, goal, _ratio(player), PackedStringArray(), true)
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, foe.x, foe.y)


func _close_in(dt: float, tree: SceneTree, player: Node, foe: Vector2, dist: float) -> void:
	var pos := _xz(player)
	var step := _Hazard.skirt_goal(tree, pos, foe)
	if not bot.has_target or bot.gave_up or bot.target.distance_to(step) > 0.75:
		bot.set_target(step)
	bot.extra_held = _Hazard.with_sprint(tree, pos, step, _ratio(player), PackedStringArray(), dist > 6.0)
	bot.tick(pos, _yaw(player), dt)


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
		_attack_wait = _sword_gap()
		_swing_left = _Pace.action_span("sword_swing")


func _face_foe(player: Node, pos: Vector2, foe: Vector2) -> void:
	bot.input.begin_tick()
	var held := PackedStringArray()
	var rot := _Nav.face_action(pos, foe, _yaw(player))
	if rot != "":
		held.append(rot)
	bot.input.set_held(held)
	bot.input.aim_column(player, foe.x, foe.y)


func arm_bow() -> void:
	bow_phase = "run"
	_bow = 1
	_bow_age = 0.0


func finish_bow() -> void:
	bow_phase = "off"
	_bow = 4
	_sword = false
	_attack_wait = _sword_gap()


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
	_attack_wait = _sword_gap()


func _hold_pool(dt: float, tree: SceneTree, player: Node, origin: Vector2) -> void:
	var pos := _xz(player)
	var goal := _safe_pool(tree, pos, origin)
	if _Hazard.burning(tree, pos) or pos.distance_to(goal) > 0.8:
		goal = _Hazard.skirt_goal(tree, pos, goal)
		if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(goal) > 1.2:
			bot.set_target(goal)
		bot.extra_held = _Hazard.with_sprint(tree, pos, goal, _ratio(player), PackedStringArray(), true)
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
	if _Hazard.burning(tree, goal) or _Hazard.enters_burn(tree, pos, goal):
		goal = _Hazard.skirt_goal(tree, pos, goal)
	_commit_goal(tree, pos, goal)
	bot.extra_held = _Hazard.with_sprint(tree, pos, bot.home, _ratio(player), PackedStringArray(), true)
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, foe.x, foe.y)
	if _ratio(player) <= 0.8 and _herbs(player) > 0 and _heal_wait <= 0.0:
		_heal_idle()


func _safe_pool(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	var goal := _clear_home(tree, pos, origin)
	if _home_arrived and not _Hazard.burning(tree, pos) and goal.distance_to(origin) + 0.5 >= pos.distance_to(origin):
		return pos
	if tree != null and _Hazard.burning(tree, pos):
		return _Hazard.leave_goal(tree, pos, origin)
	return goal


func _clear_home(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	return _rim_goal(tree, pos, origin, 18.0)


func _rim_goal(tree: SceneTree, pos: Vector2, origin: Vector2, stand: float) -> Vector2:
	var inward := _Roster.pool_goal(pos, origin, stand)
	if tree == null or not _Hazard.burning(tree, inward):
		return inward
	var step := inward - pos
	if step.length() < 0.2:
		return pos
	var dir := step.normalized()
	var best := pos
	var span := pos.distance_to(inward)
	var walked := 1.0
	while walked < span:
		var at := pos + dir * walked
		if _Hazard.burning(tree, at):
			return best
		best = at
		walked += 1.0
	return best


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


func _sword_gap() -> float:
	return _Pace.strike_gap("sword_swing")


func _telegraph_kind(kind: String) -> String:
	if kind == "crystal_mite":
		return "mite"
	if kind == "origin_warden":
		return "boss"
	return ""


func _note_burn(tree: SceneTree, pos: Vector2) -> bool:
	var hot := _Hazard.burning(tree, pos)
	if hot and not _burn_wind:
		_burn_wind = true
		_attack_wait = maxf(_attack_wait, _Pace.enemy_span("burn_pool"))
	elif not hot:
		_burn_wind = false
	return hot


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
