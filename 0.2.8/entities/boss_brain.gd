class_name BossBrain
extends RefCounted
## Telegraph timing for the origin warden and the shard tyrants.
## Damage is applied by CrystalEnemy only when tick() reports impact.

const SLAM_WINDUP := 0.8
const BURST_WINDUP := 0.8
const CHARGE_WINDUP := 0.65
const PHASE_HP := 0.5

const _RelicChoice = preload("res://relics/relic_choice.gd")

var phase: int = 1
var elite: bool = false
var windup: float = 0.0
var cooldown: float = 0.0
var action: StringName = &""
var _phase2_fresh: bool = false
var _burst_next: bool = true


func notify_hp_ratio(ratio: float) -> void:
	if elite:
		phase = 1
		return
	if phase == 1 and ratio <= PHASE_HP:
		phase = 2
		_phase2_fresh = true


## dist_voxels is the horizontal gap to the player, in voxels.
func tick(delta: float, dist_voxels: float) -> Dictionary:
	var summon := 0
	var phase_changed := false
	var marker_fresh := false
	if _phase2_fresh:
		_phase2_fresh = false
		phase_changed = true
		summon = 3
		action = &"burst"
		windup = BURST_WINDUP
		cooldown = 0.0
		marker_fresh = true
	if windup > 0.0:
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
		action = &"slam" if elite or dist_voxels <= 4.0 else &"charge"
		windup = SLAM_WINDUP if action == &"slam" else CHARGE_WINDUP
	else:
		# Phase 2 alternates a telegraphed burst with a faster slam or charge.
		if _burst_next:
			action = &"burst"
			windup = BURST_WINDUP
		else:
			action = &"slam" if dist_voxels <= 4.0 else &"charge"
			windup = 0.5 if action == &"slam" else 0.45
		_burst_next = not _burst_next
	marker_fresh = true
	return _pack(action, true, false, summon, phase_changed, marker_fresh)


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
