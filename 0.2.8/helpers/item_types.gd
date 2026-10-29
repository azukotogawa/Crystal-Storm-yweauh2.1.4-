class_name ItemTypes
extends RefCounted

const _ItemDef = preload("res://config/item_def.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")

enum Category { WEAPON, TOOL, MATERIAL, CONSUMABLE, MISC, ARMOR }
enum WeaponKind { MELEE, RANGED, DIG }
enum BreakShape { SINGLE, VERTICAL_1X2, LINE_3, FACE_3X3, PAD_3X3, SHAFT_1X3, CUBE_3X3X2 }

const MAX_STACK := 99
const MULTI_BLOCK_BREAK := true
const DIG_TIME_PER_EXTRA_CELL := 0.35
const BREAK_SHAPE_ORDER: Array[int] = [
	BreakShape.SINGLE,
	BreakShape.VERTICAL_1X2,
	BreakShape.LINE_3,
	BreakShape.FACE_3X3,
]

const BRUSH_ORDER: Array[int] = [
	BreakShape.SINGLE,
	BreakShape.LINE_3,
	BreakShape.PAD_3X3,
	BreakShape.SHAFT_1X3,
	BreakShape.CUBE_3X3X2,
]

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
		"cooldown": 0.32,
		"knockback": 1.0,
		"anim_kind": 1,
		"anim_duration": 0.32,
		"impact_ratio": 0.5,
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
		"cooldown": 0.55,
		"pierce": 2,
		"thrust": true,
		"knockback": 1.6,
		"anim_kind": 2,
		"anim_duration": 0.55,
		"impact_ratio": 0.56,
		"visual_id": "spear",
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
		"visual_id": "crystal_hammer",
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
		"dig_radius": 1,
		"break_shape": BreakShape.SINGLE,
		"tool_tier": 0,
		"anim_kind": 1,
		"anim_duration": 0.16,
		"impact_ratio": 0.45,
		"durability": 0,
		"description": "Dig radius 1. [ and ] widen the brush while this pick is held.",
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
		"cooldown": 0.56,
		"knockback": 0.9,
		"projectile_speed": 32.0,
		"projectile_gravity": 12.0,
		"anim_kind": 4,
		"anim_duration": 0.56,
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
		"cooldown": 0.35,
		"knockback": 0.7,
		"projectile_speed": 18.0,
		"projectile_gravity": 34.0,
		"ammo_id": "stone",
		"visual_id": "sling",
		"anim_kind": 4,
		"anim_duration": 0.35,
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
	"rare_ore": {
		"name": "Rare Ore",
		"category": Category.MATERIAL,
		"stackable": true,
		"max_stack": MAX_STACK,
		"visual_id": "crystal_shard",
		"description": "A rare ore exposed on the surface.",
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
	"wall_segment": {
		"name": "Wall Segment",
		"category": Category.MISC,
		"stackable": true,
		"max_stack": 16,
		"visual_id": "stone",
		"anim_kind": 0,
		"anim_duration": 0.17,
		"impact_ratio": 0.0,
		"description": "Crafted wall, three wide and two high. Place it from the build menu.",
	},
	"wall_corner": {
		"name": "Wall Corner",
		"category": Category.MISC,
		"stackable": true,
		"max_stack": 16,
		"visual_id": "stone",
		"anim_kind": 0,
		"anim_duration": 0.17,
		"impact_ratio": 0.0,
		"description": "Crafted wall corner, two wide and two high. Place it from the build menu.",
	},
	"gate": {
		"name": "Gate",
		"category": Category.MISC,
		"stackable": true,
		"max_stack": 16,
		"visual_id": "gate",
		"anim_kind": 0,
		"anim_duration": 0.17,
		"impact_ratio": 0.0,
		"description": "Crafted gate. Two stone posts and an open passage. Place it from the build menu.",
	},
	"stairs": {
		"name": "Stairs",
		"category": Category.MISC,
		"stackable": true,
		"max_stack": 16,
		"visual_id": "stone",
		"anim_kind": 0,
		"anim_duration": 0.17,
		"impact_ratio": 0.0,
		"description": "Crafted stairs, three steps rising one layer at a time. Place them from the build menu.",
	},
	"small_tower": {
		"name": "Small Tower",
		"category": Category.MISC,
		"stackable": true,
		"max_stack": 16,
		"visual_id": "stone",
		"anim_kind": 0,
		"anim_duration": 0.17,
		"impact_ratio": 0.0,
		"description": "Crafted tower, two by two and three high. Place it from the build menu.",
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
		return _tuned(def.to_lookup())
	return _tuned(ITEMS.get(item_id, {}))


static func _tuned(def: Dictionary) -> Dictionary:
	var feel = _GameFeelConfig.active()
	var kind := int(def.get("weapon_kind", -1))
	var is_weapon := int(def.get("category", -1)) == Category.WEAPON and (kind == WeaponKind.MELEE or kind == WeaponKind.RANGED)
	var is_throw := bool(def.get("throwable", false))
	if not is_weapon and not is_throw:
		return def
	var r := float(def.get("range", 6.0 if is_throw else 0.0))
	if is_weapon and kind == WeaponKind.MELEE:
		r = maxf(r, feel.melee_min_range)
	var out := def.duplicate()
	out["range"] = r + feel.range_bonus_voxels
	return out


static func is_valid(item_id: String) -> bool:
	ensure_builtins()
	return _defs.has(item_id) or ITEMS.has(item_id)


static func is_weapon(item_id: String) -> bool:
	var def := get_def(item_id)
	return not def.is_empty() and int(def.get("category", -1)) == Category.WEAPON


static func is_tool(item_id: String) -> bool:
	var def := get_def(item_id)
	return not def.is_empty() and int(def.get("category", -1)) == Category.TOOL


const PLACEABLE_BLOCK_IDS: PackedStringArray = ["stone", "wood"]


static func is_placeable_block(item_id: String) -> bool:
	if item_id in PLACEABLE_BLOCK_IDS:
		return true
	return bool(get_def(item_id).get("placeable_block", false))


## Pickaxe and other dig tools. Combat weapons, including the crystal hammer, do not.
static func breaks_blocks(item_id: String) -> bool:
	var def := get_def(item_id)
	if def.is_empty():
		return false
	if bool(def.get("breaks_blocks", false)):
		return true
	if int(def.get("weapon_kind", -1)) != WeaponKind.DIG:
		return false
	if int(def.get("category", -1)) == Category.TOOL:
		return true
	return int(def.get("dig_radius", 0)) > 0


static func tool_max_durability(item_id: String) -> int:
	var raw: Dictionary = ITEMS.get(item_id, {})
	return maxi(int(raw.get("durability", 0)), 0)


static func wear_for_cells(cell_count: int) -> int:
	return maxi(cell_count, 0)


static func dig_time_scale(cell_count: int) -> float:
	return 1.0 + DIG_TIME_PER_EXTRA_CELL * float(maxi(cell_count, 1) - 1)


static func break_shape_for(item_id: String, tier: int = -1) -> int:
	if not MULTI_BLOCK_BREAK or not breaks_blocks(item_id):
		return BreakShape.SINGLE
	var def := get_def(item_id)
	var base := int(def.get("break_shape", BreakShape.SINGLE))
	var steps := tier if tier >= 0 else int(def.get("tool_tier", 0))
	return widen_shape(base, steps)


static func widen_shape(shape: int, steps: int) -> int:
	var index := BREAK_SHAPE_ORDER.find(shape)
	if index < 0:
		index = 0
	var next := clampi(index + maxi(steps, 0), 0, BREAK_SHAPE_ORDER.size() - 1)
	return int(BREAK_SHAPE_ORDER[next])


static func break_shape_name(shape: int) -> String:
	match shape:
		BreakShape.VERTICAL_1X2:
			return "1x2_vertical"
		BreakShape.LINE_3:
			return "line_3"
		BreakShape.FACE_3X3:
			return "face_3x3"
		_:
			return "single"


static func brush_id(shape: int) -> String:
	match shape:
		BreakShape.LINE_3:
			return "line_3"
		BreakShape.PAD_3X3:
			return "pad_3x3"
		BreakShape.SHAFT_1X3:
			return "shaft_1x3"
		BreakShape.CUBE_3X3X2:
			return "cube_3x3x2"
		_:
			return "single"


static func brush_label(shape: int) -> String:
	match shape:
		BreakShape.LINE_3:
			return "Line 3"
		BreakShape.PAD_3X3:
			return "Pad 3x3"
		BreakShape.SHAFT_1X3:
			return "Shaft 3 deep"
		BreakShape.CUBE_3X3X2:
			return "Cube 3x3x2"
		_:
			return "Single"


static func brush_offsets(shape: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	match shape:
		BreakShape.LINE_3:
			for r in range(-1, 2):
				out.append(Vector3i(r, 0, 0))
		BreakShape.PAD_3X3:
			for f in range(-1, 2):
				for r in range(-1, 2):
					out.append(Vector3i(r, 0, f))
		BreakShape.SHAFT_1X3:
			for l in 3:
				out.append(Vector3i(0, l, 0))
		BreakShape.CUBE_3X3X2:
			for l in 2:
				for f in range(-1, 2):
					for r in range(-1, 2):
						out.append(Vector3i(r, l, f))
		_:
			out.append(Vector3i.ZERO)
	return out


static func brush_wear(cell_count: int) -> int:
	return maxi(1, ceili(float(cell_count) / 3.0))


static func rotate_aim(aim: Vector3, quarter: int) -> Vector3:
	return aim.rotated(Vector3.UP, -float(posmod(quarter, 4)) * PI * 0.5)


static func aim_cardinal(aim: Vector3) -> Vector3i:
	if absf(aim.x) < 0.0001 and absf(aim.z) < 0.0001:
		return Vector3i(0, 0, 1)
	if absf(aim.x) >= absf(aim.z):
		return Vector3i(1 if aim.x >= 0.0 else -1, 0, 0)
	return Vector3i(0, 0, 1 if aim.z >= 0.0 else -1)


static func break_cells(shape: int, anchor: Vector3i, aim: Vector3) -> Array[Vector3i]:
	var use_shape := shape if MULTI_BLOCK_BREAK else BreakShape.SINGLE
	var forward := aim_cardinal(aim)
	var right := Vector3i(forward.z, 0, -forward.x)
	var up := Vector3i(0, 1, 0)
	var cells: Array[Vector3i] = []
	for off: Vector2i in _shape_offsets(use_shape):
		cells.append(anchor + right * off.x + up * off.y)
	return cells


static func _shape_offsets(shape: int) -> Array[Vector2i]:
	match shape:
		BreakShape.VERTICAL_1X2:
			return [Vector2i(0, 0), Vector2i(0, 1)]
		BreakShape.LINE_3:
			return [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0)]
		BreakShape.FACE_3X3:
			var face: Array[Vector2i] = [Vector2i(0, 0)]
			for uy in range(-1, 2):
				for rx in range(-1, 2):
					if rx == 0 and uy == 0:
						continue
					face.append(Vector2i(rx, uy))
			return face
		_:
			return [Vector2i(0, 0)]


## Right-click use that must not also place a block. Placeable blocks are not abilities.
static func has_right_click_ability(item_id: String) -> bool:
	var def := get_def(item_id)
	if def.is_empty() or is_placeable_block(item_id):
		return false
	if bool(def.get("right_click", false)) or str(def.get("alt_use", "")) != "":
		return true
	var category := int(def.get("category", -1))
	if category == Category.CONSUMABLE or category == Category.ARMOR:
		return true
	return bool(def.get("throwable", false))


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