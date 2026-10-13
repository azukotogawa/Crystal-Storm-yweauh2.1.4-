class_name WeaponStrike
extends RefCounted
## Pure hit shapes for spear, hammer, and crystal bomb. No terrain edits.


static func thrust_targets(
	origin: Vector3,
	forward: Vector3,
	range_w: float,
	nodes: Array,
	pierce: int
) -> Array[Node]:
	var fwd := Vector3(forward.x, 0.0, forward.z)
	if fwd.length_squared() < 0.0001:
		return []
	fwd = fwd.normalized()
	var scored: Array = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_combat_alive") and not bool(node.is_combat_alive()):
			continue
		var center := _center(node)
		var radius := _radius(node)
		var to := Vector3(center.x - origin.x, 0.0, center.z - origin.z)
		var along := to.dot(fwd)
		if along < -radius or along > range_w + radius:
			continue
		var lateral := (to - fwd * along).length()
		# A thrust is a line, with a little body width so a near miss still clips.
		if lateral > radius + 0.28:
			continue
		if absf(center.y - origin.y) > 3.6:
			continue
		scored.append({"node": node, "dist": along})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.dist) < float(b.dist)
	)
	var out: Array[Node] = []
	var limit := maxi(pierce, 1)
	for row in scored:
		out.append(row.node)
		if out.size() >= limit:
			break
	return out


## Chebyshev neighborhood. radius 1 is the aimed cell plus its 8 neighbors (3×3).
static func splash_cells(center: Vector2i, chebyshev: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := maxi(chebyshev, 0)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			out.append(Vector2i(center.x + dx, center.y + dz))
	return out


## Cells whose column center is within radius. Does not read or write height.
static func blast_cells(center: Vector2i, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := maxi(int(ceil(radius)), 0)
	var r2 := radius * radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if float(dx * dx + dz * dz) <= r2 + 0.001:
				out.append(center + Vector2i(dx, dz))
	return out


## Calls damage_crystal_at only. Returns how many cells reported a hit.
static func apply_crystal_cells(crystal, cells: Array, amount: float) -> int:
	if crystal == null or amount <= 0.0 or not crystal.has_method("damage_crystal_at"):
		return 0
	var hits := 0
	for cell in cells:
		var result = crystal.damage_crystal_at(cell, amount)
		if result is Dictionary and bool(result.get("hit", false)):
			hits += 1
	return hits


static func enemies_in_radius(origin: Vector3, radius: float, nodes: Array) -> Array[Node]:
	var out: Array[Node] = []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_combat_alive") and not bool(node.is_combat_alive()):
			continue
		var center := _center(node)
		var reach := radius + _radius(node)
		var flat := Vector2(center.x - origin.x, center.z - origin.z)
		if flat.length_squared() > reach * reach:
			continue
		if absf(center.y - origin.y) > reach:
			continue
		out.append(node)
	return out


static func _center(node: Node) -> Vector3:
	if node.has_method("get_combat_center"):
		return node.get_combat_center()
	if "global_position" in node:
		return node.global_position
	return Vector3.ZERO


static func _radius(node: Node) -> float:
	if node.has_method("get_combat_radius"):
		return float(node.get_combat_radius())
	return 0.4
