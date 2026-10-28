extends SceneTree

const _Nav = preload("res://entities/entity_navigation.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Hit = preload("res://systems/combat_hit_resolver.gd")
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
	var feel = GameFeelConfig.active()
	var out := ""
	var i := 0
	for scale in [1.0, 2.0]:
		feel.knockback_scale = scale
		spawner.spawn_enemy_at_column(&"crystal_mite", pc.x + 4 + i * 3, pc.y - 6, Vector2i.ZERO, true)
		i += 1
		await physics_frame
		var all: Array = get_nodes_in_group("crystal_enemy")
		var m = all[all.size() - 1]
		m.max_health = 1000.0
		m.health = 1000.0
		m.move_speed = 0.0
		for _f in 30:
			await physics_frame
		for k in 3:
			m.take_damage(5.0, &"probe")
			_Hit.knock(m, m.global_position + Vector3(-1, 0, 0), 1.0)
			for _f in 40:
				await physics_frame
		player._begin_hit_knockback(false)
		var pk: float = player._knock_left
		out += " scale=%.1f hits=%d hp_lost=%.1f displaced=%.3f player_knock=%.3f" % [scale, m.hits_taken, m.hp_lost, m.knock_moved, pk]
	print("P5_KNOCK" + out)
	quit()
