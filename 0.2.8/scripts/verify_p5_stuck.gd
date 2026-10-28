extends SceneTree

const _Nav = preload("res://entities/entity_navigation.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	for _i in 1800:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 120:
		await physics_frame
	var spawner = get_first_node_in_group("crystal_enemy_spawner")
	var pc: Vector2i = _Nav.column_pos(player.global_position)
	var dirs := [Vector2i(10, 0), Vector2i(-10, 0), Vector2i(0, 10), Vector2i(0, -10), Vector2i(7, 7), Vector2i(-7, 7), Vector2i(7, -7), Vector2i(-7, -7)]
	for d in dirs:
		spawner.spawn_enemy_at_column(&"crystal_mite", pc.x + d.x, pc.y + d.y, Vector2i.ZERO, true)
	await physics_frame
	var mites: Array = get_nodes_in_group("crystal_enemy")
	var best := {}
	var since := {}
	var stuck := 0
	var reached := 0
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < 20.0:
		await physics_frame
		t += dt
		player.health = 100.0
		var pcol: Vector2i = _Nav.column_pos(player.global_position)
		for m in mites:
			if not is_instance_valid(m):
				continue
			var mc: Vector2i = _Nav.column_pos(m.global_position)
			var d: float = Vector2(mc - pcol).length()
			if d <= 1.5:
				since[m] = 0.0
				best[m] = d
				continue
			if not best.has(m) or d < float(best[m]) - 0.5:
				best[m] = d
				since[m] = 0.0
			else:
				since[m] = float(since.get(m, 0.0)) + dt
				if float(since[m]) >= 2.0:
					stuck += 1
					since[m] = 0.0
					best[m] = d
	for m in mites:
		if is_instance_valid(m) and float(best.get(m, 99.0)) <= 1.5:
			reached += 1
	var ev := 0
	for m in mites:
		if is_instance_valid(m) and "stuck_events" in m:
			ev += int(m.stuck_events)
	print("P5_STUCK mites=%d stuck_events=%d reached=%d sidesteps=%d" % [mites.size(), stuck, reached, ev])
	quit()