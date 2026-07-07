class_name RelicManager
extends Node

const _RelicDef = preload("res://config/relic_def.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _StatComponent = preload("res://stats/stat_component.gd")
const _StatModifier = preload("res://stats/stat_modifier.gd")

signal relic_equipped(relic_id: StringName)
signal relic_unequipped(relic_id: StringName)

@export var max_slots: int = 3

var equipped: Array[StringName] = []
var _stat_component: _StatComponent


func _ready() -> void:
	add_to_group("relic_manager")
	_RelicRegistry.ensure_builtins()
	_stat_component = get_parent().get_node_or_null("StatComponent") as _StatComponent
	if _stat_component == null:
		_stat_component = get_parent() as _StatComponent


func equip(relic_id: StringName) -> bool:
	var def: _RelicDef = _RelicRegistry.get_def(relic_id)
	if def == null:
		return false
	if relic_id in equipped:
		return true
	if equipped.size() >= max_slots:
		return false
	equipped.append(relic_id)
	_apply_relic(def)
	relic_equipped.emit(relic_id)
	return true


func unequip(relic_id: StringName) -> void:
	if relic_id not in equipped:
		return
	equipped.erase(relic_id)
	if _stat_component:
		_stat_component.remove_source(relic_id)
	relic_unequipped.emit(relic_id)


func _apply_relic(def: _RelicDef) -> void:
	if _stat_component == null:
		return
	for mod in def.stat_modifiers:
		if mod == null:
			continue
		var copy := mod.duplicate() as _StatModifier
		if copy.source_id == &"":
			copy.source_id = def.id
		_stat_component.apply_modifier(copy)


func get_equipped_defs() -> Array:
	var out: Array = []
	for rid in equipped:
		var def: _RelicDef = _RelicRegistry.get_def(rid)
		if def:
			out.append(def)
	return out


func get_crystal_flow_mult() -> float:
	var mult := 1.0
	for def in get_equipped_defs():
		mult *= def.crystal_flow_mult
	return mult