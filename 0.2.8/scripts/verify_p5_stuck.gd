extends SceneTree

const _Nav = preload("res://entities/entity_navigation.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Cfg = preload("res://config/entity_brain_config.gd")


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
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var side := Vector2i(d.y, d.x)
		for k in range(-3, 4):
			var c: Vector2i = pc + d * 5 + side * k
			_TerrainEdits.build_wall(c.x, c.y, _VoxelTypes.STONE)
			_TerrainEdits.build_wall(c.x, c.y, _VoxelTypes.STONE)
	for _i in 30:
		await physics_frame
	for d in dirs:
		spawner.spawn_enemy_at_column(&"crystal_mite", pc.x + d.x * 9, pc.y + d.y * 9, Vector2i.ZERO, true)
	await physics_frame
	var mites: Array = get_nodes_in_group("crystal_enemy")
	for m in mites:
		var cfg = m.brain.config.duplicate()
		cfg.behavior_profile = _Cfg.BehaviorProfile.SUICIDE_BOMBER
		cfg.detonate_on_contact = false
		m.brain.config = cfg
	var best := {}
	var since := {}
	var stuck := 0
	var reached := {}
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
			var d: float = Vector2(_Nav.column_pos(m.global_position) - pcol).length()
			if d <= 2.0:
				reached[m] = true
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
	var ev := 0
	for m in mites:
		if is_instance_valid(m) and "stuck_events" in m:
			ev += int(m.stuck_events)
	print("P5_STUCK mites=%d stuck_2s=%d reached=%d sidesteps=%d" % [mites.size(), stuck, reached.size(), ev])
	quit()
