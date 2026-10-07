class_name ItemDef
extends Resource
## Authored item. ItemTypes is the lookup façade (dict API for hotbar/weapons).

enum Category { WEAPON, TOOL, MATERIAL, CONSUMABLE, MISC }
enum WeaponKind { MELEE, RANGED, DIG }

const MAX_STACK := 99

@export var id: String = "stone"
@export var display_name: String = "Stone"
@export var category: Category = Category.MATERIAL
## HUD / held-item visual key. Empty means `id`.
@export var visual_id: StringName = &""

@export_group("Stack")
@export var stackable: bool = true
@export var max_stack: int = MAX_STACK

@export_group("Weapon / Tool")
@export var weapon_kind: WeaponKind = WeaponKind.MELEE
@export var damage: float = 0.0
@export var entity_damage: float = 0.0
@export var attack_range: float = 0.0
@export var cooldown: float = 0.0

@export_group("Consumable")
@export var heal_amount: float = 0.0


func resolved_visual_id() -> StringName:
	return visual_id if visual_id != &"" else StringName(id)


func to_lookup() -> Dictionary:
	var out := {
		"name": display_name,
		"category": int(category),
		"stackable": stackable,
		"max_stack": max_stack,
		"visual_id": str(resolved_visual_id()),
	}
	if category == Category.WEAPON or category == Category.TOOL:
		out["weapon_kind"] = int(weapon_kind)
		out["damage"] = damage
		out["entity_damage"] = entity_damage
		out["range"] = attack_range
		out["cooldown"] = cooldown
	if category == Category.CONSUMABLE:
		out["heal_amount"] = heal_amount
	return out


static func from_legacy(item_id: String, data: Dictionary):
	var d = (load("res://config/item_def.gd") as GDScript).new()
	d.id = item_id
	d.display_name = str(data.get("name", item_id))
	d.category = int(data.get("category", Category.MISC)) as Category
	d.visual_id = StringName(str(data.get("visual_id", item_id)))
	d.stackable = bool(data.get("stackable", false))
	d.max_stack = int(data.get("max_stack", 1 if not d.stackable else MAX_STACK))
	d.weapon_kind = int(data.get("weapon_kind", WeaponKind.MELEE)) as WeaponKind
	d.damage = float(data.get("damage", 0.0))
	d.entity_damage = float(data.get("entity_damage", d.damage))
	d.attack_range = float(data.get("range", 0.0))
	d.cooldown = float(data.get("cooldown", 0.0))
	d.heal_amount = float(data.get("heal_amount", 0.0))
	return d
