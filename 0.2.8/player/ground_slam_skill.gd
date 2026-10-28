class_name GroundSlamSkill
extends RefCounted

const _Edits = preload("res://world/terrain_edits.gd")
const _Hits = preload("res://systems/combat_hit_resolver.gd")

const SKILL_ID := &"ground_slam"
const DAMAGE := 18.0
const KNOCKBACK := 1.5
const REACH := 1


static func footprint(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dz in range(-REACH, REACH + 1):
		for dx in range(-REACH, REACH + 1):
			cells.append(Vector2i(center.x + dx, center.y + dz))
	return cells


static func surface_cells(world, center: Vector2i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for col in footprint(center):
		var y := _Edits.surface_block_y(world, col.x, col.y)
		cells.append(Vector3i(col.x, y, col.y))
	return cells


static func break_ground(world, editor, center: Vector2i) -> Dictionary:
	return _Edits.dig_cells(surface_cells(world, center), editor)


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


static func inside(col: Vector2i, center: Vector2i) -> bool:
	return absi(col.x - center.x) <= REACH and absi(col.y - center.y) <= REACH


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
		if not node.has_method("take_damage"):
			continue
		if "health" in node and float(node.health) <= 0.0:
			continue
		if not inside(column_of(node, ws), center):
			continue
		_Hits.apply_damage(node, DAMAGE, SKILL_ID, "Ground Slam", (caster as Node3D).global_position if caster is Node3D else Vector3.INF, KNOCKBACK)
		hits += 1
	return hits
