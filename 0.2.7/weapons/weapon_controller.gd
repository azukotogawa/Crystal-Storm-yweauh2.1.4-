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
var _active_hotbar_index: int = 0
var _terrain_editor: TerrainEditor
var _terrain_bind_attempts: int = 0
var _combat_def: _CombatDef
## Rate-limit fail toasts so hold-to-dig doesn't spam.
var _fail_toast_cd: float = 0.0
var _last_fail_toast: String = ""
## Hold-to-repeat: first press is one edit; continuous reshape only after a short hold.
## Prevents a single click (often >30ms) from stacking two layers without lengthening place delay.
var _dig_hold_sec: float = 0.0
var _audio: Node
var _build_hold_sec: float = 0.0
var _brush_left_held: bool = false
var _brush_right_held: bool = false
var place_index: int = 0
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
## Visual only. Resets when a layer breaks so the overlay refills without changing dig cadence.
var _crack_fill: float = 0.0


func _ready() -> void:
	player = get_parent() as Player
	if player:
		inventory = player.inventory
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	world = get_tree().get_first_node_in_group("world")
	_combat_def = _resolve_combat_def()
	# After TargetHighlight so shared aim column is current this frame.
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
		if profiler and profiler.has_method("end"):
			profiler.end("weapon_controller")
		return
	_poll_dig_brush_keys()

	# LMB subtracts structures/terrain for dig tools and place-catalog terrain edits.
	# Combat weapons (sword/bow/spear/hammer/sling/bomb): LMB is attack only — never dig or remove.
	var dig_held := _is_active_dig_tool() and Input.is_action_pressed("attack")
	if Input.is_action_just_pressed("attack") and _cooldown_timer <= 0.0:
		if not _is_active_combat_weapon():
			if _try_remove_at_cursor():
				_dig_hold_sec = 0.0
				if profiler and profiler.has_method("end"):
					profiler.end("weapon_controller")
				return
			if _PlaceableCatalog.is_terrain_edit(get_place_id()) and not _is_active_dig_tool():
				_try_dig_tool_or_fill_remove()
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
	if build_held:
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
	if Input.is_action_just_pressed("channel_water"):
		_try_channel_water()

	if Input.is_action_just_pressed("place_cycle"):
		place_index = (place_index + 1) % _PlaceableCatalog.count()
	for i in HOTBAR_INPUTS.size():
		if Input.is_action_just_pressed(HOTBAR_INPUTS[i]):
			_cancel_pending_strike()
			_active_hotbar_index = i
			_shown_item = ""
			if inventory:
				inventory.hotbar_changed.emit(i)
	_present_held(delta)
	if profiler and profiler.has_method("end"):
		profiler.end("weapon_controller")


func _is_build_material() -> bool:
	var slot = get_active_item()
	if slot == null:
		return false
	return str(slot.id) in ["stone", "wood"]


func _try_remove_at_cursor() -> bool:
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null or inventory == null:
		return false
	var target := _resolve_terrain_target(_ActionTargeting.INTERACTION_RANGE)
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
	var def := ItemTypes.get_def(str(slot.id))
	if def.is_empty():
		return false
	return int(def.get("category", -1)) == ItemTypes.Category.TOOL \
		and int(def.get("weapon_kind", -1)) == ItemTypes.WeaponKind.DIG


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
	_do_dig_attack(item_id, def)


## Existing consumable hook: herb restores health (no new survival meters).
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

	var kind := int(def.get("weapon_kind", ItemTypes.WeaponKind.MELEE))
	# Dig uses its own snappy delay — never the 0.55s weapon cooldown.
	if kind == ItemTypes.WeaponKind.DIG:
		_do_dig_attack(item_id, def)
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
	# Same column the attack highlight uses (forward fallback when the mouse is off-screen).
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
	# Highlight/column aim can face a different cell than the camera-forward column
	# the sword highlight treats as the swing. Retry that facing when the arc is empty.
	var cam_fwd := _attack_forward()
	if targets.is_empty() and cam_fwd.length_squared() > 0.0001:
		targets = _query_melee_facing(origin, cam_fwd, range_w)
	if targets.is_empty() and player and player.is_inside_tree():
		for node in player.get_tree().get_nodes_in_group("crystal_enemy"):
			if not is_instance_valid(node) or not (node is Node3D):
				continue
			if node.has_method("is_combat_alive") and not node.is_combat_alive():
				continue
			var c: Vector3 = node.global_position
			var d := Vector2(c.x - origin.x, c.z - origin.z).length()
			if d <= range_w + 1.25:
				targets.append(node)
				break
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
	# Adjacent hostiles: if the 70° arc missed, retry a half-circle
	# at the same range so a mite on-camera next to the player is hittable.
	if targets.is_empty():
		targets = _CombatHitResolver.query_melee(
			self,
			origin,
			forward,
			range_w,
			_combat_def,
			180.0
		)
	return targets


func _do_ranged_attack(item_id: String, def: Dictionary) -> void:
	var origin := _attack_origin(0.6)
	var forward := _attack_forward()
	var range_v: float = float(def.get("range", 12.0))
	# Aim point stays in world space (column range × voxel scale) for the swing marker.
	var hit_pos := origin + forward * _range_world(range_v)
	if not _fire_projectile(item_id, def, origin, forward, false):
		_cooldown_timer = 0.25
		_note_attack(origin, _HitMarkers.Result.BLOCKED)
		return
	_sfx("fire_sling" if item_id == "sling" else "fire_bow", origin)
	attacked.emit(item_id, hit_pos)


## Line thrust. Hits the first `pierce` bodies on the aim line and can miss the side.
func _do_thrust_attack(item_id: String, def: Dictionary) -> void:
	var range_v: float = float(def.get("range", 3.0))
	var origin := _attack_origin(0.5)
	_sfx("swing_spear", origin)
	var forward := _attack_forward()
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
	var forward := _attack_forward()
	var cell := _crystal_target_cell(range_v)
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
	var forward := _attack_forward()
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
	var ok := _Projectile.launch(self, {
		"origin": origin,
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
	_sync_impact_pose(item_id)
	_sfx("swing_pick", _attack_origin(0.45) if player else null)
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		push_warning("WeaponController: terrain_editor not found for dig")
		return
	var range_v: float = _ActionTargeting.INTERACTION_RANGE
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL):
		_try_channel_water_at_target(range_v)
		return
	var forward := _attack_forward()
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
	# LMB subtracts: player-built first, then terrain. RMB places.
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
	if _terrain_editor.has_method("try_dig_brush") and _terrain_editor.try_dig_brush(target, dig_brush_radius(), player):
		# Snappy dig cadence only — ignore weapon table cooldown.
		_cooldown_timer = _terrain_editor.get_dig_delay(target)
		_flash_dig_feedback(target)
		_notify_block_break(target)
	else:
		_notify_terrain_fail()
		# Brief retry so hold-dig recovers quickly after a miss.
		_cooldown_timer = 0.04

	# Light combat on dig is intentional, but only on a fresh press (not every hold tick).
	if Input.is_action_just_pressed("attack"):
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


## Pick footprint. Combat weapons never reach this. Default tool radius is 1.
func dig_brush_radius() -> int:
	if not _is_active_dig_tool():
		return _LivingForce.BRUSH_RADIUS_DEFAULT
	var slot = get_active_item()
	if slot == null:
		return _LivingForce.BRUSH_RADIUS_DEFAULT
	return _LivingForce.radius_for_item(str(slot.id))


func _poll_dig_brush_keys() -> void:
	if not _is_active_dig_tool():
		_brush_left_held = false
		_brush_right_held = false
		return
	var left := Input.is_physical_key_pressed(KEY_BRACKETLEFT)
	var right := Input.is_physical_key_pressed(KEY_BRACKETRIGHT)
	var slot = get_active_item()
	var item_id := str(slot.id) if slot != null else "stone_pick"
	if left and not _brush_left_held:
		_LivingForce.adjust_session_bias(-1, item_id)
		_toast("Dig brush %d" % dig_brush_radius())
	if right and not _brush_right_held:
		_LivingForce.adjust_session_bias(1, item_id)
		_toast("Dig brush %d" % dig_brush_radius())
	_brush_left_held = left
	_brush_right_held = right


func get_place_id() -> String:
	return _PlaceableCatalog.id_at(place_index)


func get_place_label() -> String:
	return _PlaceableCatalog.display_name(get_place_id())


func _try_dig_tool_or_fill_remove() -> void:
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		return
	var target := _resolve_terrain_target(_ActionTargeting.INTERACTION_RANGE)
	if target == Vector3.ZERO:
		_notify_terrain_fail()
		_cooldown_timer = 0.04
		return
	if _terrain_editor.try_dig(target):
		_cooldown_timer = _terrain_editor.get_dig_delay(target)
		_flash_dig_feedback(target)
		_notify_block_break(target)
	else:
		_notify_terrain_fail()
		_cooldown_timer = 0.04


func _try_place_selected() -> void:
	if _cooldown_timer > 0.0 or player == null:
		return
	if inventory == null and player:
		inventory = player.inventory
	if _terrain_editor == null:
		_bind_terrain_editor()
	if _terrain_editor == null:
		return
	var game_manager := get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	var target := _resolve_terrain_target(_ActionTargeting.INTERACTION_RANGE)
	if target == Vector3.ZERO:
		_notify_terrain_fail()
		_cooldown_timer = 0.035
		return
	var place_id: String = get_place_id()
	var ok := false
	match place_id:
		"fill":
			ok = _terrain_editor.try_fill(target, inventory)
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
		structure_built.emit(StringName(place_id), target)
		_flash_build_feedback(target, StringName(place_id))
		_sync_impact_pose(_place_anim_id())
		_notify_block_place(target)
		_sfx("build_place", target)
	else:
		_notify_terrain_fail()
		_cooldown_timer = 0.035


func _try_build_wall() -> void:
	_try_place_selected()


## Dig/build ALWAYS use the highlighted cursor cell — never a facing fallback mismatch.
func _resolve_terrain_target(range_v: float) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var hl = player.get_node_or_null("TargetHighlight")
	if hl != null and hl.has_method("get_action_column"):
		var shared: Vector3 = hl.get_action_column()
		if shared != Vector3.ZERO:
			var sx := floori(shared.x)
			var sz := floori(shared.z)
			# Only act on the highlighted cell; out-of-range is a failed action (toast), not a different dig.
			if not _ActionTargeting._column_in_range(player, sx, sz, range_v):
				if _terrain_editor:
					_terrain_editor.last_fail_reason = "Out of range"
				return Vector3.ZERO
			return Vector3(float(sx) + 0.5, shared.y, float(sz) + 0.5)
	# No highlight (headless / boot): mouse then facing.
	return _ActionTargeting.target_column(player, range_v)


func _resolve_buildable_id() -> StringName:
	# SHIFT = gate (walk-through baffle), CTRL = bridge (span digs), else wall.
	if Input.is_key_pressed(KEY_SHIFT):
		return &"gate"
	if Input.is_key_pressed(KEY_CTRL):
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
	# Lightweight temporary visual — reuses place flash tinted as dig dust.
	var vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	if vfx and vfx.has_method("show_place_flash"):
		vfx.show_place_flash(target, &"dig")
	_sfx("dig", target)


func _player_damage_mult(stat_id: StringName) -> float:
	# A player whose stat sheet is not ready yet has no multipliers. Item damage stands.
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


## Depth removed from the crystal mass. Pick is strong; sword and bow are weak.
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
	_try_channel_water_at_target(_ActionTargeting.INTERACTION_RANGE)


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
	if _terrain_editor.try_channel_water(target, inventory if inventory else null, mode, forward):
		_cooldown_timer = maxf(_cooldown_timer, _terrain_editor.get_channel_delay(target))


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
		if player:
			_held.face(_attack_forward())
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


func _cancel_pending_strike() -> void:
	if _pending_mode < 0:
		return
	_pending_mode = -1
	_pending_item = ""
	_pending_def = {}
	_playback = null
	_shown_item = ""


func _sync_impact_pose(item_id: String) -> void:
	if _pending_mode >= 0:
		return
	var spec: Dictionary = _ItemAnim.spec_for(item_id)
	if int(spec.get("kind", _ItemAnim.Kind.NONE)) == _ItemAnim.Kind.NONE:
		return
	_playback = _ItemAnim.playback_for(item_id)
	_playback.snap_to_impact()
	_clock_damage_elapsed = float(_playback.elapsed)
	if _held:
		_held.apply_playback(_playback)
		if player:
			_held.face(_attack_forward())


func _present_held(_delta: float) -> void:
	if not _present_bound:
		return
	var id := ""
	var slot = get_active_item()
	if slot != null:
		id = str(slot.id)
	if _held:
		if player:
			_held.face(_attack_forward())
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
	var target := _resolve_terrain_target(_ActionTargeting.INTERACTION_RANGE)
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
