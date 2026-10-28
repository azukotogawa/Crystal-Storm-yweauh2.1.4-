extends SceneTree

const _Nav = preload("res://entities/entity_navigation.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Juice = preload("res://systems/juice.gd")
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
	var vfx = get_first_node_in_group("combat_visual_feedback")
	var weapon = player.get_node_or_null("WeaponController")
	if weapon == null:
		for n in player.find_children("*", "", true, false):
			if n.has_signal("entity_hit"):
				weapon = n
				break
	var pc: Vector2i = _Nav.column_pos(player.global_position)
	spawner.spawn_enemy_at_column(&"crystal_mite", pc.x + 2, pc.y, Vector2i.ZERO, true)
	await physics_frame
	var all: Array = get_nodes_in_group("crystal_enemy")
	var m = all[all.size() - 1]
	m.max_health = 1000.0
	m.health = 1000.0
	m.move_speed = 0.0
	for _f in 10:
		await physics_frame
	var fx: int = 0
	var worst_off := 0.0
	var radii := 0.0
	var s0: int = _Juice.shake_requests
	for k in 3:
		var before: int = vfx._bursts.size()
		var center: Vector3 = m.get_combat_center()
		var r: float = m.get_combat_radius()
		var flat := Vector3(player.global_position.x - center.x, 0.0, player.global_position.z - center.z).normalized()
		var hit_point: Vector3 = center + flat * r
		weapon.entity_hit.emit(m, 5.0, "wooden_sword")
		for b in vfx._bursts.slice(before):
			if bool(b.get("hit_marker", false)):
				fx += 1
				var ap: Vector3 = (b["anchor"] as Node3D).global_position
				worst_off = maxf(worst_off, Vector2(ap.x - hit_point.x, ap.z - hit_point.z).length())
				var mi = b.get("mesh")
				if mi != null and mi.mesh is TorusMesh:
					radii = (mi.mesh as TorusMesh).outer_radius
		for _f in 20:
			await physics_frame
	var s_hit: int = _Juice.shake_requests - s0
	var s1: int = _Juice.shake_requests
	for k in 3:
		weapon.attacked.emit("wooden_sword", player.global_position + Vector3(0, 0, -2))
		for _f in 20:
			await physics_frame
	var s_miss: int = _Juice.shake_requests - s1
	print("P5_FX hits=3 effects=%d worst_off_from_hit_point=%.3f ring_radius=%.3f shake_on_hit=%d shake_on_miss=%d effect_scale=%.1f" % [fx, worst_off, radii, s_hit, s_miss, float(GameFeelConfig.active().get("hit_effect_scale") if GameFeelConfig.active().get("hit_effect_scale") != null else 1.0)])
	quit()
