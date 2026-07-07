class_name StatComponent
extends Node

const _StatSheet = preload("res://stats/stat_sheet.gd")
const _StatModifier = preload("res://stats/stat_modifier.gd")
const _StatIds = preload("res://stats/stat_ids.gd")

signal stat_changed(stat_id: StringName, value: float)

var sheet: _StatSheet


func _ready() -> void:
	add_to_group("stat_component")
	sheet = _StatSheet.new()
	sheet.stat_changed.connect(_on_sheet_stat_changed)
	_apply_default_caps()


func _apply_default_caps() -> void:
	sheet.set_cap(_StatIds.MAX_HEALTH, 1.0, 9999.0)
	sheet.set_cap(_StatIds.MOVE_SPEED, 1.0, 80.0)
	sheet.set_cap(_StatIds.CRYSTAL_RESISTANCE, 0.0, 0.95)
	sheet.set_cap(_StatIds.DEFENSE, 0.0, 0.90)
	sheet.set_cap(_StatIds.DIG_SPEED, 0.1, 5.0)
	sheet.set_cap(_StatIds.BUILD_COST, 0.1, 3.0)
	sheet.set_cap(_StatIds.CRYSTAL_DAMAGE, 0.1, 10.0)
	sheet.set_cap(_StatIds.BUILD_FLOW_BLOCK, 0.0, 1.0)


func get_stat(stat_id: StringName) -> float:
	return sheet.get_value(stat_id) if sheet else 0.0


func set_base(stat_id: StringName, value: float) -> void:
	if sheet:
		sheet.set_base(stat_id, value)


func apply_modifier(mod: _StatModifier) -> void:
	if sheet and mod:
		sheet.add_modifier(mod)


func apply_modifiers(mods: Array) -> void:
	for mod in mods:
		if mod is _StatModifier:
			apply_modifier(mod)


func remove_source(source_id: StringName) -> void:
	if sheet:
		sheet.remove_modifiers_from_source(source_id)


func load_bases_from_exports(max_health: float, move_speed: float) -> void:
	set_base(_StatIds.MAX_HEALTH, max_health)
	set_base(_StatIds.MOVE_SPEED, move_speed)


func _on_sheet_stat_changed(stat_id: StringName, value: float) -> void:
	stat_changed.emit(stat_id, value)