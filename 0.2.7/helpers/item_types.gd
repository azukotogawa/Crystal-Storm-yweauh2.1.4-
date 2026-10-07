class_name ItemTypes
extends RefCounted
## Compatibility façade over ItemDef. Dict lookups stay stable for weapons/HUD.

const _ItemDef = preload("res://config/item_def.gd")

enum Category { WEAPON, TOOL, MATERIAL, CONSUMABLE, MISC }
enum WeaponKind { MELEE, RANGED, DIG }

const MAX_STACK := 99

static var _defs: Dictionary = {}

const ITEMS: Dictionary = {
	"wooden_sword": {
		"name": "Wooden Sword",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.MELEE,
		"damage": 12.0,
		"entity_damage": 12.0,
		"crystal_damage": 0.35,
		"range": 2.8,
		"cooldown": 0.45,
		"stackable": false,
		"max_stack": 1,
	},
	"stone_pick": {
		"name": "Stone Pick",
		"category": Category.TOOL,
		"weapon_kind": WeaponKind.DIG,
		"damage": 6.0,
		"entity_damage": 5.0,
		"crystal_damage": 2.4,
		"range": 3.0,
		"cooldown": 0.1,
		"stackable": false,
		"max_stack": 1,
	},
	"shortbow": {
		"name": "Shortbow",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.RANGED,
		"damage": 10.0,
		"crystal_damage": 0.55,
		"range": 14.0,
		"cooldown": 0.8,
		"stackable": false,
		"max_stack": 1,
	},
	"wood": {
		"name": "Wood",
		"category": Category.MATERIAL,
		"stackable": true,
		"max_stack": MAX_STACK,
	},
	"stone": {
		"name": "Stone",
		"category": Category.MATERIAL,
		"stackable": true,
		"max_stack": MAX_STACK,
	},
	"herb": {
		"name": "Herb",
		"category": Category.CONSUMABLE,
		"stackable": true,
		"max_stack": MAX_STACK,
		"heal_amount": 28.0,
	},
	"crystal_shard": {
		"name": "Crystal Shard",
		"category": Category.MATERIAL,
		"stackable": true,
		"max_stack": MAX_STACK,
	},
}


static func reset() -> void:
	_defs.clear()


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	for item_id in ITEMS:
		register(_ItemDef.from_legacy(str(item_id), ITEMS[item_id]))


static func register(def) -> void:
	if def == null:
		return
	_defs[str(def.id)] = def


static func register_all(defs: Array) -> void:
	for entry in defs:
		if entry is _ItemDef:
			register(entry)


static func get_item_def(item_id: String):
	ensure_builtins()
	return _defs.get(item_id)


static func get_def(item_id: String) -> Dictionary:
	ensure_builtins()
	var def = _defs.get(item_id)
	if def:
		return def.to_lookup()
	return ITEMS.get(item_id, {})


static func is_valid(item_id: String) -> bool:
	ensure_builtins()
	return _defs.has(item_id) or ITEMS.has(item_id)


static func is_weapon(item_id: String) -> bool:
	var def := get_def(item_id)
	return not def.is_empty() and int(def.get("category", -1)) == Category.WEAPON


static func is_tool(item_id: String) -> bool:
	var def := get_def(item_id)
	return not def.is_empty() and int(def.get("category", -1)) == Category.TOOL


static func weapon_kind(item_id: String) -> int:
	return int(get_def(item_id).get("weapon_kind", WeaponKind.MELEE))


static func display_name(item_id: String) -> String:
	return str(get_def(item_id).get("name", item_id))


static func max_stack_for(item_id: String) -> int:
	return int(get_def(item_id).get("max_stack", 1))


static func is_stackable(item_id: String) -> bool:
	return bool(get_def(item_id).get("stackable", false))