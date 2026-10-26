class_name CombatHitbox
extends RefCounted

const DEFAULT_RADIUS := 0.5
const RADIUS_SCALE := 0.65


static func sphere_of(node: Node) -> Dictionary:
	var center := Vector3.ZERO
	if node is Node3D:
		center = (node as Node3D).global_position
	if node.has_method("get_combat_center"):
		center = node.get_combat_center()
	var radius := DEFAULT_RADIUS
	if node.has_method("get_combat_radius"):
		radius = float(node.get_combat_radius()) * RADIUS_SCALE
	return {"center": center, "radius": radius}


static func segment_entry(a: Vector3, b: Vector3, center: Vector3, radius: float) -> float:
	var d := b - a
	var f := a - center
	var qa := d.dot(d)
	var qc := f.dot(f) - radius * radius
	if qc <= 0.0:
		return 0.0
	if qa < 0.000001:
		return INF
	var qb := 2.0 * f.dot(d)
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return INF
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	if t < 0.0 or t > 1.0:
		return INF
	return t


static func ray_distance(ray_origin: Vector3, ray_dir: Vector3, point: Vector3) -> float:
	var to_point := point - ray_origin
	var along := to_point.dot(ray_dir)
	return (to_point - ray_dir * along).length()


static func pick_under_ray(nodes: Array, ray_origin: Vector3, ray_dir: Vector3, from: Vector3, reach_world: float, slack: float) -> Node:
	var best: Node = null
	var best_d := INF
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_combat_alive") and not bool(node.is_combat_alive()):
			continue
		var box := sphere_of(node)
		var center: Vector3 = box.center
		var radius: float = box.radius
		if Vector2(center.x - from.x, center.z - from.z).length() > reach_world + radius:
			continue
		var d := ray_distance(ray_origin, ray_dir, center)
		if d > radius + slack or d >= best_d:
			continue
		best_d = d
		best = node
	return best


static func cursor_in_reach(ray_origin: Vector3, ray_dir: Vector3, from: Vector3, reach_world: float) -> bool:
	if absf(ray_dir.y) < 0.00001:
		return false
	var point := ray_origin + ray_dir * ((from.y - ray_origin.y) / ray_dir.y)
	return Vector2(point.x - from.x, point.z - from.z).length() <= reach_world
