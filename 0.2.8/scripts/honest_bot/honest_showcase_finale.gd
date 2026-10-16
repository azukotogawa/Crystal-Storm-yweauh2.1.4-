extends RefCounted

const _Crystal = preload("res://scripts/honest_bot/honest_crystal.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _Relic = preload("res://ui/relic_choice_panel.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Hazard = preload("res://scripts/honest_bot/honest_hazard.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")

const CRYSTAL_LIMIT := 240.0
const BOSS_LIMIT := 150.0
const WIN_LIMIT := 90.0
const WIN_HOLD := 5.0
const SPACE_COLUMNS := 1.75
const HEAL_RATIO := 0.78
const SAFE_DEPTH := 0.25
const POKE_RATIO := 0.62
const SWORD_REACH := 2.8
const SWING_GAP := 0.62
const CARVE_GAP := 0.28

var heart = _Crystal.new()
var caption := ""
var seg := ""
var _seen := 0
var _hp_shown := -1
var _dropped := false
var _hold := 0.0
var _heal := 0
var _heal_wait := 0.0
var _relic := 0
var _pest_sword := false
var _pest_wait := 0.0
var _relic_frames := 0
var _stand_logged := false
var _camp_logged := false
var _gap := 0.0
var _aim_hold := 0.0
var _poking := false
var _boss_wait := 0.0
var _armed := false
var _intro := 0.0
var _exit_age := -1.0
var _carve := Vector2.INF
var _carve_pick := false
var _carve_logged := false
var _clocks := {"crystal": 0.0, "boss": 0.0, "win_screen": 0.0}


func begin(id: String) -> void:
	seg = id
	_intro = 0.0
	_exit_age = -1.0
	caption = id
	if id != "crystal" and _armed:
		return
	heart = _Crystal.new()
	_armed = true
	_seen = 0
	_hp_shown = -1
	_dropped = false
	_hold = 0.0
	_heal = 0
	_heal_wait = 0.0
	_relic = 0
	_relic_frames = 0
	_stand_logged = false
	_camp_logged = false
	_gap = 0.0
	_aim_hold = 0.0
	_poking = false
	_boss_wait = 0.0
	_pest_sword = false
	_pest_wait = 0.0
	_carve = Vector2.INF
	_carve_pick = false
	_carve_logged = false
	caption = id


func release() -> void:
	if heart != null:
		heart.release()


func tick(step: float, tree: SceneTree, player: Node) -> String:
	var dt := step
	if dt <= 0.0:
		dt = 1.0 / 60.0
	_heal_wait = maxf(_heal_wait - dt, 0.0)
	tick_clock(dt)
	if player == null or tree == null or heart == null:
		print("FAIL finale missing player")
		return "fail"
	if float(player.health) <= 0.0 or heart.fight.deaths > 0:
		print("DEATH hp %.1f" % float(player.health))
		heart.release()
		return "fail"
	var relic := _click_relic()
	if relic == 1:
		return ""
	if relic == 2:
		print("FAIL relic offer stayed open")
		return "fail"
	if not _intro_ready(dt, tree, player):
		return ""
	if _exit_age >= 0.0:
		_frame_exit(dt, tree, player)
		_drain()
		_note_hp()
		return _status(dt, tree)
	_gap = maxf(_gap - dt, 0.0)
	var origin := _origin(tree)
	var pos := _xz(player)
	var aim := origin + Vector2(0.5, 0.5)
	var early_bosses := _bosses(tree)
	if not early_bosses.is_empty():
		aim = early_bosses[0].get("xz", aim)
	if _Hazard.burning(tree, pos):
		_poking = false
		_carve = Vector2.INF
		_carve_pick = false
		_goto(dt, player, _camp(tree, origin), aim)
		_drain()
		_note_hp()
		return _status(dt, tree)
	if _needs_herb(player):
		_poking = false
		var rest := _camp(tree, origin)
		if pos.distance_to(rest) > 1.2:
			_goto(dt, player, rest, aim)
		elif _needs_herb(player):
			_use_herb()
		_drain()
		_note_hp()
		return _status(dt, tree)
	var seen_hp := _hp(tree)
	if seen_hp.y > 0.0 and seen_hp.x < seen_hp.y - 0.5:
		_dropped = true
	var crowd := _close_crowd(tree, player)
	if not crowd.is_empty():
		_space_from(dt, tree, player, crowd)
		_drain()
		_note_hp()
		return _status(dt, tree)
	if _bosses(tree).is_empty():
		_swing_heart(dt, tree, player, origin, pos, false)
	else:
		_swing_boss(dt, tree, player, origin, false)
	_drain()
	_note_hp()
	return _status(dt, tree)


func _drive(dt: float, tree: SceneTree, player: Node) -> void:
	var origin := _origin(tree)
	var hp := _hp(tree)
	var pos := _xz(player)
	var bosses := _bosses(tree)
	var nav := origin
	if bosses.is_empty() and _in_sword_range(pos, origin):
		nav = pos
	heart.set_vitals(float(player.health), float(player.max_health))
	heart.observe_crystal(nav, hp.x, hp.y)
	heart.observe_foes(bosses)
	heart.fight.chip_skills = false
	var aim := origin + Vector2(0.5, 0.5)
	if not bosses.is_empty():
		aim = bosses[0].get("xz", aim)
	heart.fight.bot.extra_held = PackedStringArray()
	heart.fight.bot.input.aim_column(player, aim.x, aim.y)
	heart.tick(pos, _yaw(player), dt)
	if hp.x < hp.y - 0.5:
		_dropped = true


func _status(dt: float, tree: SceneTree) -> String:
	var limit := CRYSTAL_LIMIT
	if seg == "boss":
		limit = BOSS_LIMIT
	elif seg == "win_screen":
		limit = WIN_LIMIT
	if seg == "crystal":
		if heart.destroyed and heart.boss_kills < 1:
			print("FAIL crystal fell before the boss")
			return "fail"
		if heart.boss_kills >= 1 or heart.fighting_boss or _at_line():
			if not _dropped:
				print("FAIL crystal line without a swing")
				return "fail"
			return _hold_exit(dt)
	elif seg == "boss":
		if heart.destroyed and heart.boss_kills < 1:
			print("FAIL heart emptied while the warden lived")
			return "fail"
		if heart.boss_kills >= 1 and not heart.fighting_boss:
			return _hold_exit(dt)
	elif seg == "win_screen":
		if _victory_ready(tree):
			heart.release()
			_hold += dt
			if _hold >= WIN_HOLD:
				print("SHOWCASE win hold %.2f" % _hold)
				return "pass"
			return ""
	if float(_clocks.get(seg, 0.0)) >= limit:
		print("FAIL %s timed out %s" % [seg, heart.summary_line()])
		return "fail"
	return ""


func _frame_exit(dt: float, tree: SceneTree, player: Node) -> void:
	var origin := _origin(tree)
	var pos := _xz(player)
	var aim := origin + Vector2(0.5, 0.5)
	var bosses := _bosses(tree)
	if not bosses.is_empty():
		aim = bosses[0].get("xz", aim)
	if _feet_depth(tree, pos) >= SAFE_DEPTH:
		_goto(dt, player, _camp(tree, origin), aim)
		return
	if heart != null:
		heart.fight.bot.release()
		heart.fight.bot.input.aim_column(player, aim.x, aim.y)


func _intro_ready(dt: float, tree: SceneTree, player: Node) -> bool:
	if seg == "win_screen" or _intro >= _Pace.PRE_PAUSE:
		_intro = _Pace.PRE_PAUSE
		return true
	_intro += dt
	var origin := _origin(tree)
	var aim := origin + Vector2(0.5, 0.5)
	var bosses := _bosses(tree)
	if not bosses.is_empty():
		aim = bosses[0].get("xz", aim)
	if heart != null:
		heart.fight.bot.release()
		heart.fight.bot.input.aim_column(player, aim.x, aim.y)
	return false


func _hold_exit(dt: float) -> String:
	if _exit_age < 0.0:
		_exit_age = 0.0
	_exit_age += dt
	if _exit_age < _Pace.RESULT_HOLD + _Pace.SETTLE:
		return ""
	return "pass"


func _at_line() -> bool:
	if heart.crystal_max <= 0.0:
		return false
	return heart.crystal_hp <= heart.crystal_max * _Crystal.BOSS_LINE + 0.01


func tick_clock(step: float) -> void:
	if seg == "":
		return
	_clocks[seg] = float(_clocks.get(seg, 0.0)) + step


func _swing_heart(dt: float, tree: SceneTree, player: Node, origin: Vector2, pos: Vector2, _deep: bool) -> void:
	var aim := origin + Vector2(0.5, 0.5)
	var pad := _Hazard.sword_pad(tree, origin)
	if pad != Vector2.INF:
		_carve = Vector2.INF
		_carve_pick = false
		if pos.distance_to(pad) > 0.7 or not _in_sword_range(pos, origin):
			_goto(dt, player, pad, aim)
			return
		heart.fight.reset_weapon()
		_swing_at(dt, tree, player, origin, aim)
		return
	_carve_rim(dt, tree, player, origin, pos, aim)


func _swing_boss(dt: float, tree: SceneTree, player: Node, origin: Vector2, _deep: bool) -> void:
	var bosses := _bosses(tree)
	if bosses.is_empty():
		return
	var boss: Vector2 = bosses[0].get("xz", origin)
	var pos := _xz(player)
	if _Hazard.burning(tree, pos) or _ratio(player) < POKE_RATIO:
		_goto(dt, player, _camp(tree, origin), boss)
		return
	var stand := _Hazard.strike_stand(tree, pos, boss)
	if stand == Vector2.INF:
		stand = _Hazard.sword_pad(tree, origin)
		_boss_wait += dt
		if stand == Vector2.INF:
			_goto(dt, player, _camp(tree, origin), boss)
			return
		if pos.distance_to(boss) > _Hazard.SWORD_RANGE or pos.distance_to(stand) > 0.7:
			_goto(dt, player, stand, boss)
			return
	else:
		_boss_wait = 0.0
		if pos.distance_to(stand) > 0.7:
			_goto(dt, player, stand, boss)
			return
	heart.fight.reset_weapon()
	_swing_at(dt, tree, player, origin, boss)


func _swing_at(dt: float, tree: SceneTree, player: Node, origin: Vector2, aim: Vector2) -> void:
	var bot = heart.fight.bot
	bot.input.aim_column(player, aim.x, aim.y)
	var ready := _aim_locked(player, aim)
	if ready:
		_aim_hold = 0.0
	else:
		_aim_hold += dt
	heart.fight.aim_ready = ready or _aim_hold >= 0.35
	var facing := _Nav.face_action(_xz(player), aim, _yaw(player))
	if facing != "" or not heart.fight.aim_ready:
		bot.input.begin_tick()
		var held := PackedStringArray()
		if facing != "":
			held.append(facing)
		bot.input.set_held(held)
		bot.input.aim_column(player, aim.x, aim.y)
		return
	_drive(dt, tree, player)


func _aim_locked(player: Node, aim: Vector2) -> bool:
	if player == null:
		return false
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return true
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return true
	var cell := Vector2(float(floori(shared.x)) + 0.5, float(floori(shared.z)) + 0.5)
	var want := Vector2(float(floori(aim.x)) + 0.5, float(floori(aim.y)) + 0.5)
	return cell.distance_to(want) <= 1.15


func _carve_rim(dt: float, tree: SceneTree, player: Node, origin: Vector2, pos: Vector2, aim: Vector2) -> void:
	if _carve == Vector2.INF or not _Hazard.burning(tree, _carve):
		_carve = _Hazard.rim_carve(tree, origin)
		_carve_pick = false
	if _carve == Vector2.INF:
		_goto(dt, player, _camp(tree, origin), aim)
		return
	if not _carve_logged:
		_carve_logged = true
		print("SHOWCASE carve rim %.0f,%.0f" % [_carve.x, _carve.y])
	var stand := _Hazard.strike_stand(tree, pos, _carve)
	if stand == Vector2.INF:
		stand = _camp(tree, origin)
	if pos.distance_to(stand) > 0.7:
		_goto(dt, player, stand, _carve)
		return
	var bot = heart.fight.bot
	bot.release()
	bot.input.begin_tick()
	bot.input.aim_column(player, _carve.x, _carve.y)
	var facing := _Nav.face_action(pos, _carve, _yaw(player))
	if facing != "":
		bot.input.set_held(PackedStringArray([facing]))
		return
	if not _carve_pick:
		if bot.input.pulse("hotbar_2"):
			_carve_pick = true
		return
	_gap = maxf(_gap - dt, 0.0)
	if _gap > 0.0:
		return
	if not bot.input.pulse("attack"):
		return
	_gap = maxf(CARVE_GAP, _Pace.action_span("multi_block_break") + 0.02)
	if not _Hazard.burning(tree, _carve):
		_carve = Vector2.INF
		_carve_pick = false
		heart.fight.reset_weapon()


func _ratio(player: Node) -> float:
	if player == null:
		return 1.0
	return clampf(float(player.health) / maxf(float(player.max_health), 1.0), 0.0, 1.0)


func _camp(tree: SceneTree, origin: Vector2) -> Vector2:
	var center := origin + Vector2(0.5, 0.5)
	var best := center + Vector2(8.0, 8.0).normalized() * 8.0
	var best_dist := 9999.0
	var found := false
	for dx in range(-14, 15):
		for dz in range(-14, 15):
			var at := Vector2(origin.x + float(dx) + 0.5, origin.y + float(dz) + 0.5)
			var dist := at.distance_to(center)
			if dist < 4.2 or dist > 13.0:
				continue
			if _feet_depth(tree, at) >= SAFE_DEPTH:
				continue
			if dist < best_dist:
				best_dist = dist
				best = at
				found = true
	if not _camp_logged:
		_camp_logged = true
		print("SHOWCASE camp %.0f,%.0f depth %.2f" % [best.x, best.y, _feet_depth(tree, best)])
	if not found and not _stand_logged:
		_stand_logged = true
		print("SHOWCASE camp fallback %.0f,%.0f" % [best.x, best.y])
	return best


func _goto(dt: float, player: Node, goal: Vector2, aim: Vector2) -> void:
	var bot = heart.fight.bot
	var pos := _xz(player)
	var extras := PackedStringArray()
	if pos.distance_to(goal) > 5.0:
		extras.append("sprint")
	bot.extra_held = extras
	if bot.gave_up and bot.target.distance_to(goal) <= 0.8:
		var side := Vector2(-(pos.y - goal.y), pos.x - goal.x)
		if side.length() < 0.05:
			side = Vector2(1.0, 0.0)
		goal = pos + side.normalized() * 3.2
	if not bot.has_target or bot.gave_up or bot.arrived or bot.target.distance_to(goal) > 0.8:
		bot.set_target(goal)
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, aim.x, aim.y)


func _in_sword_range(pos: Vector2, origin: Vector2) -> bool:
	return pos.distance_to(origin + Vector2(0.5, 0.5)) <= SWORD_REACH


func _feet_depth(tree: SceneTree, at: Vector2) -> float:
	var crystal = tree.get_first_node_in_group("crystal_manager") if tree != null else null
	if crystal == null or not crystal.has_method("get_depth_at"):
		return 0.0
	return float(crystal.get_depth_at(floori(at.x), floori(at.y)))


func _close_crowd(tree: SceneTree, player: Node) -> Dictionary:
	var pos := _xz(player)
	var bosses := _bosses(tree)
	if not bosses.is_empty():
		var boss_xz: Vector2 = bosses[0].get("xz", pos)
		if pos.distance_to(boss_xz) < SPACE_COLUMNS:
			return {"xz": boss_xz, "boss": true}
		return {}
	var pest := _nearest_pest(tree, pos)
	if pest.is_empty():
		return {}
	var foe: Vector2 = pest.get("xz", pos)
	if pos.distance_to(foe) < SPACE_COLUMNS:
		return {"xz": foe, "boss": false}
	return {}


func _space_from(dt: float, tree: SceneTree, player: Node, crowd: Dictionary) -> void:
	var origin := _origin(tree)
	var pos := _xz(player)
	var threat: Vector2 = crowd.get("xz", pos)
	var aim := origin + Vector2(0.5, 0.5)
	if bool(crowd.get("boss", false)):
		aim = threat
	_watch(tree, player, origin)
	var goal := _space_goal(tree, pos, origin, threat)
	var bot = heart.fight.bot
	bot.extra_held = PackedStringArray(["sprint"])
	if not bot.has_target or bot.gave_up or bot.arrived or bot.target.distance_to(goal) > 0.8:
		bot.set_target(goal)
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, aim.x, aim.y)
	if not _pest_sword:
		if bot.input.pulse("hotbar_1"):
			_pest_sword = true
		return
	_pest_wait -= dt
	if _pest_wait <= 0.0 and bot.input.pulse("attack"):
		_pest_wait = 0.48


func _space_goal(tree: SceneTree, pos: Vector2, origin: Vector2, threat: Vector2) -> Vector2:
	var away := pos - threat
	if away.length() < 0.05:
		away = pos - (origin + Vector2(0.5, 0.5))
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var tangent := Vector2(-away.y, away.x)
	var center := origin + Vector2(0.5, 0.5)
	var best := pos + away * 3.0
	var best_score := -9999.0
	var signs: Array[float] = [-1.0, 1.0]
	for sign in signs:
		var cand: Vector2 = pos + away * 2.2 + tangent * sign * 2.2
		var to_heart: Vector2 = cand - center
		if to_heart.length() > SWORD_REACH:
			cand = center + to_heart.normalized() * (SWORD_REACH - 0.15)
		if _Hazard.burning(tree, cand):
			continue
		var gap: float = cand.distance_to(threat)
		var score: float = gap - _feet_depth(tree, cand) * 6.0
		if score > best_score:
			best_score = score
			best = cand
	return best


func _watch(tree: SceneTree, player: Node, origin: Vector2) -> void:
	var hp := _hp(tree)
	var pos := _xz(player)
	heart.set_vitals(float(player.health), float(player.max_health))
	var nav := origin
	if _bosses(tree).is_empty() and _in_sword_range(pos, origin):
		var toward := origin - pos
		if toward.length() > 1.5:
			nav = pos + toward.normalized() * 1.5
	heart.observe_crystal(nav, hp.x, hp.y)
	var bosses := _bosses(tree)
	heart.observe_foes(bosses)
	heart.fight.chip_skills = false
	if hp.x < hp.y - 0.5:
		_dropped = true


func _click_relic() -> int:
	var panel = _Relic._open
	if panel == null or not is_instance_valid(panel):
		_relic = 0
		return 0
	_relic_frames += 1
	if _relic_frames > 180:
		return 2
	var button: Button = null
	for node in panel.find_children("*", "Button", true, false):
		button = node as Button
		if button != null:
			break
	if button == null:
		return 1
	var rect := button.get_global_rect()
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return 1
	var at := rect.position + rect.size * 0.5
	var pressed := _relic == 0
	if not heart.fight.bot.input.click_at(button, at, pressed):
		return 1
	_relic = 1 if pressed else 0
	if pressed:
		print("SHOWCASE relic click")
	return 1


func _needs_herb(player: Node) -> bool:
	if _heal_wait > 0.0:
		return false
	if player == null or float(player.max_health) <= 0.0:
		return false
	if float(player.health) / float(player.max_health) > HEAL_RATIO:
		_heal = 0
		return false
	return _herbs(player) > 0


func _use_herb() -> void:
	var input = heart.fight.bot.input
	if _heal == 0:
		if input.pulse("hotbar_6"):
			_heal = 1
		return
	if not input.pulse("build_place"):
		return
	_heal = 0
	_heal_wait = 0.5
	print("SHOWCASE herb")


func _note_hp() -> void:
	if heart == null or not heart.has_crystal:
		caption = seg
		return
	var hp := int(round(heart.crystal_hp))
	var mx := int(round(heart.crystal_max))
	caption = "%s %d/%d" % [seg, hp, mx]
	if hp == _hp_shown:
		return
	_hp_shown = hp
	print("SHOWCASE crystal hp %d/%d" % [hp, mx])


func _drain() -> void:
	if heart == null:
		return
	while _seen < heart.lines.size():
		print(heart.lines[_seen])
		_seen += 1
	var stuck: PackedStringArray = heart.stuck_lines()
	if stuck.is_empty():
		return
	for line in stuck:
		print(line)
	heart.fight.bot.stuck_lines = PackedStringArray()


func _victory_ready(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var gm = tree.get_first_node_in_group("game_manager")
	if gm == null:
		return false
	if int(gm.run_state) != int(gm.RunState.WON):
		return false
	if str(gm.victory_reason) != "crystal":
		return false
	var overlay = tree.get_first_node_in_group("game_overlay")
	if overlay == null:
		return false
	var title := overlay.get_node_or_null("Panel/VBox/Title") as Label
	if title == null:
		return false
	return title.visible and title.text == "Victory — Crystal Destroyed"


func _nearest_pest(tree: SceneTree, pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := SPACE_COLUMNS
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		if str(node.get("enemy_id")) == "origin_warden":
			continue
		var foe := _body_xz(node)
		if foe == Vector2.INF:
			continue
		var dist := pos.distance_to(foe)
		if dist < best_d:
			best_d = dist
			best = {"xz": foe, "dist": dist}
	for node in tree.get_nodes_in_group("world_entity"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var cfg = node.get("config")
		if cfg == null or float(cfg.get("contact_damage")) <= 0.0:
			continue
		var foe := _body_xz(node)
		if foe == Vector2.INF:
			continue
		var dist := pos.distance_to(foe)
		if dist < best_d:
			best_d = dist
			best = {"xz": foe, "dist": dist}
	return best


func _body_xz(node: Node) -> Vector2:
	var body := node as Node3D
	if body == null:
		return Vector2.INF
	var col := _Move.column_pos(body.global_position)
	return Vector2(float(col.x) + 0.5, float(col.y) + 0.5)


func _bosses(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group("origin_boss"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		out.append({
			"id": "boss-%d" % node.get_instance_id(),
			"xz": Vector2(float(col.x) + 0.5, float(col.y) + 0.5),
		})
	return out


func _origin(tree: SceneTree) -> Vector2:
	var crystal = tree.get_first_node_in_group("crystal_manager") if tree != null else null
	if crystal == null or not crystal.has_method("get_origin_cell"):
		return Vector2.ZERO
	var cell: Vector2i = crystal.get_origin_cell()
	return Vector2(float(cell.x), float(cell.y))


func _hp(tree: SceneTree) -> Vector2:
	var crystal = tree.get_first_node_in_group("crystal_manager") if tree != null else null
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return Vector2.ZERO
	var prog: Dictionary = crystal.get_spawn_progress()
	return Vector2(float(prog.get("crystal_health", 0.0)), float(prog.get("crystal_max_health", 0.0)))


func _herbs(player: Node) -> int:
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return 0
	return int(inv.count_item("herb"))


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
