extends RefCounted

const _Crystal = preload("res://scripts/honest_bot/honest_crystal.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _Relic = preload("res://ui/relic_choice_panel.gd")

const CRYSTAL_LIMIT := 150.0
const BOSS_LIMIT := 120.0
const WIN_LIMIT := 90.0
const WIN_HOLD := 3.0
const SPACE_COLUMNS := 1.75
const HEAL_RATIO := 0.78
const SWORD_REACH := 2.55

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
var _armed := false
var _clocks := {"crystal": 0.0, "boss": 0.0, "win_screen": 0.0}


func begin(id: String) -> void:
	seg = id
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
	_pest_sword = false
	_pest_wait = 0.0
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
	if _needs_herb(player):
		_use_herb()
		return ""
	var seen_hp := _hp(tree)
	if seen_hp.y > 0.0 and seen_hp.x < seen_hp.y - 0.5:
		_dropped = true
	var crowd := _close_crowd(tree, player)
	if not crowd.is_empty():
		_space_from(dt, tree, player, crowd)
		_drain()
		_note_hp()
		return _status(dt, tree)
	if _bosses(tree).is_empty() and _walk_stand(dt, tree, player):
		_note_hp()
		return _status(dt, tree)
	_drive(dt, tree, player)
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
		var toward := origin - pos
		if toward.length() > 1.5:
			nav = pos + toward.normalized() * 1.5
		else:
			nav = pos
	heart.set_vitals(float(player.health), float(player.max_health))
	heart.observe_crystal(nav, hp.x, hp.y)
	heart.observe_foes(bosses)
	heart.fight.chip_skills = not bosses.is_empty()
	var aim := origin + Vector2(0.5, 0.5)
	if not bosses.is_empty():
		aim = bosses[0].get("xz", aim)
	var dist := pos.distance_to(origin)
	if bosses.is_empty() and dist > SWORD_REACH + 0.4:
		heart.fight.bot.extra_held = PackedStringArray(["sprint"])
	else:
		heart.fight.bot.extra_held = PackedStringArray()
	heart.tick(pos, _yaw(player), dt)
	heart.fight.bot.input.aim_column(player, aim.x, aim.y)
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
			return "pass"
	elif seg == "boss":
		if heart.destroyed and heart.boss_kills < 1:
			print("FAIL heart emptied while the warden lived")
			return "fail"
		if heart.boss_kills >= 1 and not heart.fighting_boss:
			return "pass"
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


func _at_line() -> bool:
	if heart.crystal_max <= 0.0:
		return false
	return heart.crystal_hp <= heart.crystal_max * _Crystal.BOSS_LINE + 0.01


func tick_clock(step: float) -> void:
	if seg == "":
		return
	_clocks[seg] = float(_clocks.get(seg, 0.0)) + step


func _walk_stand(dt: float, tree: SceneTree, player: Node) -> bool:
	if seg != "crystal":
		return false
	var origin := _origin(tree)
	var pos := _xz(player)
	var stand := _shallow_stand(tree, origin)
	var here := _feet_depth(tree, pos)
	if not _stand_logged:
		_stand_logged = true
		print("SHOWCASE stand %.0f,%.0f depth %.2f feet %.2f player %.0f/%.0f" % [
			stand.x, stand.y, _feet_depth(tree, stand), here,
			float(player.health), float(player.max_health),
		])
	if here < 0.25 and _in_sword_range(pos, origin):
		return false
	if pos.distance_to(stand) <= 0.75 and _feet_depth(tree, stand) + 0.05 >= here:
		return false
	var bot = heart.fight.bot
	bot.extra_held = PackedStringArray(["sprint"])
	if not bot.has_target or bot.gave_up or bot.target.distance_to(stand) > 0.6:
		bot.set_target(stand)
	bot.tick(pos, _yaw(player), dt)
	bot.input.aim_column(player, origin.x + 0.5, origin.y + 0.5)
	return true


func _shallow_stand(tree: SceneTree, origin: Vector2) -> Vector2:
	var best := origin + Vector2(0.5, 0.5)
	var best_depth := _feet_depth(tree, best)
	var ox := int(round(origin.x))
	var oz := int(round(origin.y))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var at := Vector2(float(ox + dx) + 0.5, float(oz + dz) + 0.5)
			if at.distance_to(origin + Vector2(0.5, 0.5)) > SWORD_REACH:
				continue
			var depth := _feet_depth(tree, at)
			if depth < best_depth - 0.01:
				best_depth = depth
				best = at
	return best


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
		bot.input.pulse("hotbar_1")
		_pest_sword = true
		return
	_pest_wait -= dt
	if _pest_wait <= 0.0:
		bot.input.pulse("attack")
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
	for sign in [-1.0, 1.0]:
		var cand := pos + away * 2.2 + tangent * sign * 2.2
		var to_heart := cand - center
		if to_heart.length() > SWORD_REACH:
			cand = center + to_heart.normalized() * (SWORD_REACH - 0.15)
		var gap := cand.distance_to(threat)
		var score := gap - _feet_depth(tree, cand) * 6.0
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
	heart.fight.chip_skills = not bosses.is_empty()
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
	heart.fight.bot.input.click_at(button, at, pressed)
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
		input.pulse("hotbar_6")
		_heal = 1
		return
	input.pulse("build_place")
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
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	return 0.0
