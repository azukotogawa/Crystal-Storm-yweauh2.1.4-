class_name WeaponController
extends Node

const _Inventory = preload("res://inventory/inventory.gd")

const _GameManager = preload("res://game/game_manager.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _CombatDef = preload("res://config/combat_def.gd")
const _CombatHitResolver = preload("res://systems/combat_hit_resolver.gd")
const _CombatLog = preload("res://systems/combat_log.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

signal attacked(item_id: String, hit_pos: Vector3)
signal dig_attempted(world_pos: Vector3)
signal entity_hit(target: Node, damage: float, item_id: String)

@export var melee_arc_degrees: float = 70.0

var inventory
var player: Player
var crystal_manager: CrystalManager
var world: InfiniteNoiseWorld

var _cooldown_timer: float = 0.0
var _active_hotbar_index: int = 0
var _terrain_editor: TerrainEditor
var _terrain_bind_attempts: int = 0
var _combat_def: _CombatDef


func _ready() -> void:
	player = get_parent() as Player
	if player:
		inventory = player.inventory
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	world = get_tree().get_first_node_in_group("world")
	_combat_def = _resolve_combat_def()
	_bind_terrain_editor()


func _resolve_combat_def() -> _CombatDef:
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and "game_config" in cfg_svc and cfg_svc.game_config:
		var combat = cfg_svc.game_config.combat
		if combat is _CombatDef:
			return combat
	return _CombatDef.create_default()


func _bind_terrain_editor() -> void:
	_terrain_editor = get_tree().get_first_node_in_group("terrain_editor") as TerrainEditor
	if _terrain_editor == null and _terrain_bind_attempts < 30:
		_terrain_bind_attempts += 1
		call_deferred("_bind_terrain_editor")


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)

	if _GameplayInput.blocks_actions():
		return

	if Input.is_action_just_pressed("attack"):
		_try_attack()
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("build_place"):
		_try_build_wall()
	if Input.is_action_just_pressed("plant"):
		_try_plant()
	if Input.is_action_just_pressed("channel_water"):
		_try_channel_water()

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
	var def := ItemTypes.get_def(item_id)
	if def.is_empty():
		return

	var category := int(def.get("category", -1))
	if category != ItemTypes.Category.WEAPON and category != ItemTypes.Category.TOOL:
		return

	_cooldown_timer = float(def.get("cooldown", 0.5))
	var kind := int(def.get("weapon_kind", ItemTypes.WeaponKind.MELEE))

	match kind:
		ItemTypes.WeaponKind.MELEE:
			_do_melee_attack(item_id, def)
		ItemTypes.WeaponKind.RANGED:
			_do_ranged_attack(item_id, def)
		ItemTypes.WeaponKind.DIG:
			_do_dig_attack(item_id, def)


func _attack_forward() -> Vector3:
	return _ActionTargeting.attack_forward(player)


func _attack_origin(chest_ratio: float = 0.5) -> Vector3:
	return _ActionTargeting.attack_origin_world(player, chest_ratio)


func _do_melee_attack(item_id: String, def: Dictionary) -> void:
	var range_v: float = float(def.get("range", 2.0))
	var origin := _attack_origin(0.5)
	var target_col := _ActionTargeting.target_column(player, range_v)
	var forward := _ActionTargeting.attack_toward_column(player, range_v)
	var hit_pos := Vector3(target_col.x, origin.y, target_col.z)
	var entity_damage: float = _entity_hit_damage(def, _StatIds.MELEE_DAMAGE)

	var targets := _CombatHitResolver.query_melee(
		self,
		origin,
		forward,
		range_v,
		_combat_def,
		melee_arc_degrees
	)
	for target in targets:
		var dealt := _CombatHitResolver.apply_damage(target, entity_damage, StringName(item_id))
		if dealt > 0.0:
			entity_hit.emit(target, dealt, item_id)

	if crystal_manager:
		crystal_manager.damage_spawn_at_world(
			_crystal_target_cell(range_v),
			_crystal_hit_damage(def),
			range_v
		)

	if _combat_def.log_hits_to_console and targets.is_empty():
		_CombatLog.push("melee %s — no entity hit" % item_id)

	attacked.emit(item_id, hit_pos)


func _do_ranged_attack(item_id: String, def: Dictionary) -> void:
	var origin := _attack_origin(0.6)
	var forward := _attack_forward()
	var range_v: float = float(def.get("range", 12.0))
	var hit_pos := origin + forward * range_v
	var entity_damage: float = _entity_hit_damage(def, _StatIds.RANGED_DAMAGE)

	var target := _CombatHitResolver.query_ranged(self, origin, forward, range_v, _combat_def)
	if target:
		var dealt := _CombatHitResolver.apply_damage(target, entity_damage, StringName(item_id))
		if dealt > 0.0:
			entity_hit.emit(target, dealt, item_id)
	elif _combat_def.log_hits_to_console:
		_CombatLog.push("ranged %s — no entity hit" % item_id)

	if crystal_manager:
		crystal_manager.damage_spawn_at_world(
			_crystal_target_cell(range_v),
			_crystal_hit_damage(def, _StatIds.RANGED_DAMAGE),
			2.5
		)

	attacked.emit(item_id, hit_pos)


func _crystal_target_cell(range_v: float) -> Vector2i:
	return _ActionTargeting.target_cell(player, range_v)


func _do_dig_attack(item_id: String, def: Dictionary) -> void:
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		push_warning("WeaponController: terrain_editor not found for dig")
		return
	var range_v: float = float(def.get("range", 2.0))
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT):
		_try_channel_water_at_target(range_v)
		return
	var forward := _attack_forward()
	var target := _ActionTargeting.target_column(player, range_v)
	dig_attempted.emit(target)
	if _terrain_editor.try_dig(target):
		_cooldown_timer = maxf(_cooldown_timer, _terrain_editor.get_dig_delay(target))

	var origin := _attack_origin(0.45)
	var entity_damage: float = _entity_hit_damage(def, _StatIds.MELEE_DAMAGE) * 0.65
	var melee_targets := _CombatHitResolver.query_melee(
		self,
		origin,
		forward,
		float(def.get("range", 2.0)) * 0.9,
		_combat_def,
		melee_arc_degrees * 0.85
	)
	for enemy in melee_targets:
		var dealt := _CombatHitResolver.apply_damage(enemy, entity_damage, StringName(item_id))
		if dealt > 0.0:
			entity_hit.emit(enemy, dealt, item_id)

	if crystal_manager:
		crystal_manager.damage_spawn_at_world(
			_crystal_target_cell(float(def.get("range", 2.0))),
			_crystal_hit_damage(def),
			1.8
		)

	attacked.emit(item_id, target)


func _try_build_wall() -> void:
	if _cooldown_timer > 0.0 or player == null:
		return
	if inventory == null and player:
		inventory = player.inventory
	if inventory == null:
		return
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		return
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	var target := _ActionTargeting.target_column(player, 2.0)
	if _terrain_editor.try_build_wall(target, inventory, inventory.count_item("stone") > 0):
		_cooldown_timer = 0.35


func _player_damage_mult(stat_id: StringName) -> float:
	if player and player.has_method("get_stat"):
		return player.get_stat(stat_id)
	return 1.0


func _entity_hit_damage(def: Dictionary, weapon_stat: StringName) -> float:
	var base := float(def.get("entity_damage", def.get("damage", 5.0)))
	return base * _player_damage_mult(weapon_stat)


func _crystal_hit_damage(def: Dictionary, weapon_stat: StringName = _StatIds.MELEE_DAMAGE) -> float:
	var base := float(def.get("damage", 5.0))
	return base * _player_damage_mult(weapon_stat) * _player_damage_mult(_StatIds.CRYSTAL_DAMAGE)


func _try_plant() -> void:
	if _cooldown_timer > 0.0 or player == null or inventory == null or _terrain_editor == null:
		return
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	var forward := _attack_forward()
	var target := player.voxel_position + forward * 2.0
	var plant_id: StringName
	if Input.is_key_pressed(KEY_SHIFT):
		plant_id = &"tree" if inventory.count_item("wood") >= 3 else &"fern"
	elif Input.is_key_pressed(KEY_CTRL):
		plant_id = &"wildflower"
	elif inventory.count_item("wood") >= 2:
		plant_id = &"bush"
	elif inventory.count_item("herb") >= 2:
		plant_id = &"tall_grass"
	else:
		plant_id = &"grass_tuft"
	if _terrain_editor.try_plant(target, inventory, plant_id):
		_cooldown_timer = _terrain_editor.get_plant_delay()


func _try_channel_water() -> void:
	_try_channel_water_at_target(2.0)


func _try_channel_water_at_target(range_v: float) -> void:
	if _cooldown_timer > 0.0 or player == null or _terrain_editor == null:
		return
	var slot = get_active_item()
	var using_pick: bool = slot != null and str(slot.id) == "stone_pick"
	if not using_pick:
		return
	var forward := _ActionTargeting.attack_toward_column(player, range_v)
	var target := _ActionTargeting.target_column(player, range_v)
	if target == Vector3.ZERO:
		target = player.voxel_position + forward * range_v
	var mode: int = TerrainEditor.ChannelMode.DIG
	if Input.is_key_pressed(KEY_SHIFT):
		mode = TerrainEditor.ChannelMode.RAISE
	elif Input.is_key_pressed(KEY_CTRL):
		mode = TerrainEditor.ChannelMode.REDIRECT
	elif Input.is_key_pressed(KEY_ALT):
		mode = TerrainEditor.ChannelMode.LOWER
	if _terrain_editor.try_channel_water(target, inventory if inventory else null, mode, forward):
		_cooldown_timer = maxf(_cooldown_timer, _terrain_editor.get_channel_delay(target))
