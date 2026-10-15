class_name StatModifier
extends Resource

const _StatIds = preload("res://stats/stat_ids.gd")

enum Op { FLAT, ADDITIVE_PERCENT, MULTIPLICATIVE }

@export var stat_id: StringName = &"move_speed"

@export var op: Op = Op.FLAT

@export var value: float = 0.0

@export var source_id: StringName = &""

@export var priority: int = 0


static func flat(stat_id: StringName, amount: float, source: StringName = &""):
	var m := StatModifier.new() as StatModifier
	m.stat_id = stat_id
	m.op = Op.FLAT
	m.value = amount
	m.source_id = source
	return m


static func add_pct(stat_id: StringName, percent: float, source: StringName = &""):
	var m := StatModifier.new() as StatModifier
	m.stat_id = stat_id
	m.op = Op.ADDITIVE_PERCENT
	m.value = percent
	m.source_id = source
	return m


static func mult(stat_id: StringName, factor: float, source: StringName = &""):
	var m := StatModifier.new() as StatModifier
	m.stat_id = stat_id
	m.op = Op.MULTIPLICATIVE
	m.value = factor
	m.source_id = source
	return m