class_name StructureIntegrity
extends RefCounted

const _Features = preload("res://world/feature_registry.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _WorldState = preload("res://world/world_state.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Passives = preload("res://player/skill_passives.gd")

const HP_PER_CELL := 8
const CRYSTAL_DAMAGE := 2.0

static var _next_id: int = 1
static var _live: int = 0
static var _anchors: Dictionary = {}
static var _erode_bank: Dictionary = {}


static func forget_session() -> void:
	_live = -1
	_next_id = 1
	_anchors.clear()
	_erode_bank.clear()


static func reset() -> void:
	_live = 0
	_next_id = 1
	_anchors.clear()
	_erode_bank.clear()


static func live_count() -> int:
	if _live >= 0:
		return _live
	var seen := {}
	var max_id := 0
	_anchors.clear()
	var cells: Dictionary = _WorldState.get_active().feature_cells
	for key_v in cells.keys():
		var feat: Dictionary = cells[key_v]
		if not feat.has("structure_id"):
			continue
		var sid := int(feat.get("structure_id", 0))
		seen[sid] = true
		max_id = maxi(max_id, sid)
		var col: Vector2i = key_v
		var ax := int(feat.get("structure_anchor_x", col.x))
		var az := int(feat.get("structure_anchor_z", col.y))
		if col.x == ax and col.y == az:
			_anchors[sid] = col
	for key_v in cells.keys():
		var feat: Dictionary = cells[key_v]
		if not feat.has("structure_id"):
			continue
		var sid := int(feat.get("structure_id", 0))
		if not _anchors.has(sid):
			_anchors[sid] = key_v
	_live = seen.size()
	_next_id = max_id + 1
	return _live


static func bind(blueprint_id: StringName, anchor: Vector2i, cells: Array) -> Dictionary:
	if not _Blueprints.LARGE_STRUCTURES:
		return {}
	var packed: Array = []
	var columns := {}
	for item in cells:
		if not item is Dictionary or not item.get("at") is Vector3i:
			continue
		var at: Vector3i = item["at"]
		packed.append({
			"x": at.x,
			"y": at.y,
			"z": at.z,
			"role": str(item.get("role", "wall")),
		})
		columns[Vector2i(at.x, at.z)] = true
	if packed.is_empty():
		return {}
	if _live < 0:
		live_count()
	var sid := _next_id
	_next_id += 1
	var anchor_col := anchor
	if not columns.has(anchor_col):
		anchor_col = columns.keys()[0]
	var blockers := {}
	for item in cells:
		if not item is Dictionary or not item.get("at") is Vector3i:
			continue
		var at: Vector3i = item["at"]
		var col := Vector2i(at.x, at.z)
		var solid := str(item.get("role", "wall")) != "passage"
		blockers[col] = bool(blockers.get(col, false)) or solid
	var max_hp := packed.size() * (HP_PER_CELL + _Passives.structure_cell_bonus())
	var ws = _WorldState.get_active()
	ws.begin_batch()
	for key_v in columns.keys():
		var col: Vector2i = key_v
		_stamp(col, sid, max_hp, max_hp, String(blueprint_id), anchor_col, packed, col == anchor_col, bool(blockers.get(col, true)))
	ws.bump(_WorldState.DOMAIN_FEATURE)
	ws.end_batch()
	_anchors[sid] = anchor_col
	_live += 1
	return record_at(anchor_col)


static func record_at(column: Vector2i) -> Dictionary:
	var feat = _Features.feature_at(column.x, column.y)
	if feat == null or not feat.has("structure_id"):
		return {}
	var ax := int(feat.get("structure_anchor_x", column.x))
	var az := int(feat.get("structure_anchor_z", column.y))
	if ax == column.x and az == column.y:
		return feat
	var anchor = _Features.feature_at(ax, az)
	if anchor == null or int(anchor.get("structure_id", -1)) != int(feat.get("structure_id")):
		return feat
	return anchor


static func apply_damage(column: Vector2i, amount: float, source: StringName = &"", editor: Object = null) -> Dictionary:
	var rec := record_at(column)
	if rec.is_empty():
		return {"hit": false, "destroyed": false}
	var dealt := int(ceil(amount))
	if dealt <= 0:
		return {"hit": false, "destroyed": false, "hp": int(rec.get("structure_hp", 0)), "max_hp": int(rec.get("structure_max", 0))}
	var hp := maxi(int(rec.get("structure_hp", 0)) - dealt, 0)
	var max_hp := int(rec.get("structure_max", 0))
	var sid := int(rec.get("structure_id", 0))
	if hp > 0:
		_write_hp(rec, hp)
		return {"hit": true, "destroyed": false, "hp": hp, "max_hp": max_hp, "source": String(source)}
	var removed: Dictionary = _Edits.remove_structure_cells(rec.get("structure_cells", []), editor)
	_anchors.erase(sid)
	_erode_bank.erase(sid)
	if _live > 0:
		_live -= 1
	else:
		_live = -1
	return {
		"hit": true,
		"destroyed": true,
		"hp": 0,
		"max_hp": max_hp,
		"source": String(source),
		"removed": int(removed.get("removed_count", 0)),
		"edits": int(removed.get("edits", 0)),
	}


static func damage_around(cell: Vector2i, amount: float, editor: Object = null) -> Dictionary:
	var last := {"hit": false, "destroyed": false}
	var seen := {}
	for dir in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var rec := record_at(cell + dir)
		if rec.is_empty():
			continue
		var sid := int(rec.get("structure_id", 0))
		if seen.has(sid):
			continue
		seen[sid] = true
		last = apply_damage(cell + dir, amount, &"enemy", editor)
	return last


static func erode_pressed(fluid, min_depth: float, amount: float, editor: Object = null) -> Array:
	if live_count() <= 0 or amount <= 0.0 or fluid == null:
		return []
	var hits: Array = []
	var ids: Array = _anchors.keys()
	for sid_v in ids:
		var sid := int(sid_v)
		var anchor: Vector2i = _anchors[sid]
		var rec := record_at(anchor)
		if rec.is_empty() or int(rec.get("structure_id", -1)) != sid:
			_anchors.erase(sid)
			_erode_bank.erase(sid)
			continue
		if not _pressed_by_crystal(rec, fluid, min_depth):
			continue
		var bank := float(_erode_bank.get(sid, 0.0)) + amount
		var whole := int(floor(bank))
		_erode_bank[sid] = bank - float(whole)
		if whole <= 0:
			continue
		var hit: Dictionary = apply_damage(anchor, float(whole), &"crystal", editor)
		hits.append(hit)
		if bool(hit.get("destroyed", false)):
			_erode_bank.erase(sid)
	return hits


static func erode_columns(columns: Array, editor: Object = null) -> Array:
	if live_count() <= 0:
		return []
	var hits: Array = []
	var seen := {}
	for raw in columns:
		if not raw is Vector2i:
			continue
		var col: Vector2i = raw
		var rec := record_at(col)
		if rec.is_empty():
			continue
		var sid := int(rec.get("structure_id", 0))
		if seen.has(sid):
			continue
		seen[sid] = true
		hits.append(apply_damage(col, CRYSTAL_DAMAGE, &"crystal", editor))
	return hits


static func chip_enemy(cell: Vector2i, amount: float, did_attack: bool, brain, host = null) -> Dictionary:
	if not _Blueprints.LARGE_STRUCTURES or amount <= 0.0 or live_count() <= 0:
		return {"hit": false}
	if record_at(cell).is_empty() and record_at(cell + Vector2i.RIGHT).is_empty() and record_at(cell + Vector2i.LEFT).is_empty() and record_at(cell + Vector2i.UP).is_empty() and record_at(cell + Vector2i.DOWN).is_empty():
		return {"hit": false}
	var editor := _editor_of(host)
	if did_attack:
		return damage_around(cell, amount, editor)
	if brain != null and "attack_timer" in brain and float(brain.attack_timer) > 0.0:
		return {"hit": false}
	var hit := damage_around(cell, amount, editor)
	if bool(hit.get("hit", false)) and brain != null and "attack_timer" in brain and brain.config != null:
		brain.attack_timer = float(brain.config.attack_cooldown)
	return hit


static func repair_at(column: Vector2i, inventory) -> Dictionary:
	var rec := record_at(column)
	if rec.is_empty():
		return {"repaired": false}
	var hp := int(rec.get("structure_hp", 0))
	var max_hp := int(rec.get("structure_max", 0))
	if hp >= max_hp:
		return {"repaired": false, "hp": hp, "max_hp": max_hp}
	var need := int(ceil(float(max_hp - hp) / float(HP_PER_CELL)))
	if inventory == null or not inventory.has_method("count_item") or not inventory.has_method("consume_item"):
		return {"repaired": false, "need": need, "hp": hp, "max_hp": max_hp}
	var spend := mini(int(inventory.count_item("stone")), need)
	if spend <= 0 or not inventory.consume_item("stone", spend):
		return {"repaired": false, "need": need, "hp": hp, "max_hp": max_hp}
	var healed := mini(max_hp, hp + spend * HP_PER_CELL)
	_write_hp(rec, healed)
	return {"repaired": true, "hp": healed, "max_hp": max_hp, "spent": spend}


static func _pressed_by_crystal(rec: Dictionary, fluid, min_depth: float) -> bool:
	var seen := {}
	var listed = rec.get("structure_cells", [])
	if listed is Array and not listed.is_empty():
		for raw in listed:
			if not raw is Dictionary:
				continue
			if str(raw.get("role", "wall")) == "passage":
				continue
			var col := Vector2i(int(raw.get("x", 0)), int(raw.get("z", 0)))
			if seen.has(col):
				continue
			seen[col] = true
			if _depth_presses(fluid, col, min_depth):
				return true
		return false
	var anchor := Vector2i(int(rec.get("structure_anchor_x", 0)), int(rec.get("structure_anchor_z", 0)))
	return _depth_presses(fluid, anchor, min_depth)


static func _depth_presses(fluid, col: Vector2i, min_depth: float) -> bool:
	if float(fluid.depth.get(col, 0.0)) >= min_depth:
		return true
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if float(fluid.depth.get(col + dir, 0.0)) >= min_depth:
			return true
	return false


static func _stamp(col: Vector2i, sid: int, hp: int, max_hp: int, blueprint: String, anchor: Vector2i, cells: Array, keep_cells: bool, blocks_spread: bool = true) -> void:
	var feat = _Features.feature_at(col.x, col.y)
	if feat == null:
		_Features.register_feature(col.x, col.y, 0, {})
		feat = _Features.feature_at(col.x, col.y)
	if feat == null:
		return
	feat["structure_id"] = sid
	feat["structure_hp"] = hp
	feat["structure_max"] = max_hp
	feat["structure_blueprint"] = blueprint
	feat["structure_anchor_x"] = anchor.x
	feat["structure_anchor_z"] = anchor.y
	feat["structure_blocks_spread"] = blocks_spread
	if keep_cells:
		feat["structure_cells"] = cells.duplicate(true)
	else:
		feat.erase("structure_cells")


static func _write_hp(rec: Dictionary, hp: int) -> void:
	var seen := {}
	var ws = _WorldState.get_active()
	ws.begin_batch()
	for raw in rec.get("structure_cells", []):
		if not raw is Dictionary:
			continue
		var col := Vector2i(int(raw.get("x", 0)), int(raw.get("z", 0)))
		if seen.has(col):
			continue
		seen[col] = true
		var feat = _Features.feature_at(col.x, col.y)
		if feat == null:
			continue
		feat["structure_hp"] = hp
	ws.bump(_WorldState.DOMAIN_FEATURE)
	ws.end_batch()


static func _editor_of(host) -> Object:
	if host == null or not host.has_method("is_inside_tree") or not host.is_inside_tree():
		return null
	return host.get_tree().get_first_node_in_group("terrain_editor")
