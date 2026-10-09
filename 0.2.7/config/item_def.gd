class_name ItemDef
extends Resource
## Authored item. ItemTypes is the lookup façade (dict API for hotbar/weapons).

enum Category { WEAPON, TOOL, MATERIAL, CONSUMABLE, MISC, ARMOR }
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
@export var crystal_damage: float = 0.0
@export var description: String = ""
## Targets a thrust can pass through. 1 is a normal swing.
@export var pierce: int = 1
## Horizontal shove in voxels. World distance is this times voxel_scale.
@export var knockback: float = 0.8
## Chebyshev splash on crystal cells. 1 is a 3×3. 0 is a single cell.
@export var splash: int = 0
@export var thrust: bool = false
@export var projectile_speed: float = 0.0
@export var projectile_gravity: float = 0.0
## Stack spent per shot. Empty means the shot is free.
@export var ammo_id: String = ""
## Column radius for a thrown blast. 0 means not a bomb.
@export var blast_radius: float = 0.0
@export var throwable: bool = false
## ItemAnim.Kind. -1 derives a pose from the category.
@export var anim_kind: int = -1
## Seconds. 0 uses the action cooldown.
@export var anim_duration: float = 0.0
## 0–1 through the pose when the hit lands. -1 uses the kind default.
@export var impact_ratio: float = -1.0

@export_group("Armor")
## Fraction removed from incoming damage, before the defense stat.
@export var damage_reduction: float = 0.0
@export var move_speed_mult: float = 1.0

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
		"description": description,
	}
	if category == Category.WEAPON or category == Category.TOOL:
		out["weapon_kind"] = int(weapon_kind)
		out["damage"] = damage
		out["entity_damage"] = entity_damage
		out["range"] = attack_range
		out["cooldown"] = cooldown
		out["crystal_damage"] = crystal_damage
		out["pierce"] = pierce
		out["knockback"] = knockback
		out["splash"] = splash
		out["thrust"] = thrust
		out["projectile_speed"] = projectile_speed
		out["projectile_gravity"] = projectile_gravity
		out["ammo_id"] = ammo_id
		out["blast_radius"] = blast_radius
	if category == Category.CONSUMABLE:
		out["heal_amount"] = heal_amount
		out["crystal_damage"] = crystal_damage
		out["damage"] = damage
		out["blast_radius"] = blast_radius
		out["throwable"] = throwable
		out["projectile_speed"] = projectile_speed
		out["projectile_gravity"] = projectile_gravity
		out["knockback"] = knockback
	if category == Category.ARMOR:
		out["damage_reduction"] = damage_reduction
		out["move_speed_mult"] = move_speed_mult
	out["anim_kind"] = anim_kind
	out["anim_duration"] = anim_duration
	out["impact_ratio"] = impact_ratio
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
	d.crystal_damage = float(data.get("crystal_damage", 0.0))
	d.heal_amount = float(data.get("heal_amount", 0.0))
	d.description = str(data.get("description", ""))
	d.pierce = int(data.get("pierce", 1))
	d.knockback = float(data.get("knockback", 0.8))
	d.splash = int(data.get("splash", 0))
	d.thrust = bool(data.get("thrust", false))
	d.projectile_speed = float(data.get("projectile_speed", 0.0))
	d.projectile_gravity = float(data.get("projectile_gravity", 0.0))
	d.ammo_id = str(data.get("ammo_id", ""))
	d.blast_radius = float(data.get("blast_radius", 0.0))
	d.throwable = bool(data.get("throwable", false))
	d.anim_kind = int(data.get("anim_kind", -1))
	d.anim_duration = float(data.get("anim_duration", 0.0))
	d.impact_ratio = float(data.get("impact_ratio", -1.0))
	d.damage_reduction = float(data.get("damage_reduction", 0.0))
	d.move_speed_mult = float(data.get("move_speed_mult", 1.0))
	return d
