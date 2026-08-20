class_name CombatHitResolver
extends RefCounted

const _CombatDef = preload("res://config/combat_def.gd")
const _SpatialQueryLayer = preload("res://systems/spatial_query_layer.gd")
const _SpatialQueryService = preload("res://systems/spatial_query_service.gd")

class HitCandidate:
	var node: Node
	var center: Vector3
	var radius: float
	var distance: float
	var alignment: float


static func query_melee(
	scene_root: Node,
	origin: Vector3,
	forward: Vector3,
	range_v: float,
	combat_def: _CombatDef = null,
	arc_degrees: float = -1.0
) -> Array[Node]:
	var cfg: _CombatDef = combat_def if combat_def else _CombatDef.create_default()
	var arc: float = arc_degrees if arc_degrees > 0.0 else cfg.melee_arc_degrees
	var half_arc := deg_to_rad(arc * 0.5)
	var fwd_xz := Vector3(forward.x, 0.0, forward.z).normalized()
	if fwd_xz.length_squared() < 0.0001:
		return []

	var candidates: Array[HitCandidate] = []
	for node in _combat_nodes(scene_root, origin, range_v + 2.0):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_combat_alive") and not node.is_combat_alive():
			continue
		var center := _combat_center(node)
		if absf(center.y - origin.y) > cfg.melee_vertical_tolerance:
			continue
		var to_target := Vector3(center.x - origin.x, 0.0, center.z - origin.z)
		var dist := to_target.length()
		var hit_radius := _combat_radius(node)
		var effective_dist := dist - hit_radius
		if effective_dist > range_v or effective_dist < -hit_radius:
			continue
		if to_target.length_squared() < 0.0001:
			to_target = fwd_xz
		var dir_xz := to_target.normalized()
		var alignment := fwd_xz.dot(dir_xz)
		if alignment < cos(half_arc):
			continue
		var cand := HitCandidate.new()
		cand.node = node
		cand.center = center
		cand.radius = hit_radius
		cand.distance = effective_dist
		cand.alignment = alignment
		candidates.append(cand)

	candidates.sort_custom(func(a: HitCandidate, b: HitCandidate) -> bool:
		if absf(a.distance - b.distance) > 0.05:
			return a.distance < b.distance
		return a.alignment > b.alignment
	)

	var out: Array[Node] = []
	var limit: int = cfg.max_melee_targets
	for cand in candidates:
		out.append(cand.node)
		if out.size() >= limit:
			break
	return out


static func query_ranged(
	scene_root: Node,
	origin: Vector3,
	forward: Vector3,
	range_v: float,
	combat_def: _CombatDef = null
) -> Node:
	var cfg: _CombatDef = combat_def if combat_def else _CombatDef.create_default()
	var fwd := forward.normalized()
	if fwd.length_squared() < 0.0001:
		return null

	var best: Node = null
	var best_t := INF
	for node in _combat_nodes(scene_root, origin, range_v + 2.0):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_combat_alive") and not node.is_combat_alive():
			continue
		var center := _combat_center(node)
		var hit_radius: float = cfg.ranged_hit_radius + _combat_radius(node) * 0.5
		var to_center := center - origin
		var t := to_center.dot(fwd)
		if t < 0.0 or t > range_v:
			continue
		var closest := origin + fwd * t
		var miss := Vector2(center.x - closest.x, center.z - closest.z).length()
		if miss > hit_radius:
			continue
		if absf(center.y - closest.y) > cfg.ranged_vertical_tolerance:
			continue
		if t < best_t:
			best_t = t
			best = node
	return best


static func apply_damage(
	target: Node,
	base_damage: float,
	source_id: StringName = &"",
	log_label: String = ""
) -> float:
	if base_damage <= 0.0 or not is_instance_valid(target):
		return 0.0
	var defense := 0.0
	if target.has_method("get_combat_defense"):
		defense = float(target.get_combat_defense())
	var final := base_damage * (1.0 - clampf(defense, 0.0, 0.9))
	if target.has_method("take_damage"):
		target.take_damage(final, source_id)
	return final


## Discover combatants via Spatial Query Layer when available; group scan is legacy fallback only.
static func _combat_nodes(scene_root: Node, origin: Vector3, search_radius: float) -> Array:
	var svc = _SpatialQueryService.get_active()
	if svc == null and scene_root and scene_root.is_inside_tree():
		svc = scene_root.get_tree().get_first_node_in_group("spatial_query_service")
	if svc and svc.layer and svc.has_method("query_combat_candidates"):
		var combat_n: int = svc.layer.count_category(_SpatialQueryLayer.CAT_ENTITY) \
			+ svc.layer.count_category(_SpatialQueryLayer.CAT_AI)
		if combat_n > 0:
			var hits: Array = svc.query_combat_candidates(origin, search_radius)
			var nodes: Array = []
			for h in hits:
				var p = h.get("payload")
				if p is Node and is_instance_valid(p):
					nodes.append(p)
			if not nodes.is_empty():
				return nodes
	# Group scan: tests without a layer, and live mites the radius query missed.
	var out: Array = []
	if scene_root == null or not scene_root.is_inside_tree():
		return out
	for group_name in ["world_entity", "crystal_enemy"]:
		for node in scene_root.get_tree().get_nodes_in_group(group_name):
			out.append(node)
	return out


static func _combat_center(node: Node) -> Vector3:
	if node.has_method("get_combat_center"):
		return node.get_combat_center()
	if "global_position" in node:
		return node.global_position
	return Vector3.ZERO


static func _combat_radius(node: Node) -> float:
	if node.has_method("get_combat_radius"):
		return float(node.get_combat_radius())
	return 0.35
