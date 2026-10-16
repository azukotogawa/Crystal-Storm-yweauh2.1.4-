extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")

const ENGAGE_COLUMNS := 2.4
const RETREAT_HP_RATIO := 0.30
const RETREAT_PUSH := 8.0
const ATTACK_GAP_SEC := 0.40
const SKILL_GAP_SEC := 0.55
const SWORD_ACTION := "hotbar_1"
const ATTACK_ACTION := "attack"
const SKILL_ACTIONS: PackedStringArray = ["skill_1", "skill_2", "skill_3"]

var bot = _Bot.new()
var kills := 0
var deaths := 0
var swings := 0
var skills_used := 0
var lines: PackedStringArray = PackedStringArray()
var retreating := false
var striking := false
var _seen: Dictionary = {}
var _hp := 1.0
var _hp_max := 1.0
var _dead := false
var _sword_sent := false
var _sword_delay := 0
var _attack_wait := 0.0
var _skill_wait := 0.0
var _skill_i := 0
var chip_skills := true


func release() -> void:
	bot.release()


func summary_line() -> String:
	return "KILLS %d DEATHS %d" % [kills, deaths]


func set_vitals(hp: float, hp_max: float) -> void:
	_hp = hp
	_hp_max = maxf(hp_max, 0.0)
	if _dead:
		return
	if _hp_max > 0.0 and _hp <= 0.0:
		_dead = true
		deaths += 1
		lines.append("DEATH hp %.1f/%.1f" % [_hp, _hp_max])
		striking = false
		retreating = false
		bot.release()


func observe(seen: Array) -> void:
	var now := {}
	for item in seen:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var id := str(item.get("id", ""))
		if id == "":
			continue
		var xz: Vector2 = item.get("xz", Vector2.ZERO)
		now[id] = xz
	for id in _seen.keys():
		if not now.has(id):
			kills += 1
			lines.append("KILL %s" % str(id))
	_seen = now


func nearest_id(player_xz: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in _seen.keys():
		var d: float = player_xz.distance_to(_seen[id])
		if d < best_d:
			best_d = d
			best = str(id)
	return best


func tick(player_xz: Vector2, yaw_degrees: float, delta: float) -> void:
	if _dead:
		bot.release()
		striking = false
		retreating = false
		return
	var step := minf(maxf(delta, 0.0), 0.05)
	var foe_id := nearest_id(player_xz)
	if foe_id == "":
		striking = false
		retreating = false
		bot.release()
		return
	var foe: Vector2 = _seen[foe_id]
	retreating = _ratio() <= RETREAT_HP_RATIO
	if retreating:
		striking = false
		_walk_retreat(player_xz, foe, yaw_degrees, step)
		return
	if player_xz.distance_to(foe) <= ENGAGE_COLUMNS:
		_strike(player_xz, foe, yaw_degrees, step)
		return
	striking = false
	_walk_toward(foe, player_xz, yaw_degrees, step)


func _ratio() -> float:
	if _hp_max <= 0.0:
		return 1.0
	return clampf(_hp / _hp_max, 0.0, 1.0)


func _walk_toward(goal: Vector2, player_xz: Vector2, yaw: float, step: float) -> void:
	if not bot.has_target or bot.gave_up or bot.target.distance_to(goal) > 0.5:
		bot.set_target(goal)
	bot.tick(player_xz, yaw, step)
	_tap_sword()


func _walk_retreat(player_xz: Vector2, foe: Vector2, yaw: float, step: float) -> void:
	var away := player_xz - foe
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	var goal := player_xz + away * RETREAT_PUSH
	if not bot.has_target or bot.arrived or bot.gave_up or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	bot.tick(player_xz, yaw, step)


func _strike(player_xz: Vector2, foe: Vector2, yaw: float, step: float) -> void:
	striking = true
	bot.input.begin_tick()
	var held: PackedStringArray = PackedStringArray()
	var rot := _Nav.face_action(player_xz, foe, yaw)
	if rot != "":
		held.append(rot)
	bot.input.set_held(held)
	_tap_sword()
	if _sword_delay > 0:
		_sword_delay -= 1
		return
	_attack_wait -= step
	_skill_wait -= step
	if rot != "":
		return
	if _attack_wait <= 0.0:
		bot.input.pulse(ATTACK_ACTION)
		swings += 1
		_attack_wait = ATTACK_GAP_SEC
	if chip_skills and _skill_wait <= 0.0:
		var skill := SKILL_ACTIONS[_skill_i % SKILL_ACTIONS.size()]
		bot.input.pulse(skill)
		skills_used += 1
		_skill_i += 1
		_skill_wait = SKILL_GAP_SEC


func walk_to(goal: Vector2, player_xz: Vector2, yaw: float, step: float) -> void:
	_walk_toward(goal, player_xz, yaw, step)


func strike_point(player_xz: Vector2, point: Vector2, yaw: float, step: float) -> void:
	_strike(player_xz, point, yaw, step)


func _tap_sword() -> void:
	if _sword_sent:
		return
	bot.input.pulse(SWORD_ACTION)
	_sword_sent = true
	_sword_delay = 1
