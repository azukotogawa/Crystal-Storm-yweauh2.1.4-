extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _put_player(p, col: Vector2i) -> void:
	var x := float(col.x) + 0.5
	var z := float(col.y) + 0.5
	p.voxel_position = Vector3(x, p._sample_walkable_feet(x, z) + 0.1, z)


func _dist(m, a: Vector2i) -> float:
	return Vector2(C._Nav.column_pos(m.global_position) - a).length()


func _patch(cm, a: Vector2i, r: int, depth: float) -> void:
	var sim = cm.get_fluid_sim()
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r:
				sim.set_depth(a + Vector2i(dx, dz), depth)


func _run() -> void:
	var p = await C.boot(self)
	var cm = get_first_node_in_group("crystal_manager")
	var a: Vector2i = C.pcol(p) + Vector2i(8, 0)
	_patch(cm, a, 2, 0.8)
	for _f in 30:
		await physics_frame
	var m = await C.spawn_mite(self, a, false)
	m.contact_damage = 0.0
	var speed: float = m.move_speed
	_put_player(p, a + Vector2i(11, 0))
	var chase_max := 0.0
	for _f in 600:
		p.health = 100000.0
		chase_max = maxf(chase_max, _dist(m, a))
		await physics_frame
	_put_player(p, a + Vector2i(45, 0))
	for _f in 720:
		p.health = 100000.0
		await physics_frame
	var back := _dist(m, a)
	_patch(cm, a, 3, 1.4)
	for _f in 20:
		await physics_frame
	m.global_position = C.col_center(a, m.global_position.y + 2.0)
	_put_player(p, a + Vector2i(7, 0))
	for _f in 30:
		await physics_frame
	var sim = cm.get_fluid_sim()
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			sim.set_depth(a + Vector2i(dx, dz), 0.0)
	var out_max := 0.0
	var stuck := 0
	var since := 0.0
	var best := 99.0
	for _f in 600:
		p.health = 100000.0
		await physics_frame
		var d: float = Vector2(C._Nav.column_pos(m.global_position) - C.pcol(p)).length()
		out_max = maxf(out_max, _dist(m, a))
		if d < best - 0.5:
			best = d
			since = 0.0
		else:
			since += 1.0 / 60.0
			if since >= 2.0 and d > 2.0:
				stuck += 1
				since = 0.0
	var ok := chase_max >= 9.0 and back <= 4.0 and out_max >= 3.0
	print("P6_LEASH speed=%.2f chase_max_cols=%.1f returned_dist_cols=%.1f pit_escape_max_cols=%.1f stuck_2s=%d sidesteps=%d %s" % [speed, chase_max, back, out_max, stuck, m.stuck_events, "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
