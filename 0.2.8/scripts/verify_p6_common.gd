extends RefCounted

const _Nav = preload("res://entities/entity_navigation.gd")
const _AT = preload("res://player/action_targeting.gd")


static func boot(tree: SceneTree, settle: int = 120) -> Node:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(game)
	var player = null
	for _i in 1800:
		player = tree.get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await tree.process_frame
	for _i in settle:
		await tree.physics_frame
	return player


static func spawn_mite(tree: SceneTree, col: Vector2i, still: bool = true) -> Node:
	var spawner = tree.get_first_node_in_group("crystal_enemy_spawner")
	var before: Array = tree.get_nodes_in_group("crystal_enemy")
	spawner.spawn_enemy_at_column(&"crystal_mite", col.x, col.y, Vector2i.ZERO, true)
	await tree.physics_frame
	for m in tree.get_nodes_in_group("crystal_enemy"):
		if not before.has(m):
			m.max_health = 100000.0
			m.health = 100000.0
			if still:
				m.move_speed = 0.0
				m.contact_damage = 0.0
			return m
	return null


static func clear_mites(tree: SceneTree) -> void:
	for m in tree.get_nodes_in_group("crystal_enemy"):
		m.queue_free()
	await tree.physics_frame


static func point_at(player: Node, world_pt: Vector3) -> void:
	var cam: Camera3D = player.get("camera")
	var vp := player.get_viewport()
	_AT.note_event_mouse(cam.unproject_position(world_pt), vp.get_visible_rect().size)


static func col_center(col: Vector2i, y: float) -> Vector3:
	var ws = WorldSettings.get_active()
	return Vector3(ws.column_to_world(float(col.x) + 0.5), y, ws.column_to_world(float(col.y) + 0.5))


static func pcol(player: Node) -> Vector2i:
	return _Nav.column_pos(player.global_position)


static func weapon(player: Node) -> Node:
	return player.get_node("WeaponController")


static func vs() -> float:
	return WorldSettings.get_active().voxel_scale


static func track_shot(tree: SceneTree, w: Node, target: Node, frames: int) -> Dictionary:
	var shots: Array = []
	for c in w.get_children():
		if c is Projectile and c.active:
			shots.append(c)
	var min_d := INF
	var kind := "none"
	var first: Vector3 = shots[0].global_position if not shots.is_empty() else Vector3.ZERO
	var last := first
	var tc: Vector3 = target.get_combat_center() if is_instance_valid(target) and target.has_method("get_combat_center") else Vector3.ZERO
	for _f in frames:
		for s in shots:
			if is_instance_valid(s) and s.active:
				last = s.global_position
				min_d = minf(min_d, last.distance_to(tc))
				if not s.last_hit.is_empty():
					kind = str(s.last_hit.get("kind", kind))
		await tree.physics_frame
	return {"n": shots.size(), "min_d": min_d / vs(), "kind": kind, "start": first, "end": last, "tc": tc}
