class_name ItemTypes
extends RefCounted
## Compatibility façade over ItemDef. Dict lookups stay stable for weapons/HUD.

const _ItemDef = preload("res://config/item_def.gd")

enum Category { WEAPON, TOOL, MATERIAL, CONSUMABLE, MISC, ARMOR }
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
		"knockback": 1.0,
		"anim_kind": 1,
		"anim_duration": 0.45,
		"impact_ratio": 0.42,
		"description": "A quick arc. Reliable, short, and light.",
		"stackable": false,
		"max_stack": 1,
	},
	"spear": {
		"name": "Spear",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.MELEE,
		"damage": 15.0,
		"entity_damage": 15.0,
		"crystal_damage": 0.5,
		"range": 3.0,
		"cooldown": 0.78,
		"pierce": 2,
		"thrust": true,
		"knockback": 1.6,
		"anim_kind": 2,
		"anim_duration": 0.78,
		"impact_ratio": 0.56,
		"visual_id": "wooden_sword",
		"description": "Long thrust, about 3 voxels. Pierces two targets. Slower than the sword.",
		"stackable": false,
		"max_stack": 1,
	},
	"crystal_hammer": {
		"name": "Crystal Hammer",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.MELEE,
		"damage": 8.0,
		"entity_damage": 7.0,
		"crystal_damage": 4.8,
		"range": 2.2,
		"cooldown": 1.1,
		"splash": 1,
		"knockback": 3.2,
		"anim_kind": 1,
		"anim_duration": 1.1,
		"impact_ratio": 0.62,
		"visual_id": "stone_pick",
		"description": "Slow crystal breaker. 3×3 cell splash and a heavy shove. Does not dig.",
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
		"anim_kind": 1,
		"anim_duration": 0.08,
		"impact_ratio": 0.40,
		"stackable": false,
		"max_stack": 1,
	},
	"shortbow": {
		"name": "Shortbow",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.RANGED,
		"damage": 10.0,
		"entity_damage": 10.0,
		"crystal_damage": 0.55,
		"range": 14.0,
		"cooldown": 0.8,
		"knockback": 0.9,
		"projectile_speed": 32.0,
		"projectile_gravity": 12.0,
		"anim_kind": 4,
		"anim_duration": 0.8,
		"impact_ratio": 0.70,
		"description": "Fires an arrow along your aim. It drops and can miss. Does not dig.",
		"stackable": false,
		"max_stack": 1,
	},
	"sling": {
		"name": "Sling",
		"category": Category.WEAPON,
		"weapon_kind": WeaponKind.RANGED,
		"damage": 8.0,
		"entity_damage": 8.0,
		"crystal_damage": 0.45,
		"range": 11.0,
		"cooldown": 0.5,
		"knockback": 0.7,
		"projectile_speed": 18.0,
		"projectile_gravity": 34.0,
		"ammo_id": "stone",
		"visual_id": "shortbow",
		"anim_kind": 4,
		"anim_duration": 0.5,
		"impact_ratio": 0.62,
		"description": "Lobs one stone in a high arc. Cheap, slow, and easy to miss.",
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
		"anim_kind": 3,
		"anim_duration": 0.32,
		"impact_ratio": 0.50,
	},
	"crystal_shard": {
		"name": "Crystal Shard",
		"category": Category.MATERIAL,
		"stackable": true,
		"max_stack": MAX_STACK,
	},
	"crystal_bomb": {
		"name": "Crystal Bomb",
		"category": Category.CONSUMABLE,
		"damage": 22.0,
		"crystal_damage": 3.2,
		"blast_radius": 2.5,
		"throwable": true,
		"knockback": 2.0,
		"projectile_speed": 12.0,
		"projectile_gravity": 22.0,
		"visual_id": "crystal_shard",
		"anim_kind": 3,
		"anim_duration": 0.36,
		"impact_ratio": 0.48,
		"description": "Throws a short arc, then clears crystal in a 2.5-column radius. Terrain height stays.",
		"stackable": true,
		"max_stack": 8,
	},
	"leather_armor": {
		"name": "Leather Armor",
		"category": Category.ARMOR,
		"damage_reduction": 0.12,
		"move_speed_mult": 1.0,
		"visual_id": "herb",
		"description": "Light hide. Cuts incoming damage a little. No speed loss.",
		"stackable": false,
		"max_stack": 1,
	},
	"stone_plate": {
		"name": "Stone Plate",
		"category": Category.ARMOR,
		"damage_reduction": 0.28,
		"move_speed_mult": 0.86,
		"visual_id": "stone",
		"description": "Heavy plates. Strong reduction and slower steps.",
		"stackable": false,
		"max_stack": 1,
	},
	"crystal_weave": {
		"name": "Crystal Weave",
		"category": Category.ARMOR,
		"damage_reduction": 0.20,
		"move_speed_mult": 1.08,
		"visual_id": "crystal_shard",
		"description": "Woven shards. Solid protection and a quicker step. Taken from elites.",
		"stackable": false,
		"max_stack": 1,
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


static func is_armor(item_id: String) -> bool:
	var def := get_def(item_id)
	return not def.is_empty() and int(def.get("category", -1)) == Category.ARMOR


## Icon key. New gear reuses an existing item texture through visual_id.
static func visual_key(item_id: String) -> String:
	var vis := str(get_def(item_id).get("visual_id", ""))
	if vis == "":
		return item_id
	return vis


static func armor_reduction(item_id: String) -> float:
	if item_id == "":
		return 0.0
	return clampf(float(get_def(item_id).get("damage_reduction", 0.0)), 0.0, 0.75)


static func armor_speed_mult(item_id: String) -> float:
	if item_id == "":
		return 1.0
	return clampf(float(get_def(item_id).get("move_speed_mult", 1.0)), 0.5, 1.25)