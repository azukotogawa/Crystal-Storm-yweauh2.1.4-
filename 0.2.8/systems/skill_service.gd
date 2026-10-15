class_name SkillService
extends Node

const _Progression = preload("res://systems/progression_service.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _Dash = preload("res://player/dash_skill.gd")
const _Pulse = preload("res://player/crystal_pulse_skill.gd")

const SKILLS_ENABLED := true
const ACTIVE_SLOTS := 3
const HOTKEY_ACTIONS: Array[String] = ["skill_1", "skill_2", "skill_3"]
const DEFAULT_COOLDOWN := 1.0
const KIND_ACTIVE := &"active"
const KIND_PASSIVE := &"passive"
const TREE_FIGHTER := &"fighter"
const TREE_MINER := &"miner"
const TREE_BUILDER := &"builder"

const CATALOG := {
	&"dash": {"kind": KIND_ACTIVE, "cost": 1, "cooldown": _Dash.COOLDOWN, "tree": TREE_FIGHTER},
	&"ground_slam": {"kind": KIND_ACTIVE, "cost": 1, "cooldown": DEFAULT_COOLDOWN, "tree": TREE_MINER},
	&"crystal_pulse": {"kind": KIND_ACTIVE, "cost": 1, "cooldown": _Pulse.COOLDOWN, "tree": TREE_FIGHTER},
	&"quick_wall": {"kind": KIND_ACTIVE, "cost": 1, "cooldown": DEFAULT_COOLDOWN, "tree": TREE_BUILDER},
	&"fighter_passive": {"kind": KIND_PASSIVE, "cost": 1, "cooldown": 0.0, "tree": TREE_FIGHTER},
	&"miner_passive": {"kind": KIND_PASSIVE, "cost": 1, "cooldown": 0.0, "tree": TREE_MINER},
	&"builder_passive": {"kind": KIND_PASSIVE, "cost": 1, "cooldown": 0.0, "tree": TREE_BUILDER},
}

signal skill_unlocked(skill_id: StringName)
signal skill_equipped(slot: int, skill_id: StringName)
signal skill_activated(slot: int, skill_id: StringName)

static var _active = null

var _unlocked: Dictionary = {}
var _slots: Array[StringName] = [&"", &"", &""]
var _cooldown: Array[float] = [0.0, 0.0, 0.0]
var _hotkey_down: Array[bool] = [false, false, false]


static func get_active():
	return _active


func _enter_tree() -> void:
	_active = self
	add_to_group("skill_service")


func _exit_tree() -> void:
	if _active == self:
		_active = null


func _process(delta: float) -> void:
	if not SKILLS_ENABLED:
		return
	if _GameplayInput.blocks_actions():
		_latch_hotkeys()
		return
	_tick_cooldowns(delta)
	_poll_hotkeys()


func progression():
	if is_inside_tree():
		var node = get_tree().get_first_node_in_group("progression_service")
		if node != null:
			return node
	return _Progression.get_active()


func skill_points() -> int:
	var svc = progression()
	if svc == null:
		return 0
	return int(svc.skill_points)


func def_for(skill_id: StringName) -> Dictionary:
	var spec = CATALOG.get(skill_id, {})
	if spec is Dictionary:
		return spec
	return {}


func is_active(skill_id: StringName) -> bool:
	return def_for(skill_id).get("kind", &"") == KIND_ACTIVE


func is_unlocked(skill_id: StringName) -> bool:
	return bool(_unlocked.get(skill_id, false))


func unlock(skill_id: StringName) -> bool:
	if not SKILLS_ENABLED:
		return false
	if is_unlocked(skill_id):
		return false
	var spec := def_for(skill_id)
	if spec.is_empty():
		return false
	var svc = progression()
	if svc == null or not svc.has_method("spend_skill_points"):
		return false
	var cost := maxi(int(spec.get("cost", 1)), 0)
	if not svc.spend_skill_points(cost):
		return false
	_unlocked[skill_id] = true
	skill_unlocked.emit(skill_id)
	return true


func equip(slot: int, skill_id: StringName) -> bool:
	if not SKILLS_ENABLED:
		return false
	if not _slot_ok(slot):
		return false
	if not is_active(skill_id) or not is_unlocked(skill_id):
		return false
	if _held_elsewhere(slot, skill_id):
		return false
	_slots[slot] = skill_id
	_cooldown[slot] = 0.0
	skill_equipped.emit(slot, skill_id)
	return true


func clear_slot(slot: int) -> void:
	if not _slot_ok(slot):
		return
	_slots[slot] = &""
	_cooldown[slot] = 0.0
	skill_equipped.emit(slot, &"")


func slot_skill(slot: int) -> StringName:
	if not _slot_ok(slot):
		return &""
	return _slots[slot]


func cooldown_left(slot: int) -> float:
	if not _slot_ok(slot):
		return 0.0
	return _cooldown[slot]


func release_cooldown(slot: int) -> void:
	if not _slot_ok(slot):
		return
	_cooldown[slot] = 0.0


func try_activate(slot: int) -> bool:
	if not SKILLS_ENABLED:
		return false
	if not _slot_ok(slot):
		return false
	var skill_id := _slots[slot]
	if skill_id == &"" or _cooldown[slot] > 0.0:
		return false
	var cd := float(def_for(skill_id).get("cooldown", DEFAULT_COOLDOWN))
	_cooldown[slot] = maxf(cd, 0.0)
	skill_activated.emit(slot, skill_id)
	return true


func export_state() -> Dictionary:
	var unlocked: Array[String] = []
	for id in _unlocked.keys():
		unlocked.append(String(id))
	unlocked.sort()
	var slots: Array[String] = []
	var cds: Array[float] = []
	for i in ACTIVE_SLOTS:
		slots.append(String(_slots[i]))
		cds.append(_cooldown[i])
	return {"unlocked": unlocked, "slots": slots, "cooldowns": cds}


func import_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	_unlocked.clear()
	for id in data.get("unlocked", []):
		var key := StringName(String(id))
		if CATALOG.has(key):
			_unlocked[key] = true
	for i in ACTIVE_SLOTS:
		_slots[i] = &""
		_cooldown[i] = 0.0
	var slots: Array = data.get("slots", [])
	var cds: Array = data.get("cooldowns", [])
	for i in mini(ACTIVE_SLOTS, slots.size()):
		var key := StringName(String(slots[i]))
		if key != &"" and is_unlocked(key) and is_active(key) and not _held_elsewhere(i, key):
			_slots[i] = key
			if i < cds.size():
				_cooldown[i] = maxf(float(cds[i]), 0.0)


func tree_ids(tree: StringName) -> Array:
	var ids: Array = []
	for skill_id in CATALOG.keys():
		if def_for(skill_id).get("tree", &"") == tree:
			ids.append(skill_id)
	ids.sort()
	return ids


func _tick_cooldowns(delta: float) -> void:
	if delta <= 0.0:
		return
	for i in ACTIVE_SLOTS:
		if _cooldown[i] > 0.0:
			_cooldown[i] = maxf(_cooldown[i] - delta, 0.0)


func _hotkey_down_now(slot: int) -> bool:
	var action := HOTKEY_ACTIONS[slot]
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _latch_hotkeys() -> void:
	for i in ACTIVE_SLOTS:
		_hotkey_down[i] = _hotkey_down_now(i)


func _poll_hotkeys() -> void:
	for i in ACTIVE_SLOTS:
		var down := _hotkey_down_now(i)
		if down and not _hotkey_down[i]:
			try_activate(i)
		_hotkey_down[i] = down


func _slot_ok(slot: int) -> bool:
	return slot >= 0 and slot < ACTIVE_SLOTS


func _held_elsewhere(slot: int, skill_id: StringName) -> bool:
	for i in ACTIVE_SLOTS:
		if i != slot and _slots[i] == skill_id:
			return true
	return false
