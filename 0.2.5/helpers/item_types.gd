class_name ItemTypes
extends RefCounted

enum Category { WEAPON, TOOL, MATERIAL, CONSUMABLE, MISC }
enum WeaponKind { MELEE, RANGED, DIG }

const MAX_STACK := 99

const ITEMS: Dictionary = {
	"wooden_sword": {
		"name": "Wooden Sword",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.MELEE,
		"damage": 12.0,
		"range": 2.2,
		"cooldown": 0.45,
		"stackable": false,
		"max_stack": 1,
	},
	"stone_pick": {
		"name": "Stone Pick",
		"category": Category.TOOL,
		"weapon_kind": WeaponKind.DIG,
		"damage": 6.0,
		"range": 2.0,
		"cooldown": 0.55,
		"stackable": false,
		"max_stack": 1,
	},
	"shortbow": {
		"name": "Shortbow",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.RANGED,
		"damage": 10.0,
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
	},
}


static func get_def(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


static func is_valid(item_id: String) -> bool:
	return ITEMS.has(item_id)


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