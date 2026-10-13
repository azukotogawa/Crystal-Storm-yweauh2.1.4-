class_name RelicRegistry
extends RefCounted

const _RelicDef = preload("res://config/relic_def.gd")
const _StatModifier = preload("res://stats/stat_modifier.gd")
const _StatIds = preload("res://stats/stat_ids.gd")

static var _defs: Dictionary = {}


static func reset() -> void:
	_defs.clear()


static func register(def: _RelicDef) -> void:
	if def:
		_defs[def.id] = def


static func register_all(defs: Array) -> void:
	for def in defs:
		if def is _RelicDef:
			register(def)


static func get_def(id: StringName) -> _RelicDef:
	return _defs.get(id)


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	register(_make_crystal_ward())
	register(_make_flow_anchor())
	register(_make_mason_glove())
	register(_make_pathfinder_charm())
	register(_make_ruin_seal())


## Relics that can drop from ruin expeditions (exploration reward pool).
static func ruin_loot_pool() -> Array[StringName]:
	ensure_builtins()
	return [&"pathfinder_charm", &"ruin_seal", &"flow_anchor", &"mason_glove"]


## Vertical-slice starter: slows crystal fluid flow (measurable via get_crystal_flow_mult).
static func _make_crystal_ward() -> _RelicDef:
	var d := _RelicDef.new()
	d.id = &"crystal_ward"
	d.display_name = "Crystal Ward"
	d.description = "Dampens crystal pressure — nearby growth and flow slow noticeably."
	d.rarity = _RelicDef.Rarity.UNCOMMON
	d.crystal_flow_mult = 0.72
	d.stat_modifiers = [
		_StatModifier.flat(_StatIds.CRYSTAL_RESISTANCE, 0.12, &"crystal_ward"),
	]
	return d


static func _make_flow_anchor() -> _RelicDef:
	var d := _RelicDef.new()
	d.id = &"flow_anchor"
	d.display_name = "Flow Anchor"
	d.description = "Walls you place resist crystal spread more effectively."
	d.rarity = _RelicDef.Rarity.UNCOMMON
	d.crystal_flow_mult = 0.88
	d.stat_modifiers = [
		_StatModifier.mult(_StatIds.BUILD_FLOW_BLOCK, 1.25, &"flow_anchor"),
	]
	return d


static func _make_mason_glove() -> _RelicDef:
	var d := _RelicDef.new()
	d.id = &"mason_glove"
	d.display_name = "Mason's Glove"
	d.description = "Dig faster and build at reduced material cost."
	d.rarity = _RelicDef.Rarity.COMMON
	d.stat_modifiers = [
		_StatModifier.mult(_StatIds.DIG_SPEED, 1.35, &"mason_glove"),
		_StatModifier.mult(_StatIds.BUILD_COST, 0.8, &"mason_glove"),
	]
	d.build_cost_mult = 0.8
	return d

## Ruin find: move faster while scouting the wilds.
static func _make_pathfinder_charm() -> _RelicDef:
	var d := _RelicDef.new()
	d.id = &"pathfinder_charm"
	d.display_name = "Pathfinder's Charm"
	d.description = "Pulled from a forgotten ruin — you cover ground faster."
	d.rarity = _RelicDef.Rarity.COMMON
	d.stat_modifiers = [
		_StatModifier.mult(_StatIds.MOVE_SPEED, 1.18, &"pathfinder_charm"),
	]
	return d


## Ruin find: resist crystal burn while exploring pressure fronts.
static func _make_ruin_seal() -> _RelicDef:
	var d := _RelicDef.new()
	d.id = &"ruin_seal"
	d.display_name = "Ruin Seal"
	d.description = "A cracked ward-stone. Crystal contact burns less."
	d.rarity = _RelicDef.Rarity.UNCOMMON
	d.crystal_flow_mult = 0.92
	d.stat_modifiers = [
		_StatModifier.flat(_StatIds.CRYSTAL_RESISTANCE, 0.18, &"ruin_seal"),
	]
	return d
