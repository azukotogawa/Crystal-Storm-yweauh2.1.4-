class_name StatSheet
extends RefCounted

const _StatIds = preload("res://stats/stat_ids.gd")
const _StatModifier = preload("res://stats/stat_modifier.gd")

signal stat_changed(stat_id: StringName, value: float)

var _bases: Dictionary = {}
var _modifiers: Array = []
var _caps: Dictionary = {}  # StringName -> {min, max} optional


func _init(default_bases: Dictionary = {}) -> void:
	for key in _StatIds.DEFAULT_BASES:
		_bases[key] = float(_StatIds.DEFAULT_BASES[key])
	for key in default_bases:
		_bases[key] = float(default_bases[key])


func set_base(stat_id: StringName, value: float) -> void:
	_bases[stat_id] = value
	stat_changed.emit(stat_id, get_value(stat_id))


func get_base(stat_id: StringName) -> float:
	return float(_bases.get(stat_id, 0.0))


func set_cap(stat_id: StringName, min_value: float, max_value: float) -> void:
	_caps[stat_id] = {"min": min_value, "max": max_value}


func add_modifier(mod: _StatModifier) -> void:
	if mod == null:
		return
	_modifiers.append(mod)
	_modifiers.sort_custom(func(a: _StatModifier, b: _StatModifier) -> bool:
		return a.priority < b.priority
	)
	stat_changed.emit(mod.stat_id, get_value(mod.stat_id))


func remove_modifiers_from_source(source_id: StringName) -> void:
	if source_id == &"":
		return
	var changed: Dictionary = {}
	var kept: Array = []
	for mod in _modifiers:
		if mod.source_id == source_id:
			changed[mod.stat_id] = true
		else:
			kept.append(mod)
	_modifiers = kept
	for stat_id in changed:
		stat_changed.emit(stat_id, get_value(stat_id))


func clear_modifiers() -> void:
	_modifiers.clear()
	for stat_id in _bases:
		stat_changed.emit(stat_id, get_value(stat_id))


func get_value(stat_id: StringName) -> float:
	var base := get_base(stat_id)
	var flat_sum := 0.0
	var add_pct_sum := 0.0
	var mult_product := 1.0

	for mod in _modifiers:
		if mod.stat_id != stat_id:
			continue
		match mod.op:
			_StatModifier.Op.FLAT:
				flat_sum += mod.value
			_StatModifier.Op.ADDITIVE_PERCENT:
				add_pct_sum += mod.value
			_StatModifier.Op.MULTIPLICATIVE:
				mult_product *= mod.value

	var result := (base + flat_sum) * (1.0 + add_pct_sum) * mult_product

	if _caps.has(stat_id):
		var cap: Dictionary = _caps[stat_id]
		result = clampf(result, float(cap.min), float(cap.max))

	return result


func snapshot() -> Dictionary:
	var out := {}
	for stat_id in _StatIds.ALL:
		out[stat_id] = get_value(stat_id)
	return out


func export_bases() -> Dictionary:
	var out := {}
	for key in _bases.keys():
		out[str(key)] = float(_bases[key])
	return out


func load_bases(data: Dictionary) -> void:
	for key in data.keys():
		set_base(StringName(str(key)), float(data[key]))