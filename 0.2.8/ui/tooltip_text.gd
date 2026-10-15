class_name TooltipText
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _StatModifier = preload("res://stats/stat_modifier.gd")


static func format_num(v: float) -> String:
	var rounded := snappedf(v, 0.01)
	if absf(rounded - roundf(rounded)) < 0.001:
		return str(int(round(rounded)))
	var text := "%.2f" % rounded
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


static func for_item(item_id: String) -> String:
	_ItemTypes.ensure_builtins()
	var def = _ItemTypes.get_item_def(item_id)
	if def == null:
		return "Name: %s\nDamage: 0\nRange: 0\nCooldown: 0\nCrystal damage: 0\nArmor reduction: 0\nDescription:\nEffects: none" % item_id
	var effects := _item_effects(def)
	return "Name: %s\nDamage: %s\nRange: %s\nCooldown: %s\nCrystal damage: %s\nArmor reduction: %s\nDescription: %s\nEffects: %s" % [
		str(def.display_name),
		format_num(float(def.damage)),
		format_num(float(def.attack_range)),
		format_num(float(def.cooldown)),
		format_num(float(def.crystal_damage)),
		format_num(float(def.damage_reduction)),
		str(def.description),
		effects,
	]


static func for_relic(relic_id: String) -> String:
	_RelicRegistry.ensure_builtins()
	var def = _RelicRegistry.get_def(StringName(relic_id))
	if def == null:
		return "Name: %s\nDamage: 0\nRange: 0\nCooldown: 0\nCrystal damage: 0\nArmor reduction: 0\nDescription:\nEffects: none" % relic_id
	var effects := _relic_effects(def)
	var aura := float(def.crystal_damage_aura)
	return "Name: %s\nDamage: 0\nRange: 0\nCooldown: 0\nCrystal damage: %s\nArmor reduction: 0\nDescription: %s\nEffects: %s" % [
		str(def.display_name),
		format_num(aura),
		str(def.description),
		effects,
	]


static func _item_effects(def) -> String:
	var parts: PackedStringArray = []
	if int(def.pierce) > 1:
		parts.append("pierce %d" % int(def.pierce))
	if float(def.knockback) > 0.0 and int(def.category) != _ItemTypes.Category.ARMOR:
		parts.append("knockback %s" % format_num(float(def.knockback)))
	if int(def.splash) > 0:
		parts.append("splash %d" % int(def.splash))
	if bool(def.thrust):
		parts.append("thrust")
	if float(def.blast_radius) > 0.0:
		parts.append("blast %s" % format_num(float(def.blast_radius)))
	if float(def.heal_amount) > 0.0:
		parts.append("heal %s" % format_num(float(def.heal_amount)))
	if int(def.category) == _ItemTypes.Category.ARMOR:
		parts.append("move speed ×%s" % format_num(float(def.move_speed_mult)))
	if str(def.ammo_id) != "":
		parts.append("ammo %s" % str(def.ammo_id))
	if parts.is_empty():
		return "none"
	return ", ".join(parts)


static func _relic_effects(def) -> String:
	var parts: PackedStringArray = []
	if absf(float(def.crystal_flow_mult) - 1.0) > 0.001:
		parts.append("crystal flow ×%s" % format_num(float(def.crystal_flow_mult)))
	if absf(float(def.crystal_damage_aura)) > 0.001:
		parts.append("crystal damage aura %s" % format_num(float(def.crystal_damage_aura)))
	if bool(def.grants_dig_through_crystal):
		parts.append("dig through crystal")
	if absf(float(def.build_cost_mult) - 1.0) > 0.001:
		parts.append("build cost ×%s" % format_num(float(def.build_cost_mult)))
	if bool(def.friendly_to_towns):
		parts.append("friendly to towns")
	if str(def.spawns_entity_id) != "":
		parts.append("spawns %s" % str(def.spawns_entity_id))
	for unlock_id in def.unlock_buildable_ids:
		parts.append("unlocks %s" % str(unlock_id))
	for mod in def.stat_modifiers:
		if mod == null:
			continue
		var op := "flat"
		if int(mod.op) == _StatModifier.Op.ADDITIVE_PERCENT:
			op = "add%"
		elif int(mod.op) == _StatModifier.Op.MULTIPLICATIVE:
			op = "×"
		parts.append("%s %s %s" % [str(mod.stat_id), op, format_num(float(mod.value))])
	if parts.is_empty():
		return "none"
	return ", ".join(parts)
