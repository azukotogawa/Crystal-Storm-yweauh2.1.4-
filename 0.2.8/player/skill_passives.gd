class_name SkillPassives
extends RefCounted

const _StatIds = preload("res://stats/stat_ids.gd")
const _StatModifier = preload("res://stats/stat_modifier.gd")

const SOURCE := &"skill_passive"
const MINING_SPEED := 0.25
const MAX_HP := 20.0
const STRUCTURE_HP := 4
const MINER := &"miner_passive"
const FIGHTER := &"fighter_passive"
const BUILDER := &"builder_passive"


static func apply(stats, skills) -> void:
	if stats == null or not stats.has_method("remove_source"):
		return
	stats.remove_source(SOURCE)
	if skills == null or not skills.has_method("is_unlocked") or not stats.has_method("apply_modifier"):
		return
	if skills.is_unlocked(MINER):
		stats.apply_modifier(_StatModifier.flat(_StatIds.DIG_SPEED, MINING_SPEED, SOURCE))
	if skills.is_unlocked(FIGHTER):
		stats.apply_modifier(_StatModifier.flat(_StatIds.MAX_HEALTH, MAX_HP, SOURCE))


static func push(skills) -> void:
	if skills == null or not skills.is_inside_tree():
		return
	var player: Node = skills.get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var stats = player.get("stat_component")
	if stats == null:
		stats = player.get_node_or_null("StatComponent")
	apply(stats, skills)


static func structure_cell_bonus() -> int:
	var skills = load("res://systems/skill_service.gd").get_active()
	if skills != null and skills.has_method("is_unlocked") and skills.is_unlocked(BUILDER):
		return STRUCTURE_HP
	return 0
