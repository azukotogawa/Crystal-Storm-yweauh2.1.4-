class_name BossBrain
extends RefCounted

const FALLBACK_TELEGRAPH := 0.85
const PHASE_HP := 0.5
const BOSS_SPAWN_HEALTH_RATIO = 0.25

const _RelicChoice = preload("res://relics/relic_choice.gd")

var phase: int = 1
var elite: bool = false
var windup: float = 0.0
var telegraph_sec: float = FALLBACK_TELEGRAPH
var cooldown: float = 0.0
var action: StringName = &""
var _phase2_fresh: bool = false
var _burst_next: bool = true


static func spawns_at_health_ratio(ratio: float) -> bool:
	return ratio <= BOSS_SPAWN_HEALTH_RATIO


func notify_hp_ratio(ratio: float) -> void:
	if elite:
		phase = 1
		return
	if phase == 1 and ratio <= PHASE_HP:
		phase = 2
		_phase2_fresh = true


func tick(delta: float, dist_voxels: float) -> Dictionary:
	var summon := 0
	var phase_changed := false
	var marker_fresh := false
	var just_armed := false
	if _phase2_fresh:
		_phase2_fresh = false
		phase_changed = true
		summon = 3
		_arm(&"burst")
		cooldown = 0.0
		marker_fresh = true
		just_armed = true
	if windup > 0.0 and not just_armed:
		var current := action
		windup -= delta
		if windup > 0.0:
			return _pack(current, true, false, summon, phase_changed, marker_fresh)
		action = &""
		windup = 0.0
		cooldown = 0.32 if phase == 2 and not elite else 0.85
		return _pack(current, false, true, summon, phase_changed, false)
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
		return _pack(&"", false, false, summon, phase_changed, false)
	if elite or phase == 1:
		_arm(&"slam" if elite or dist_voxels <= 4.0 else &"charge")
	else:
		if _burst_next:
			_arm(&"burst")
		else:
			_arm(&"slam" if dist_voxels <= 4.0 else &"charge")
		_burst_next = not _burst_next
	marker_fresh = true
	return _pack(action, true, false, summon, phase_changed, marker_fresh)


func _arm(act: StringName) -> void:
	_read_telegraph()
	action = act
	windup = telegraph_sec


func _read_telegraph() -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var feel := (loop as SceneTree).root.get_node_or_null("GameFeel")
	if feel == null or not feel.has_method("enemy_telegraph"):
		return
	var seconds := float(feel.enemy_telegraph("boss"))
	if seconds > 0.0:
		telegraph_sec = seconds


func _pack(
	act: StringName,
	telegraph: bool,
	impact: bool,
	summon: int,
	phase_changed: bool,
	marker_fresh: bool
) -> Dictionary:
	return {
		"phase": phase,
		"action": act,
		"telegraph": telegraph,
		"impact": impact,
		"summon": summon,
		"phase_changed": phase_changed,
		"marker_fresh": marker_fresh,
	}


static func on_warden_killed(tree: SceneTree) -> void:
	if tree == null:
		return
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("set_origin_warden_alive"):
		crystal.set_origin_warden_alive(false)
	var gm = tree.get_first_node_in_group("game_manager")
	if gm and gm.has_method("notify_boss_defeated"):
		gm.notify_boss_defeated()
	_offer(tree, 1, "Origin Warden fell — choose a relic")


static func on_elite_killed(tree: SceneTree, seed: int) -> void:
	_offer(tree, seed + 3, "Shard Tyrant fell — choose a relic")


static func _offer(tree: SceneTree, seed: int, title: String) -> void:
	if tree == null:
		return
	var relics = null
	var player = tree.get_first_node_in_group("player")
	if player:
		relics = player.get_node_or_null("RelicManager")
	_RelicChoice.present(tree, relics, seed, title)
