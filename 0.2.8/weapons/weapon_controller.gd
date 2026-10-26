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
const _WorldSettings = preload("res://config/world_settings.gd")
const _PlaceableCatalog = preload("res://helpers/placeable_catalog.gd")
const _Projectile = preload("res://weapons/projectile.gd")
const _WeaponStrike = preload("res://weapons/weapon_strike.gd")
const _LivingForce = preload("res://world/living_force.gd")
const _ItemAnim = preload("res://systems/item_anim.gd")
const _HeldItemView = preload("res://systems/held_item_view.gd")
const _AimIndicator = preload("res://systems/aim_indicator.gd")
const _HitMarkers = preload("res://systems/hit_markers.gd")
const _BlockBreakFx = preload("res://systems/block_break_fx.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _StructureBlueprints = preload("res://helpers/structure_blueprints.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ToolFeel = preload("res://player/tool_feel_cast.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")

signal attacked(item_id: String, hit_pos: Vector3)
signal dig_attempted(world_pos: Vector3)
signal entity_hit(target: Node, damage: float, item_id: String)
signal structure_built(build_id: StringName, world_pos: Vector3)

@export var melee_arc_degrees: float = 70.0

var inventory
var player: Player
var crystal_manager: CrystalManager
var world: InfiniteNoiseWorld

var _cooldown_timer: float = 0.0
var _last_break_cells: Array[Vector3i] = []
var _listed_break: bool = false
var _active_hotbar_index: int = 0
var _terrain_editor: TerrainEditor
var _terrain_bind_attempts: int = 0
var _combat_def: _CombatDef
var _fail_toast_cd: float = 0.0
var _last_fail_toast: String = ""
var _dig_hold_sec: float = 0.0
var _audio: Node
var _build_hold_sec: float = 0.0
var _brush_right_held: bool = false
var brush_index: int = 0
var _brush_known: int = 1
var place_index: int = 0
var blueprint_index: int = 0
var blueprint_quarter: int = 0
var blueprint_place_armed: bool = false
var build_variant: int = 0
const TERRAIN_HOLD_REPEAT_START_SEC: float = 0.16
var _held: _HeldItemView
var _aim: _AimIndicator
var _playback = null
var _pending_mode: int = -1
var _pending_item: String = ""
var _pending_def: Dictionary = {}
var _vfx: Node
var _shown_item: String = ""
var _clock_damage_elapsed: float = -1.0
var _present_bound: bool = false
var _crack_fill: float = 0.0
var _tool_feel = _ToolFeel.new()
var _feel_item := ""
var _feel_def: Dictionary = {}
var _feel_target := Vector3.ZERO
var _feel_resolving := false
var _feel_hit_entities := false


func _ready() -> void:
	player = get_parent() as Player
	if player:
		inventory = player.inventory
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	world = get_tree().get_first_node_in_group("world")
	_combat_def = _resolve_combat_def()
	process_priority = 10
	_bind_terrain_editor()
	call_deferred("_bind_presentation")


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
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("weapon_controller")
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if _fail_toast_cd > 0.0:
		_fail_toast_cd = maxf(_fail_toast_cd - delta, 0.0)

	if _GameplayInput.blocks_actions():
		if _aim:
			_aim.suppress(true)
		_hide_structure_ghost()
		if profiler and profiler.has_method("end"):
			profiler.end("weapon_controller")
		return
	_poll_brush_actions()
	_poll_blueprint_keys()

	# LMB breaks blocks only for the pick and other dig tools.
	# Combat weapons (sword/bow/spear/hammer/sling/bomb): LMB is attack only — never dig or remove.
	# Stone, wood, herbs, and other non-dig items do not break blocks.
	var dig_held := _is_active_dig_tool() and Input.is_action_pressed("attack")
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		if not _is_active_combat_weapon():
			if _is_active_dig_tool():
				if _try_remove_at_cursor():
					_dig_hold_sec = 0.0
					if profiler and profiler.has_method("end"):
						profiler.end("weapon_controller")
					return
	if dig_held:
		var dig_edge := Input.is_action_just_pressed("attack")
		if dig_edge:
			_dig_hold_sec = 0.0
			if _cooldown_timer <= 0.0:
				_try_dig_tool()
		else:
			_dig_hold_sec += delta
			if _dig_hold_sec >= TERRAIN_HOLD_REPEAT_START_SEC and _cooldown_timer <= 0.0:
				_try_dig_tool()
	else:
		_dig_hold_sec = 0.0
		if Input.is_action_just_pressed("attack"):
			if not _try_use_consumable():
				_try_attack()

	var build_held := Input.is_action_pressed("build_place") or Input.is_action_pressed("interact")
	var build_edge := Input.is_action_just_pressed("build_place") or Input.is_action_just_pressed("interact")
	# A right-click ability runs instead of placement and never places a block.
	if build_held and _held_has_right_click_ability():
		if build_edge and _cooldown_timer <= 0.0:
			_try_right_click_ability()
		_build_hold_sec = 0.0
	elif build_held:
		if build_edge:
			_build_hold_sec = 0.0
			if _cooldown_timer <= 0.0:
				_try_place_selected()
		else:
			_build_hold_sec += delta
			if _build_hold_sec >= TERRAIN_HOLD_REPEAT_START_SEC and _cooldown_timer <= 0.0:
				_try_place_selected()
	else:
		_build_hold_sec = 0.0
	if Input.is_action_just_pressed("plant"):
		_try_plant()

	if Input.is_action_just_pressed("place_cycle"):
		place_index = (place_index + 1) % _PlaceableCatalog.count()
	for i in HOTBAR_INPUTS.size():
		if Input.is_action_just_pressed(HOTBAR_INPUTS[i], true):
			select_hotbar(i)
	if Input.is_action_just_pressed("hotbar_next", true):
		select_hotbar(posmod(_active_hotbar_index + 1, _Inventory.HOTBAR_SIZE))
	if Input.is_action_just_pressed("hotbar_prev", true):
		select_hotbar(posmod(_active_hotbar_index - 1, _Inventory.HOTBAR_SIZE))
	# Poses and ranged release share this clock. Hammer damage stays on its wind-up frame.
	_tick_animation_clock(delta)
	_present_held(delta)
	_refresh_structure_ghost()
	if profiler and profiler.has_method("end"):
		profiler.end("weapon_controller")


func _active_item_id() -> String:
	var slot = get_active_item()
	if slot == null:
		return ""
	return str(slot.id)


func _is_build_material() -> bool:
	var id := _active_item_id()
	if ItemTypes.is_placeable_block(id):
		return true
	return _StructureBlueprints.LARGE_STRUCTURES and _StructureBlueprints.ids().has(StringName(id))


func _held_has_right_click_ability() -> bool:
	return ItemTypes.has_right_click_ability(_active_item_id())


## RMB use for herb, armor, bombs, and any item that sets alt_use. Never places.
func _try_right_click_ability() -> void:
	if _cooldown_timer > 0.0:
		return
	var def := ItemTypes.get_def(_active_item_id())
	if str(def.get("alt_use", "")) == "attack":
		_try_attack()
		return
	_try_use_consumable()


func _try_remove_at_cursor() -> bool:
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null or inventory == null:
		return false
	var target := _resolve_terrain_target(_ActionTargeting.reach())
	if target == Vector3.ZERO:
		return false
	if not _terrain_editor.has_method("can_remove") or not _terrain_editor.can_remove(target):
		return false
	if _terrain_editor.try_remove(target, inventory):
		_cooldown_timer = _terrain_editor.get_build_delay(target)
		_flash_build_feedback(target, &"remove")
		var removed_slot = get_active_item()
		if removed_slot != null:
			_sync_impact_pose(str(removed_slot.id))
		_notify_block_break(target)
		return true
	_notify_terrain_fail()
	_cooldown_timer = 0.035
	return true


func _is_active_dig_tool() -> bool:
	var slot = get_active_item()
	if slot == null:
		return false
	return ItemTypes.breaks_blocks(str(slot.id))


func _is_active_combat_weapon() -> bool:
	var slot = get_active_item()
	if slot == null:
		return false
	var def := ItemTypes.get_def(str(slot.id))
	if def.is_empty():
		return false
	var category := int(def.get("category", -1))
	if category == ItemTypes.Category.ARMOR:
		return true
	if category == ItemTypes.Category.CONSUMABLE and bool(def.get("throwable", false)):
		return true
	if category != ItemTypes.Category.WEAPON:
		return false
	var kind := int(def.get("weapon_kind", ItemTypes.WeaponKind.MELEE))
	return kind == ItemTypes.WeaponKind.MELEE or kind == ItemTypes.WeaponKind.RANGED


func _try_dig_tool() -> void:
	if player == null or inventory == null:
		return
	var slot = get_active_item()
	if slot == null:
		return
	var item_id: String = str(slot.id)
	var def := ItemTypes.get_def(item_id)
	if def.is_empty():
		return
	var reach := brush_reach()
	var aim := _aim_forward(reach)
	var anchor := _dig_anchor_cell(reach)
	_last_break_cells = _brush_cells(false, anchor, aim) if anchor != Vector3i.ZERO else ([] as Array[Vector3i])
	_listed_break = ItemTypes.MULTI_BLOCK_BREAK
	_offer_tool_action("multi_block_break", item_id, def)


func _brush_cells(place: bool, anchor: Vector3i, aim: Vector3) -> Array[Vector3i]:
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		return [anchor]
	return _terrain_editor.brush_plan(brush_shape(), anchor, aim, place, player, brush_reach())


func brush_shape() -> int:
	var order := ItemTypes.BRUSH_ORDER
	return order[clampi(brush_index, 0, order.size() - 1)]


func brush_reach() -> float:
	return _GameFeelConfig.active().brush_reach


func brush_mastery() -> int:
	if not is_inside_tree():
		return 0
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return 0
	return int(gm.get("blocks_mined")) + int(gm.get("blocks_placed"))


func brush_unlocked_count() -> int:
	var cfg = _GameFeelConfig.active()
	var mastery := brush_mastery()
	var count := 0
	for shape in ItemTypes.BRUSH_ORDER:
		if mastery < cfg.brush_unlock(ItemTypes.brush_id(shape)):
			break
		count += 1
	return maxi(count, 1)


func brush_tool_active() -> bool:
	if _is_active_dig_tool():
		return true
	return _is_build_material() and active_blueprint_id() == &"" and get_place_id() == "fill"


func action_reach() -> float:
	if brush_tool_active():
		return brush_reach()
	return _ActionTargeting.reach()


func _poll_brush_actions() -> void:
	if not brush_tool_active():
		return
	var step := 0
	if Input.is_action_just_pressed("brush_grow"):
		step = 1
	elif Input.is_action_just_pressed("brush_shrink"):
		step = -1
	if step == 0:
		return
	brush_index = posmod(brush_index + step, brush_unlocked_count())
	_toast("Brush: %s" % ItemTypes.brush_label(brush_shape()))


func _announce_brush_unlock() -> void:
	var count := brush_unlocked_count()
	if count <= _brush_known:
		return
	_brush_known = count
	var shape: int = ItemTypes.BRUSH_ORDER[count - 1]
	_toast("New brush unlocked: %s. Press ] to use it" % ItemTypes.brush_label(shape))


func break_cells_for(item_id: String, anchor: Vector3i, aim: Vector3) -> Array[Vector3i]:
	return ItemTypes.break_cells(ItemTypes.break_shape_for(item_id), anchor, aim)


func _dig_anchor_cell(range_v: float) -> Vector3i:
	var target := _resolve_terrain_target(range_v)
	if target == Vector3.ZERO:
		return Vector3i.ZERO
	var wx := floori(target.x)
	var wz := floori(target.z)
	var block_y := floori(target.y)
	if player != null and player.world != null:
		block_y = TerrainEdits.surface_block_y(player.world, wx, wz)
	return Vector3i(wx, block_y, wz)


func _try_use_consumable() -> bool:
	if player == null or inventory == null:
		return false
	if _cooldown_timer > 0.0:
		return false
	var slot = get_active_item()
	if slot == null:
		return false
	var item_id: String = str(slot.id)
	var def := ItemTypes.get_def(item_id)
	if def.is_empty():
		return false
	var category := int(def.get("category", -1))
	if category == ItemTypes.Category.ARMOR:
		if inventory.has_method("equip_armor") and inventory.equip_armor(item_id):
			_cooldown_timer = 0.2
			_toast("Wearing %s" % ItemTypes.display_name(item_id))
			_sfx("ui_click")
			return true
		return false
	if category != ItemTypes.Category.CONSUMABLE:
		return false
	if bool(def.get("throwable", false)):
		return _throw_bomb(item_id, def)
	if item_id != "herb":
		return false
	if not inventory.consume_item("herb", 1):
		return false
	var heal_amt: float = 28.0
	if "heal_amount" in def:
		heal_amt = float(def.heal_amount)
	if player.has_method("heal"):
		player.heal(heal_amt)
	elif "health" in player and "max_health" in player:
		player.health = minf(float(player.max_health), float(player.health) + heal_amt)
	_sync_impact_pose(item_id)
	_cooldown_timer = 0.35
	_sfx("pickup")
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", "Used herb (+%.0f HP)" % heal_amt)
	return true


const HOTBAR_INPUTS := [
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4",
	"hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8",
	"hotbar_9", "hotbar_10",
]


func get_active_item() -> Variant:
	if inventory == null:
		return null
	return inventory.get_hotbar_item(_active_hotbar_index)


func get_active_hotbar_index() -> int:
	return _active_hotbar_index


func select_hotbar(index: int) -> void:
	_cancel_pending_strike()
	_active_hotbar_index = clampi(index, 0, _Inventory.HOTBAR_SIZE - 1)
	_shown_item = ""
	if inventory:
		inventory.hotbar_changed.emit(_active_hotbar_index)


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

	var kind := int(def.get("weapon_kind", ItemTypes.WeaponKind.MELEE))
	if kind == ItemTypes.WeaponKind.DIG:
		_do_dig_attack(item_id, def)
		return
	var feel_id := _configured_attack_id(item_id, def)
	if feel_id != "":
		_offer_tool_action(feel_id, item_id, def)
		return

	_cooldown_timer = float(def.get("cooldown", 0.5))
	match kind:
		ItemTypes.WeaponKind.MELEE:
			_arm_clock(item_id, def, 0)
		ItemTypes.WeaponKind.RANGED:
			_arm_clock(item_id, def, 1)


func _range_world(range_columns: float) -> float:
	# Item range is authored in columns; hit queries use world units.
	return maxf(range_columns, 0.0) * _WorldSettings.get_active().voxel_scale


func _attack_forward() -> Vector3:
	return _ActionTargeting.attack_forward(player)


func _aim_forward(range_v: float) -> Vector3:
	if _held_is_ranged():
		var aimed := _ActionTargeting.cursor_cell_under_mouse(player, range_v)
		if aimed != Vector3.ZERO and player != null and "voxel_position" in player:
			var offset := Vector3(aimed.x - float(player.voxel_position.x), 0.0, aimed.z - float(player.voxel_position.z))
			if offset.length_squared() > 0.04:
				return offset.normalized()
	return _ActionTargeting.cursor_aim(player, range_v)


func _held_is_ranged() -> bool:
	var def := ItemTypes.get_def(_active_item_id())
	if def.is_empty():
		return false
	return int(def.get("category", -1)) == ItemTypes.Category.WEAPON \
		and int(def.get("weapon_kind", -1)) == ItemTypes.WeaponKind.RANGED


func _held_aim_range() -> float:
	var def := ItemTypes.get_def(_active_item_id())
	if def.is_empty():
		return _ActionTargeting.reach()
	var category := int(def.get("category", -1))
	var kind := int(def.get("weapon_kind", ItemTypes.WeaponKind.MELEE))
	if category == ItemTypes.Category.WEAPON and (kind == ItemTypes.WeaponKind.MELEE or kind == ItemTypes.WeaponKind.RANGED):
		return float(def.get("range", 2.0))
	return _ActionTargeting.reach()


func _face_held() -> void:
	if _held == null or player == null:
		return
	var aim := _aim_forward(_held_aim_range())
	_held.face(aim)
	_held.pose_rig(aim)


func _attack_origin(chest_ratio: float = 0.5) -> Vector3:
	return _ActionTargeting.attack_origin_world(player, chest_ratio)


func _do_melee_attack(item_id: String, def: Dictionary) -> void:
	if bool(def.get("thrust", false)):
		_do_thrust_attack(item_id, def)
		return
	if int(def.get("splash", 0)) > 0:
		_do_hammer_attack(item_id, def)
		return
	_sfx("swing_sword", _attack_origin(0.5))
	var range_v: float = float(def.get("range", 2.0))
	var origin := _attack_origin(0.5)
	var chunk_manager: ChunkManager = get_tree().get_first_node_in_group("chunk_manager") as ChunkManager if is_inside_tree() else null
	var aim: Dictionary = _ActionTargeting.resolve_action(
		player, world, chunk_manager, range_v, false, &"attack"
	)
	var target_col: Vector3 = aim.get("column", Vector3.ZERO)
	if target_col == Vector3.ZERO:
		target_col = _ActionTargeting.target_column(player, range_v)
	var forward := _ActionTargeting.attack_toward_column(player, range_v)
	var ws = _WorldSettings.get_active()
	var hit_pos := Vector3(ws.column_to_world(target_col.x), origin.y, ws.column_to_world(target_col.z))
	var entity_damage: float = _entity_hit_damage(def, _StatIds.MELEE_DAMAGE)
	var connected := false
	var saw_target := false

	var range_w := _range_world(range_v)
	var targets := _query_melee_facing(origin, forward, range_w)
	for target in targets:
		saw_target = true
		var dealt := _CombatHitResolver.apply_damage(target, entity_damage, StringName(item_id))
		if dealt > 0.0:
			connected = true
			_shove(target, float(def.get("knockback", 1.0)))
			entity_hit.emit(target, dealt, item_id)

	if crystal_manager:
		var mass_cell := _crystal_target_cell(range_v)
		crystal_manager.damage_spawn_at_world(
			mass_cell,
			_crystal_hit_damage(def),
			range_v
		)
		if _try_break_crystal_mass(mass_cell, def):
			connected = true

	if not connected:
		_note_attack(hit_pos, _HitMarkers.Result.BLOCKED if saw_target else _HitMarkers.Result.MISS)

	if _combat_def.log_hits_to_console and targets.is_empty():
		_CombatLog.push("melee %s — no entity hit" % item_id)

	attacked.emit(item_id, hit_pos)


func _query_melee_facing(origin: Vector3, forward: Vector3, range_w: float) -> Array[Node]:
	if forward.length_squared() < 0.0001:
		return []
	var targets := _CombatHitResolver.query_melee(
		self,
		origin,
		forward,
		range_w,
		_combat_def,
		melee_arc_degrees
	)
	if targets.is_empty():
		targets = _CombatHitResolver.query_melee(
			self,
			origin,
			forward,
			range_w,
			_combat_def,
			180.0
		)
	if targets.is_empty():
		targets = _point_blank_melee(origin, forward)
	return targets


func _point_blank_melee(origin: Vector3, forward: Vector3) -> Array[Node]:
	var blank_w := _range_world(0.5)
	if blank_w <= 0.0:
		return []
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		return []
	flat = flat.normalized()
	var side := Vector3(-flat.z, 0.0, flat.x)
	var found: Array[Node] = []
	var dirs: Array[Vector3] = [flat, -flat, side, -side]
	for dir in dirs:
		for node in _CombatHitResolver.query_melee(self, origin, dir, blank_w, _combat_def, 90.0):
			if found.has(node):
				continue
			found.append(node)
	return found


func _do_ranged_attack(item_id: String, def: Dictionary) -> void:
	var origin := _attack_origin(0.6)
	var range_v: float = float(def.get("range", 12.0))
	var forward := _aim_forward(range_v)
	var hit_pos := origin + forward * _range_world(range_v)
	if not _fire_projectile(item_id, def, origin, forward, false):
		_cooldown_timer = 0.25
		_note_attack(origin, _HitMarkers.Result.BLOCKED)
		return
	_sfx("fire_sling" if item_id == "sling" else "fire_bow", origin)
	attacked.emit(item_id, hit_pos)


func _do_thrust_attack(item_id: String, def: Dictionary) -> void:
	var range_v: float = float(def.get("range", 3.0))
	var origin := _attack_origin(0.5)
	_sfx("swing_spear", origin)
	var forward := _aim_forward(range_v)
	var range_w := _range_world(range_v)
	var nodes: Array = _CombatHitResolver._combat_nodes(self, origin, range_w + 2.0)
	var targets := _WeaponStrike.thrust_targets(
		origin, forward, range_w, nodes, int(def.get("pierce", 2))
	)
	var entity_damage: float = _entity_hit_damage(def, _StatIds.MELEE_DAMAGE)
	var connected := false
	var saw_target := false
	for target in targets:
		saw_target = true
		var dealt := _CombatHitResolver.apply_damage(target, entity_damage, StringName(item_id))
		if dealt > 0.0:
			connected = true
			_shove(target, float(def.get("knockback", 1.6)))
			entity_hit.emit(target, dealt, item_id)
	if crystal_manager:
		var mass_cell := _crystal_target_cell(range_v)
		crystal_manager.damage_spawn_at_world(mass_cell, _crystal_hit_damage(def), range_v)
		if _try_break_crystal_mass(mass_cell, def):
			connected = true
	var ws = _WorldSettings.get_active()
	var aim := _crystal_target_cell(range_v)
	var thrust_pos := Vector3(ws.column_to_world(float(aim.x) + 0.5), origin.y, ws.column_to_world(float(aim.y) + 0.5))
	if not connected:
		_note_attack(thrust_pos, _HitMarkers.Result.BLOCKED if saw_target else _HitMarkers.Result.MISS)
	attacked.emit(item_id, thrust_pos)


## 3×3 crystal splash. Low entity damage, heavy knockback. Never digs or changes height.
func _do_hammer_attack(item_id: String, def: Dictionary) -> void:
	var range_v: float = float(def.get("range", 2.2))
	var origin := _attack_origin(0.45)
	_sfx("swing_hammer", origin)
	var forward := _aim_forward(range_v)
	var cell := _ActionTargeting.cell_column(_ActionTargeting.column_toward_cursor(player, range_v))
	var splash := int(def.get("splash", 1))
	var cells := _WeaponStrike.splash_cells(cell, splash)
	var mass := _crystal_mass_damage(def)
	var crystal_hits := _WeaponStrike.apply_crystal_cells(crystal_manager, cells, mass)
	if crystal_manager:
		crystal_manager.damage_spawn_at_world(cell, _crystal_hit_damage(def), 1.6)
	var range_w := _range_world(range_v)
	var targets := _query_melee_facing(origin, forward, range_w)
	var entity_damage: float = _entity_hit_damage(def, _StatIds.MELEE_DAMAGE)
	var shoved := 0
	var connected := crystal_hits > 0
	for target in targets:
		if shoved >= 1:
			break
		var dealt := _CombatHitResolver.apply_damage(target, entity_damage, StringName(item_id))
		if dealt > 0.0:
			connected = true
			_shove(target, float(def.get("knockback", 3.2)))
			entity_hit.emit(target, dealt, item_id)
			shoved += 1
	var ws = _WorldSettings.get_active()
	var hammer_pos := Vector3(
		ws.column_to_world(float(cell.x) + 0.5),
		origin.y,
		ws.column_to_world(float(cell.y) + 0.5)
	)
	if not connected and shoved == 0 and targets.is_empty():
		_note_attack(hammer_pos, _HitMarkers.Result.MISS)
	attacked.emit(item_id, hammer_pos)


func _throw_bomb(item_id: String, def: Dictionary) -> bool:
	if inventory == null or not inventory.consume_item(item_id, 1):
		return false
	var origin := _attack_origin(0.7)
	var forward := _aim_forward(float(def.get("range", 6.0)))
	if not _fire_projectile(item_id, def, origin, forward, true):
		inventory.add_item(item_id, 1)
		return false
	_sfx("bomb_throw", origin)
	_sync_impact_pose(item_id)
	_cooldown_timer = 0.9
	var hit_pos := origin + forward * _range_world(float(def.get("blast_radius", 2.5)))
	attacked.emit(item_id, hit_pos)
	return true


func _fire_projectile(item_id: String, def: Dictionary, origin: Vector3, forward: Vector3, lob: bool) -> bool:
	var ammo := str(def.get("ammo_id", ""))
	if ammo != "" and (inventory == null or not inventory.consume_item(ammo, 1)):
		_toast("Need %s" % ammo)
		return false
	var speed := float(def.get("projectile_speed", 28.0))
	if speed <= 0.0:
		speed = 28.0
	var vel := forward * speed
	if lob or item_id == "sling":
		vel.y += speed * 0.55
	var kind := "arrow"
	if item_id == "sling":
		kind = "stone"
	elif item_id == "crystal_bomb":
		kind = "bomb"
	var vs: float = _WorldSettings.get_active().voxel_scale
	var chunk_manager = get_tree().get_first_node_in_group("chunk_manager") if is_inside_tree() else null
	var muzzle := origin + forward * (vs * 0.65)
	var ok := _Projectile.launch(self, {
		"origin": muzzle,
		"velocity": vel,
		"gravity": float(def.get("projectile_gravity", 12.0)),
		"damage": _entity_hit_damage(def, _StatIds.RANGED_DAMAGE if not lob else _StatIds.MELEE_DAMAGE),
		"crystal_damage": _crystal_mass_damage(def) if item_id != "crystal_bomb" else float(def.get("crystal_damage", 3.2)),
		"knockback": float(def.get("knockback", 0.8)) * vs,
		"blast_radius": float(def.get("blast_radius", 0.0)),
		"source": item_id,
		"kind": kind,
		"ttl": 1.35 if kind == "bomb" else 2.8,
		"crystal": crystal_manager,
		"world": world,
		"chunk_manager": chunk_manager,
	})
	if not ok and ammo != "" and inventory:
		inventory.add_item(ammo, 1)
	return ok


func _shove(target: Node, voxels: float) -> void:
	if voxels <= 0.0 or target == null or not target.has_method("apply_knockback"):
		return
	var origin := _attack_origin(0.5)
	var center: Vector3 = (target as Node3D).global_position
	if target.has_method("get_combat_center"):
		center = target.get_combat_center()
	target.apply_knockback(center - origin, voxels * _WorldSettings.get_active().voxel_scale)


func _toast(text: String) -> void:
	if not is_inside_tree():
		return
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", text)


func _crystal_target_cell(range_v: float) -> Vector2i:
	return _ActionTargeting.target_cell(player, range_v)


func _notify_terrain_fail() -> void:
	if _terrain_editor == null:
		return
	var reason: String = str(_terrain_editor.get("last_fail_reason")) if "last_fail_reason" in _terrain_editor else ""
	if reason.is_empty():
		return
	if _fail_toast_cd > 0.0 and reason == _last_fail_toast:
		return
	_fail_toast_cd = 0.5
	_last_fail_toast = reason
	if player:
		_note_attack(player.global_position + _attack_forward() * _WorldSettings.get_active().voxel_scale, _HitMarkers.Result.BLOCKED)
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", reason)


func _do_dig_attack(item_id: String, def: Dictionary) -> void:
	var listed := _listed_break and ItemTypes.MULTI_BLOCK_BREAK
	_listed_break = false
	if not _is_active_dig_tool():
		return
	_sync_impact_pose(item_id)
	_sfx("swing_pick", _attack_origin(0.45) if player else null)
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		push_warning("WeaponController: terrain_editor not found for dig")
		return
	var range_v: float = _ActionTargeting.reach()
	var forward := _aim_forward(float(def.get("range", 2.0)))
	var crystal_cell := _crystal_target_cell(range_v)
	if _try_break_crystal_mass(crystal_cell, def):
		if crystal_manager:
			crystal_manager.damage_spawn_at_world(
				crystal_cell,
				_crystal_hit_damage(def),
				1.8
			)
		_cooldown_timer = maxf(float(def.get("cooldown", 0.1)), 0.08)
		var ws_hit = _WorldSettings.get_active()
		attacked.emit(item_id, Vector3(
			ws_hit.column_to_world(float(crystal_cell.x) + 0.5),
			player.voxel_position.y if player else 0.0,
			ws_hit.column_to_world(float(crystal_cell.y) + 0.5)
		))
		return
	var target := _resolve_terrain_target(range_v)
	if target == Vector3.ZERO:
		_notify_terrain_fail()
		_cooldown_timer = 0.04
		return
	if _terrain_editor.has_method("can_remove") and _terrain_editor.can_remove(target):
		var removed: bool = _terrain_editor.try_remove(target, inventory)
		if removed:
			_cooldown_timer = _terrain_editor.get_build_delay(target)
			_flash_build_feedback(target, &"remove")
			_notify_block_break(target)
			_sfx("build_remove", target)
		else:
			_notify_terrain_fail()
			_cooldown_timer = 0.04
		return
	dig_attempted.emit(target)
	var dug := false
	var batch: Dictionary = {}
	if listed:
		batch = TerrainEdits.dig_cells(_last_break_cells, _terrain_editor)
		dug = int(batch.get("dug_count", 0)) > 0
	elif _terrain_editor.has_method("try_dig_brush") and _terrain_editor.try_dig_brush(target, dig_brush_radius(), player):
		dug = true
	if dug:
		var broken := 1
		if listed:
			broken = maxi(int(batch.get("dug_count", 1)), 1)
		var mined := broken
		if not listed and _terrain_editor != null and "last_stroke_stats" in _terrain_editor:
			var cells := int(_terrain_editor.last_stroke_stats.get("cell_count", 0))
			mined = cells
		if mined > 0:
			_note_mined_blocks(mined)
		_cooldown_timer = _terrain_editor.get_dig_delay(target) + _GameFeelConfig.active().brush_extra_sec(broken)
		_flash_dig_feedback(target)
		if listed:
			_notify_scaled_break(batch.get("dug", []), target)
			if broken > 1:
				_toast("Broke %d blocks" % broken)
			if inventory != null:
				inventory.wear_tool(_active_hotbar_index, ItemTypes.brush_wear(broken))
			_announce_brush_unlock()
		else:
			_notify_block_break(target)
	else:
		_notify_terrain_fail()
		_cooldown_timer = 0.04

	if Input.is_action_just_pressed("attack") or (_feel_resolving and _feel_hit_entities):
		var origin := _attack_origin(0.45)
		var entity_damage: float = _entity_hit_damage(def, _StatIds.MELEE_DAMAGE) * 0.65
		var melee_targets := _CombatHitResolver.query_melee(
			self,
			origin,
			forward,
			_range_world(float(def.get("range", 2.0)) * 0.9),
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


func _note_mined_blocks(count: int) -> void:
	if count <= 0 or not is_inside_tree():
		return
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("note_blocks_mined"):
		gm.note_blocks_mined(count)


func dig_brush_radius() -> int:
	if not _is_active_dig_tool():
		return _LivingForce.BRUSH_RADIUS_DEFAULT
	var slot = get_active_item()
	if slot == null:
		return _LivingForce.BRUSH_RADIUS_DEFAULT
	return _LivingForce.radius_for_item(str(slot.id))


func _poll_dig_brush_keys() -> void:
	if not _is_active_dig_tool():
		return
	var slot = get_active_item()
	var item_id := str(slot.id) if slot != null else "stone_pick"
	if Input.is_action_just_pressed("brush_shrink"):
		_LivingForce.adjust_session_bias(-1, item_id)
		_toast("Dig brush %d" % dig_brush_radius())
	if Input.is_action_just_pressed("brush_grow"):
		_LivingForce.adjust_session_bias(1, item_id)
		_toast("Dig brush %d" % dig_brush_radius())


func selected_blueprint_id() -> StringName:
	var ids := _StructureBlueprints.ids()
	if ids.is_empty():
		return &""
	return ids[posmod(blueprint_index, ids.size())]


func rotate_selected_blueprint(steps: int = 1) -> void:
	blueprint_place_armed = true
	blueprint_quarter = posmod(blueprint_quarter + steps, 4)


func cycle_selected_blueprint(steps: int = 1) -> void:
	blueprint_place_armed = true
	var ids := _StructureBlueprints.ids()
	if ids.is_empty():
		blueprint_index = 0
		blueprint_quarter = 0
		return
	blueprint_index = posmod(blueprint_index + steps, ids.size())
	blueprint_quarter = 0


func preview_selected_blueprint(column: Vector3, world) -> Dictionary:
	return ghost_preview(active_blueprint_id(), column, blueprint_quarter, world)


func _adopt_hotbar_blueprint() -> void:
	if not _StructureBlueprints.LARGE_STRUCTURES:
		return
	var slot = get_active_item()
	if slot == null:
		return
	var ids := _StructureBlueprints.ids()
	var at := ids.find(StringName(str(slot.id)))
	if at < 0:
		return
	if blueprint_index != at:
		blueprint_quarter = 0
	blueprint_index = at


func active_blueprint_id() -> StringName:
	if not _StructureBlueprints.LARGE_STRUCTURES:
		return &""
	_adopt_hotbar_blueprint()
	var place_id := get_place_id()
	var ids := _StructureBlueprints.ids()
	if ids.has(StringName(place_id)):
		return StringName(place_id)
	var slot = get_active_item()
	if slot != null and ids.has(StringName(str(slot.id))):
		return StringName(str(slot.id))
	if not blueprint_place_armed:
		return &""
	return selected_blueprint_id()


static func snap_blueprint_anchor(column: Vector3) -> Vector2i:
	return Vector2i(floori(column.x), floori(column.z))


static func rotate_blueprint_cell(cell: Vector3i, quarter: int) -> Vector3i:
	var q := posmod(quarter, 4)
	var x := cell.x
	var y := cell.y
	var z := cell.z
	if q == 1:
		return Vector3i(z, y, -x)
	if q == 2:
		return Vector3i(-x, y, -z)
	if q == 3:
		return Vector3i(-z, y, x)
	return Vector3i(x, y, z)


static func ghost_preview(blueprint_id: StringName, column: Vector3, quarter: int, world) -> Dictionary:
	var anchor := snap_blueprint_anchor(column)
	var turned := posmod(quarter, 4)
	var bp := _StructureBlueprints.get_blueprint(blueprint_id)
	if bp.is_empty():
		return {
			"id": String(blueprint_id),
			"anchor": anchor,
			"quarter": turned,
			"valid": false,
			"cells": [],
		}
	var base_y := TerrainEdits.surface_block_y(world, anchor.x, anchor.y) + 1
	var raw: Array[Dictionary] = []
	var lows := {}
	for cell in _blueprint_rows(bp):
		var local := Vector3i(int(cell["x"]), int(cell["y"]), int(cell["z"]))
		var spun := rotate_blueprint_cell(local, turned)
		var at := Vector3i(anchor.x + spun.x, base_y + spun.y, anchor.y + spun.z)
		var key := Vector2i(at.x, at.z)
		if not lows.has(key) or spun.y < int(lows[key]):
			lows[key] = spun.y
		raw.append({
			"at": at,
			"local_y": spun.y,
			"role": str(cell.get("role", "wall")),
			"build": str(cell.get("build", bp.get("build_id", ""))),
		})
	var reasons := {}
	for item in raw:
		var at: Vector3i = item["at"]
		var key := Vector2i(at.x, at.z)
		if int(item["local_y"]) != int(lows[key]):
			continue
		reasons[key] = _column_ghost_reason(at, world)
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var cells: Array = []
	var all_ok := true
	for item in raw:
		var at: Vector3i = item["at"]
		var key := Vector2i(at.x, at.z)
		var reason := str(reasons.get(key, "blocked"))
		var ok := reason == "ok"
		if not ok:
			all_ok = false
		cells.append({
			"at": at,
			"valid": ok,
			"reason": reason,
			"role": str(item.get("role", "wall")),
			"build": str(item.get("build", "")),
			"position": Vector3(
				ws.column_to_world(float(at.x) + 0.5),
				float(at.y) * layer + layer * 0.5,
				ws.column_to_world(float(at.z) + 0.5)
			),
		})
	return {
		"id": String(blueprint_id),
		"anchor": anchor,
		"quarter": turned,
		"valid": all_ok,
		"cells": cells,
	}


static func _blueprint_rows(bp: Dictionary) -> Array:
	var rows: Array = []
	for cell in bp.get("cells", []):
		rows.append(cell)
	for cell in bp.get("passages", []):
		rows.append(cell)
	return rows


static func _column_ghost_reason(base_cell: Vector3i, world) -> String:
	if not TerrainEdits.can_edit(base_cell.x, base_cell.z):
		return "blocked"
	var ground := TerrainEdits.surface_block_y(world, base_cell.x, base_cell.z)
	if base_cell.y <= ground:
		return "blocked"
	if _column_has_build(base_cell.x, base_cell.z) and base_cell.y <= ground + 1:
		return "blocked"
	if base_cell.y > ground + 1:
		return "unsupported"
	return "ok"


static func _column_has_build(wx: int, wz: int) -> bool:
	if TerrainEdits.get_build_tile(wx, wz) >= 0:
		return true
	var feat := _FeatureRegistry.get_feature(wx, wz)
	return str(feat.get("build_id", "")).strip_edges() != ""


func _poll_blueprint_keys() -> void:
	if not _StructureBlueprints.LARGE_STRUCTURES:
		return
	if Input.is_action_just_pressed("rotate_piece", true):
		rotate_selected_blueprint(1)
	if Input.is_action_just_pressed("rotate_piece_back", true):
		rotate_selected_blueprint(-1)
	if Input.is_action_just_pressed("place_variant"):
		build_variant = (build_variant + 1) % 3
		cycle_selected_blueprint(1)


func _structure_ghost_wanted() -> bool:
	if not _StructureBlueprints.LARGE_STRUCTURES or active_blueprint_id() == &"":
		return false
	if _held_has_right_click_ability():
		return false
	if _is_build_material():
		return true
	if not (Input.is_action_pressed("build_place") or Input.is_action_pressed("interact")):
		return false
	if inventory == null and player:
		inventory = player.inventory
	if inventory == null or not inventory.has_method("count_item"):
		return false
	return int(inventory.count_item("stone")) > 0 or int(inventory.count_item("wood")) > 0


func _hide_structure_ghost() -> void:
	if player == null:
		return
	var hl = player.get_node_or_null("TargetHighlight")
	if hl and hl.has_method("hide_structure_ghost"):
		hl.hide_structure_ghost()


func _refresh_structure_ghost() -> void:
	if player == null:
		return
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("show_structure_ghost"):
		return
	if not _structure_ghost_wanted():
		hl.hide_structure_ghost()
		return
	if world == null and is_inside_tree():
		world = get_tree().get_first_node_in_group("world")
	var column := Vector3.ZERO
	if hl.has_method("get_action_column"):
		column = hl.get_action_column()
	if column == Vector3.ZERO:
		hl.hide_structure_ghost()
		return
	var plan := ghost_preview(active_blueprint_id(), column, blueprint_quarter, world)
	hl.show_structure_ghost(plan.get("cells", []))


func get_place_id() -> String:
	return _PlaceableCatalog.id_at(place_index)


func get_place_label() -> String:
	return _PlaceableCatalog.display_name(get_place_id())


func _try_place_selected() -> bool:
	if _held_has_right_click_ability():
		return false
	if _cooldown_timer > 0.0 or player == null:
		return false
	if inventory == null and player:
		inventory = player.inventory
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		return false
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.run_state != _GameManager.RunState.PLAYING:
		return false
	var target := _feel_target if _feel_resolving and _feel_target != Vector3.ZERO else _resolve_terrain_target(action_reach())
	if target == Vector3.ZERO:
		_notify_terrain_fail()
		_cooldown_timer = 0.035
		return false
	if not _feel_resolving:
		_feel_target = target
		_offer_tool_action("building_placement", get_place_id(), {})
		return false
	var place_id: String = get_place_id()
	var built_id := StringName(place_id)
	var ok := false
	if _StructureBlueprints.LARGE_STRUCTURES and _terrain_editor.has_method("try_repair_structure") and _terrain_editor.try_repair_structure(target, inventory):
		ok = true
		built_id = &"repair"
	elif _StructureBlueprints.LARGE_STRUCTURES and active_blueprint_id() != &"":
		built_id = active_blueprint_id()
		ok = _terrain_editor.try_place_blueprint(target, inventory, built_id, blueprint_quarter)
	else:
		match place_id:
			"fill":
				ok = _place_fill(target)
			"cardinal_ramp":
				ok = _terrain_editor.try_place_cardinal_ramp(target, inventory)
			"corner_ramp":
				ok = _terrain_editor.try_place_corner_ramp(target, inventory)
			"gate":
				ok = _terrain_editor.try_build_gate(target, inventory)
			"bridge":
				ok = _terrain_editor.try_build_bridge(target, inventory)
			_:
				ok = _terrain_editor.try_build(target, inventory, &"stone_wall")
	if ok:
		_cooldown_timer = _terrain_editor.get_build_delay(target)
		if built_id == &"fill" and brush_shape() != ItemTypes.BreakShape.SINGLE:
			_cooldown_timer += _GameFeelConfig.active().brush_extra_sec(int(_terrain_editor.last_place_batch.get("placed_count", 1)))
		structure_built.emit(built_id, target)
		_flash_build_feedback(target, built_id)
		_sync_impact_pose(_place_anim_id())
		_notify_block_place(target)
		_sfx("build_place", target)
	else:
		_notify_terrain_fail()
		_cooldown_timer = 0.035
	return ok


func _place_fill(target: Vector3) -> bool:
	if brush_shape() == ItemTypes.BreakShape.SINGLE:
		var placed: bool = _terrain_editor.try_fill(target, inventory)
		if placed:
			_note_placed_blocks(1)
		return placed
	var ok: bool = _terrain_editor.try_place_brush(target, inventory, brush_shape(), _aim_forward(brush_reach()), player, brush_reach())
	if ok:
		var count := int(_terrain_editor.last_place_batch.get("placed_count", 0))
		var paid := str(_terrain_editor.last_place_batch.get("paid", "stone"))
		_note_placed_blocks(count)
		_toast("Placed %d blocks, spent %d %s" % [count, count, paid])
		var fx := _break_fx()
		if fx != null and fx.has_method("notify_place"):
			var shown := 0
			for cell in _terrain_editor.last_place_batch.get("placed", []):
				if shown >= _BlockBreakFx.SWING_FX_CAP:
					break
				fx.notify_place(_cell_fx_pos(cell), Color(0.45, 0.82, 0.42))
				shown += 1
		_announce_brush_unlock()
	return ok


func _note_placed_blocks(count: int) -> void:
	if count <= 0 or not is_inside_tree():
		return
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("note_blocks_placed"):
		gm.note_blocks_placed(count)


func _try_build_wall() -> void:
	_try_place_selected()


func _resolve_terrain_target(range_v: float) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var hl = player.get_node_or_null("TargetHighlight")
	if hl != null and hl.has_method("get_action_column"):
		var shared: Vector3 = hl.get_action_column()
		if shared != Vector3.ZERO:
			var sx := floori(shared.x)
			var sz := floori(shared.z)
			if not _ActionTargeting._column_in_range(player, sx, sz, range_v):
				if _terrain_editor:
					_terrain_editor.last_fail_reason = "Out of range"
				return Vector3.ZERO
			return Vector3(float(sx) + 0.5, shared.y, float(sz) + 0.5)
	return _ActionTargeting.target_column(player, range_v)


func _resolve_buildable_id() -> StringName:
	if build_variant == 1:
		return &"gate"
	if build_variant == 2:
		return &"bridge"
	if inventory and inventory.count_item("stone") > 0:
		return &"stone_wall"
	return &"wood_wall"


func _flash_build_feedback(target: Vector3, build_id: StringName) -> void:
	var vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	if vfx and vfx.has_method("show_place_flash"):
		vfx.show_place_flash(target, build_id)
	var highlight = player.get_node_or_null("TargetHighlight") if player else null
	if highlight and highlight.has_method("pulse_place_success"):
		highlight.pulse_place_success()


func _flash_dig_feedback(target: Vector3) -> void:
	var highlight = player.get_node_or_null("TargetHighlight") if player else null
	if highlight and highlight.has_method("pulse_place_success"):
		highlight.pulse_place_success()
	var vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	if vfx and vfx.has_method("show_place_flash"):
		vfx.show_place_flash(target, &"dig")
	_sfx("dig", target)


func _player_damage_mult(stat_id: StringName) -> float:
	if player == null or player.get("stat_component") == null:
		return 1.0
	if player.has_method("get_stat"):
		return player.get_stat(stat_id)
	return 1.0


func _entity_hit_damage(def: Dictionary, weapon_stat: StringName) -> float:
	var base := float(def.get("entity_damage", def.get("damage", 5.0)))
	return base * _player_damage_mult(weapon_stat)


func _crystal_hit_damage(def: Dictionary, weapon_stat: StringName = _StatIds.MELEE_DAMAGE) -> float:
	var base := float(def.get("damage", 5.0))
	return base * _player_damage_mult(weapon_stat) * _player_damage_mult(_StatIds.CRYSTAL_DAMAGE)


func _crystal_mass_damage(def: Dictionary) -> float:
	var base := float(def.get("crystal_damage", 0.2))
	return base * _player_damage_mult(_StatIds.CRYSTAL_DAMAGE)


func _try_break_crystal_mass(cell: Vector2i, def: Dictionary) -> bool:
	if crystal_manager == null or not crystal_manager.has_method("damage_crystal_at"):
		return false
	var hit: Dictionary = crystal_manager.damage_crystal_at(cell, _crystal_mass_damage(def))
	return bool(hit.get("hit", false))


func _try_plant() -> void:
	if _cooldown_timer > 0.0 or player == null or inventory == null or _terrain_editor == null:
		return
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	var forward := _attack_forward()
	var target := player.voxel_position + forward * 2.0
	var plant_id: StringName
	if build_variant == 1:
		plant_id = &"tree" if inventory.count_item("wood") >= 3 else &"fern"
	elif build_variant == 2:
		plant_id = &"wildflower"
	elif inventory.count_item("wood") >= 2:
		plant_id = &"bush"
	elif inventory.count_item("herb") >= 2:
		plant_id = &"tall_grass"
	else:
		plant_id = &"grass_tuft"
	if _terrain_editor.try_plant(target, inventory, plant_id):
		_cooldown_timer = _terrain_editor.get_plant_delay()


func begin_animation_clock(item_id: String) -> void:
	_playback = _ItemAnim.playback_for(item_id)
	_clock_damage_elapsed = -1.0
	_pending_mode = -1
	_pending_item = ""
	_pending_def = {}


func tick_animation_clock(delta: float) -> bool:
	return _tick_animation_clock(delta)


func animation_damage_elapsed() -> float:
	return _clock_damage_elapsed


func animation_impact_time() -> float:
	if _playback == null:
		return -1.0
	return float(_playback.impact_time())


func _bind_presentation() -> void:
	if _present_bound or player == null:
		return
	_present_bound = true
	_held = _HeldItemView.new()
	_held.name = "HeldItemView"
	player.add_child(_held)
	_aim = _AimIndicator.new()
	_aim.name = "AimIndicator"
	player.add_child(_aim)
	_aim.bind_player(player)


func _arm_clock(item_id: String, def: Dictionary, mode: int) -> void:
	_playback = _ItemAnim.playback_for(item_id)
	_pending_mode = mode
	_pending_item = item_id
	_pending_def = def
	_clock_damage_elapsed = -1.0
	if _held:
		_held.apply_playback(_playback)
		_face_held()
	if _playback.impact_time() <= 0.0:
		_tick_animation_clock(0.0)


func _tick_animation_clock(delta: float) -> bool:
	if _playback == null:
		return false
	var fired: bool = bool(_playback.advance(delta))
	if _held and int(_playback.kind) != _ItemAnim.Kind.NONE:
		_held.apply_playback(_playback)
	if fired:
		_clock_damage_elapsed = float(_playback.elapsed)
		if _pending_mode >= 0 and player != null:
			var mode := _pending_mode
			var item := _pending_item
			var def := _pending_def
			_pending_mode = -1
			_pending_item = ""
			_pending_def = {}
			if mode == 0:
				_do_melee_attack(item, def)
			elif mode == 1:
				_do_ranged_attack(item, def)
	if _playback != null and _playback.finished() and _pending_mode < 0:
		var done_id := str(_playback.item_id)
		_playback = null
		_shown_item = done_id
		if _held:
			_held.show_item(done_id)
	return fired


func _configured_attack_id(item_id: String, def: Dictionary) -> String:
	var kind := int(def.get("weapon_kind", ItemTypes.WeaponKind.MELEE))
	if kind == ItemTypes.WeaponKind.RANGED and item_id.find("bow") >= 0:
		return "bow_shot"
	if kind != ItemTypes.WeaponKind.MELEE or item_id.find("sword") < 0:
		return ""
	if bool(def.get("thrust", false)) or int(def.get("splash", 0)) > 0:
		return ""
	return "sword_swing"


func _tool_press_edge() -> bool:
	return Input.is_action_just_pressed("attack") \
		or Input.is_action_just_pressed("build_place") \
		or Input.is_action_just_pressed("interact")


func _offer_tool_action(action_id: String, item_id: String, def: Dictionary) -> void:
	_feel_item = item_id
	_feel_def = def.duplicate()
	var entity_hit := action_id == "multi_block_break" and _tool_press_edge()
	if not _tool_feel.accepts():
		if _tool_press_edge():
			_feel_hit_entities = entity_hit
			_tool_feel.remember(action_id)
		return
	if not _tool_feel.try_begin(self, action_id):
		_feel_hit_entities = entity_hit
		_tool_feel.remember(action_id)
		return
	_feel_hit_entities = entity_hit
	_arm_accepted_tool(action_id)


func _arm_accepted_tool(action_id: String) -> void:
	if action_id == "sword_swing" or action_id == "bow_shot":
		_cooldown_timer = float(_feel_def.get("cooldown", 0.5))
		_sync_impact_pose(_feel_item)
	elif action_id == "multi_block_break":
		_sync_impact_pose(_feel_item)


func advance_tool_feel(delta: float) -> void:
	_tool_feel.advance(self, delta)


func on_tool_buffer_open(action_id: String) -> void:
	if not _tool_feel.try_begin(self, action_id):
		_tool_feel.remember(action_id)
		return
	_arm_accepted_tool(action_id)


func resolve_tool_feel(action_id: String) -> bool:
	_feel_resolving = true
	var landed := true
	if action_id == "sword_swing":
		_do_melee_attack(_feel_item, _feel_def)
	elif action_id == "bow_shot":
		_do_ranged_attack(_feel_item, _feel_def)
	elif action_id == "multi_block_break":
		_listed_break = true
		_do_dig_attack(_feel_item, _feel_def)
	elif action_id == "building_placement":
		landed = _try_place_selected()
	_feel_resolving = false
	_feel_hit_entities = false
	_feel_target = Vector3.ZERO
	return landed


func release_tool_feel(action_id: String) -> void:
	if action_id == "sword_swing" or action_id == "bow_shot":
		_cooldown_timer = 0.0
	if action_id == "multi_block_break":
		_listed_break = false
	_feel_target = Vector3.ZERO


func _cancel_pending_strike() -> void:
	_pending_mode = -1
	_pending_item = ""
	_pending_def = {}
	_playback = null
	_shown_item = ""
	_tool_feel.abort_wind(self)


func _sync_impact_pose(item_id: String) -> void:
	if _pending_mode >= 0:
		return
	var spec: Dictionary = _ItemAnim.spec_for(item_id)
	if int(spec.get("kind", _ItemAnim.Kind.NONE)) == _ItemAnim.Kind.NONE:
		return
	# Dig, place, and herb already resolved. Play the swing from the ready pose
	# and do not restart it on every repeat tick.
	if _playback != null and str(_playback.item_id) == item_id and not _playback.finished():
		return
	_playback = _ItemAnim.playback_for(item_id)
	_clock_damage_elapsed = -1.0
	if _held:
		_held.apply_playback(_playback)
		_face_held()


func _present_held(_delta: float) -> void:
	if not _present_bound:
		return
	var id := ""
	var slot = get_active_item()
	if slot != null:
		id = str(slot.id)
	if _held:
		_face_held()
		if _playback == null and id != _shown_item:
			_shown_item = id
			_held.show_item(id)
	if _aim:
		_aim.tick(id)
	if _is_active_dig_tool() and Input.is_action_pressed("attack"):
		_crack_fill = minf(_crack_fill + _delta / TERRAIN_HOLD_REPEAT_START_SEC, 0.92)
		_preview_dig_cracks()
	elif _crack_fill > 0.0:
		_crack_fill = 0.0
		_clear_dig_cracks()


func _preview_dig_cracks() -> void:
	var target := _resolve_terrain_target(_ActionTargeting.reach())
	if target == Vector3.ZERO:
		return
	var fx := _break_fx()
	if fx and fx.has_method("set_progress"):
		fx.set_progress(_column_fx_pos(target), _crack_fill, _BlockBreakFx.tint_for_column(world, target))


func _clear_dig_cracks() -> void:
	var fx := _break_fx()
	if fx and fx.has_method("current_stage") and int(fx.current_stage()) > 0 and fx.has_method("set_progress"):
		fx.set_progress(Vector3.ZERO, 0.0)


func _column_fx_pos(col: Vector3) -> Vector3:
	var layer: float = _WorldSettings.get_active().layer_height()
	return _WorldVisualCoords.column_to_world_pos(
		floorf(col.x) + 0.5,
		col.y + layer * 0.45,
		floorf(col.z) + 0.5
	)


func _place_anim_id() -> String:
	var slot = get_active_item()
	if slot != null:
		return str(slot.id)
	return "wood"


func _note_attack(world_pos: Vector3, result: int) -> void:
	var vfx := _feedback()
	if vfx and vfx.has_method("show_attack_feedback"):
		vfx.show_attack_feedback(world_pos, result)


func _notify_block_break(target: Vector3) -> void:
	_crack_fill = 0.0
	var fx := _break_fx()
	if fx and fx.has_method("notify_break"):
		fx.notify_break(_column_fx_pos(target), _BlockBreakFx.tint_for_column(world, target))


func _notify_scaled_break(cells: Array, fallback: Vector3) -> void:
	_crack_fill = 0.0
	var fx := _break_fx()
	var tint := _BlockBreakFx.tint_for_column(world, fallback)
	var positions: Array[Vector3] = []
	for raw in cells:
		if raw is Vector3i:
			positions.append(_cell_fx_pos(raw))
	if fx and fx.has_method("notify_scaled_breaks") and not positions.is_empty():
		fx.notify_scaled_breaks(positions, tint)
		return
	_notify_block_break(fallback)


func _cell_fx_pos(cell: Vector3i) -> Vector3:
	var layer: float = _WorldSettings.get_active().layer_height()
	return _WorldVisualCoords.column_to_world_pos(
		float(cell.x) + 0.5,
		float(cell.y) * layer + layer * 0.45,
		float(cell.z) + 0.5
	)


func _notify_block_place(target: Vector3) -> void:
	var fx := _break_fx()
	if fx and fx.has_method("notify_place"):
		fx.notify_place(_column_fx_pos(target), Color(0.45, 0.82, 0.42))


func _break_fx() -> Node:
	var vfx := _feedback()
	if vfx and vfx.has_method("block_break_fx"):
		return vfx.block_break_fx()
	return null


func _feedback() -> Node:
	if is_instance_valid(_vfx):
		return _vfx
	if not is_inside_tree():
		return null
	_vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	return _vfx


func _sfx(id: String, at: Variant = null) -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/AudioManager")
	if _audio == null or not _audio.has_method("play_sfx") and not _audio.has_method("play_ui"):
		return
	if id.begins_with("ui_") and _audio.has_method("play_ui"):
		_audio.play_ui(id)
		return
	if _audio.has_method("play_sfx"):
		if at is Vector3:
			_audio.play_sfx(id, at)
		else:
			_audio.play_sfx(id)
