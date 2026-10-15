class_name CrystalPulseSkill
extends RefCounted

const _Hits = preload("res://systems/combat_hit_resolver.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const SKILL_ID := &"crystal_pulse"
const DAMAGE := 16.0
const RADIUS := 4.0
const DURATION := 4.0
const SLOW := 0.4
const COOLDOWN := 6.0

static var _zones: Array = []


static func arm(center: Vector2i) -> void:
	for zone_v in _zones:
		var zone: Dictionary = zone_v
		if zone["center"] == center:
			zone["left"] = DURATION
			return
	_zones.append({"center": center, "left": DURATION})


static func advance(delta: float) -> void:
	if delta <= 0.0 or _zones.is_empty():
		return
	if _GameplayInput.blocks_actions():
		return
	var kept: Array = []
	for zone_v in _zones:
		var zone: Dictionary = zone_v
		var left: float = float(zone["left"]) - delta
		if left > 0.0:
			zone["left"] = left
			kept.append(zone)
	_zones = kept


static func clear() -> void:
	_zones.clear()


static func active() -> bool:
	return not _zones.is_empty()


static func spread_scale(from_pos: Vector2i, to_pos: Vector2i) -> float:
	return minf(_scale_at(from_pos), _scale_at(to_pos))


static func covers(col: Vector2i, center: Vector2i) -> bool:
	var dx := float(col.x - center.x)
	var dy := float(col.y - center.y)
	return dx * dx + dy * dy <= RADIUS * RADIUS


static func _scale_at(pos: Vector2i) -> float:
	var scale := 1.0
	for zone_v in _zones:
		var zone: Dictionary = zone_v
		if covers(pos, zone["center"]):
			scale = minf(scale, SLOW)
	return scale


static func column_of(node: Node, ws) -> Vector2i:
	var pos := Vector3.ZERO
	if node.has_method("get_combat_center"):
		pos = node.get_combat_center()
	elif node is Node3D:
		var body := node as Node3D
		pos = body.global_position if body.is_inside_tree() else body.position
	else:
		return Vector2i(999999, 999999)
	return Vector2i(floori(ws.world_to_column(pos.x)), floori(ws.world_to_column(pos.z)))


static func strike(nodes: Array, center: Vector2i, ws, caster: Node = null) -> int:
	var seen := {}
	var hits := 0
	for raw in nodes:
		if not raw is Node:
			continue
		var node: Node = raw
		if not is_instance_valid(node):
			continue
		var id := node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		if caster != null and node == caster:
			continue
		if node.is_in_group("player"):
			continue
		if not node.is_in_group("crystal_enemy"):
			continue
		if not node.has_method("take_damage"):
			continue
		if "health" in node and float(node.health) <= 0.0:
			continue
		if not covers(column_of(node, ws), center):
			continue
		_Hits.apply_damage(node, DAMAGE, SKILL_ID, "Crystal Pulse")
		hits += 1
	return hits
