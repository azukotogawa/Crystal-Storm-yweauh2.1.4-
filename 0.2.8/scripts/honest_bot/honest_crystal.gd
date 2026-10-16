extends RefCounted

const _Fight = preload("res://scripts/honest_bot/honest_combat.gd")

const ENGAGE_COLUMNS := 2.4
const BOSS_PREFIX := "boss-"
const BOSS_LINE := 0.25

var fight := _Fight.new()
var lines: PackedStringArray = PackedStringArray()
var crystal_xz := Vector2.ZERO
var crystal_hp := 0.0
var crystal_max := 0.0
var has_crystal := false
var destroyed := false
var fighting_boss := false
var striking_crystal := false
var boss_kills := 0
var _saw_boss := false
var _announced_destroy := false
var _announced_line := false
var _fight_seen := 0


func release() -> void:
	fight.release()


func summary_line() -> String:
	return "CRYSTAL %.0f/%.0f BOSS %d" % [crystal_hp, crystal_max, boss_kills]


func stuck_lines() -> PackedStringArray:
	return fight.bot.stuck_lines


func set_vitals(hp: float, hp_max: float) -> void:
	fight.set_vitals(hp, hp_max)
	_drain_fight_lines()


func observe_crystal(xz: Vector2, hp: float, hp_max: float) -> void:
	crystal_xz = xz
	crystal_hp = hp
	crystal_max = maxf(hp_max, 0.0)
	has_crystal = true
	if crystal_max > 0.0 and crystal_hp <= crystal_max * BOSS_LINE and not _announced_line:
		_announced_line = true
		_keep("BOSS LINE hp %.1f/%.1f" % [crystal_hp, crystal_max])
	if crystal_hp <= 0.0:
		_mark_destroyed()


func observe_foes(seen: Array) -> void:
	var bosses: Array = []
	for item in seen:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var id := str(item.get("id", ""))
		if not id.begins_with(BOSS_PREFIX):
			continue
		bosses.append(item)
	var before: int = int(fight.kills)
	fight.observe(bosses)
	if int(fight.kills) > before:
		var gained: int = int(fight.kills) - before
		boss_kills += gained
		_keep("BOSS KILL")
	if not bosses.is_empty() and not _saw_boss:
		_saw_boss = true
		_keep("BOSS SPAWN %s" % str(bosses[0].get("id", "")))
	_drain_fight_lines()


func tick(player_xz: Vector2, yaw_degrees: float, delta: float) -> void:
	if fight.deaths > 0:
		striking_crystal = false
		fighting_boss = false
		fight.release()
		return
	var step := minf(maxf(delta, 0.0), 0.05)
	if fight.nearest_id(player_xz) != "":
		fighting_boss = true
		striking_crystal = false
		fight.tick(player_xz, yaw_degrees, step)
		_drain_fight_lines()
		return
	fighting_boss = false
	if not has_crystal or destroyed or crystal_hp <= 0.0:
		_mark_destroyed()
		fight.release()
		striking_crystal = false
		return
	if player_xz.distance_to(crystal_xz) <= ENGAGE_COLUMNS:
		striking_crystal = true
		fight.strike_point(player_xz, crystal_xz, yaw_degrees, step)
		return
	striking_crystal = false
	fight.walk_to(crystal_xz, player_xz, yaw_degrees, step)


func _mark_destroyed() -> void:
	if _announced_destroy:
		return
	if not has_crystal:
		return
	if crystal_hp > 0.0:
		return
	destroyed = true
	_announced_destroy = true
	_keep("CRYSTAL DESTROYED")


func _drain_fight_lines() -> void:
	while _fight_seen < fight.lines.size():
		_keep(fight.lines[_fight_seen])
		_fight_seen += 1


func _keep(line: String) -> void:
	if line == "":
		return
	for existing in lines:
		if existing == line:
			return
	lines.append(line)
