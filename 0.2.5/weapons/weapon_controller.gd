class_name WeaponController
extends Node

const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

signal attacked(item_id: String, hit_pos: Vector3)
signal dig_attempted(world_pos: Vector3)

@export var melee_arc_degrees: float = 70.0

var inventory
var player: Player
var crystal_manager: CrystalManager
var world: InfiniteNoiseWorld

var _cooldown_timer: float = 0.0
var _active_hotbar_index: int = 0


func _ready() -> void:
	player = get_parent() as Player
	if player:
		inventory = player.inventory
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	world = get_tree().get_first_node_in_group("world")


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)

	if Input.is_action_just_pressed("attack"):
		_try_attack()

	for i in HOTBAR_INPUTS.size():
		if Input.is_action_just_pressed(HOTBAR_INPUTS[i]):
			_active_hotbar_index = i
			if inventory:
				inventory.hotbar_changed.emit(i)


const HOTBAR_INPUTS := [
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4",
	"hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8",
]


func get_active_item() -> Variant:
	if inventory == null:
		return null
	return inventory.get_hotbar_item(_active_hotbar_index)


func get_active_hotbar_index() -> int:
	return _active_hotbar_index


func set_active_hotbar_index(index: int) -> void:
	_active_hotbar_index = clampi(index, 0, _Inventory.HOTBAR_SIZE - 1)
	if inventory:
		inventory.hotbar_changed.emit(_active_hotbar_index)


func _try_attack() -> void:
	if _cooldown_timer > 0.0 or player == null or inventory == null:
		return

	var slot = get_active_item()
	if slot == null:
		return

	var item_id: String = slot.id
	var def := _ItemTypes.get_def(item_id)
	if def.is_empty():
		return

	if not _ItemTypes.is_weapon(item_id) and not _ItemTypes.is_tool(item_id):
		return

	_cooldown_timer = float(def.get("cooldown", 0.5))
	var kind := _ItemTypes.weapon_kind(item_id)

	match kind:
		_ItemTypes.WeaponKind.MELEE:
			_do_melee_attack(item_id, def)
		_ItemTypes.WeaponKind.RANGED:
			_do_ranged_attack(item_id, def)
		_ItemTypes.WeaponKind.DIG:
			_do_dig_attack(item_id, def)


func _attack_forward() -> Vector3:
	var rot: int = player.locked_rotation if player.is_input_locked else (
		player.camera.orbit_rotation if player.camera else 0
	)
	var rad := deg_to_rad(float(rot) * 90.0 + 45.0)
	return Vector3(cos(rad), 0.0, sin(rad)).normalized()


func _do_melee_attack(item_id: String, def: Dictionary) -> void:
	var origin := player.voxel_position + Vector3(0.0, Player.PLAYER_HEIGHT * 0.5, 0.0)
	var forward := _attack_forward()
	var range_v: float = float(def.get("range", 2.0))
	var damage: float = float(def.get("damage", 5.0))
	var hit_pos := origin + forward * range_v

	if crystal_manager:
		crystal_manager.damage_spawn_at_world(
			Vector2i(floori(hit_pos.x), floori(hit_pos.z)),
			damage,
			range_v
		)

	attacked.emit(item_id, hit_pos)


func _do_ranged_attack(item_id: String, def: Dictionary) -> void:
	var origin := player.voxel_position + Vector3(0.0, Player.PLAYER_HEIGHT * 0.6, 0.0)
	var forward := _attack_forward()
	var range_v: float = float(def.get("range", 12.0))
	var damage: float = float(def.get("damage", 8.0))
	var hit_pos := origin + forward * range_v

	if crystal_manager:
		crystal_manager.damage_spawn_at_world(
			Vector2i(floori(hit_pos.x), floori(hit_pos.z)),
			damage,
			2.5
		)

	attacked.emit(item_id, hit_pos)


func _do_dig_attack(item_id: String, def: Dictionary) -> void:
	var forward := _attack_forward()
	var target := player.voxel_position + forward * float(def.get("range", 2.0))
	dig_attempted.emit(target)

	if crystal_manager:
		crystal_manager.damage_spawn_at_world(
			Vector2i(floori(target.x), floori(target.z)),
			float(def.get("damage", 4.0)),
			1.8
		)

	attacked.emit(item_id, target)
