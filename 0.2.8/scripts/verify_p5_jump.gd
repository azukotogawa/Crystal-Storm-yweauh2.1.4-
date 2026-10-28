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
	var ws = WorldSettings.get_active()
	var L: float = ws.layer_height()
	var vs: float = ws.voxel_scale
	Input.action_press("move_forward")
	for _f in 40:
		await physics_frame
	var p0: Vector3 = player.global_position
	Input.action_press("jump")
	var apex := 0.0
	var air := 0.0
	for _f in 30:
		await physics_frame
		if int(player.current_state) >= 2:
			break
	p0 = player.global_position
	for _f in 4:
		await physics_frame
	Input.action_release("jump")
	for _f in 240:
		await physics_frame
		air += 1.0 / 60.0
		apex = maxf(apex, player.global_position.y - p0.y)
		if air > 0.1 and int(player.current_state) < 2:
			break
	var p1: Vector3 = player.global_position
	var dist: float = Vector2(p1.x - p0.x, p1.z - p0.z).length() / vs
	var fd := Vector2(p1.x - p0.x, p1.z - p0.z).normalized()
	var step := Vector2i(roundi(fd.x), 0) if absf(fd.x) > absf(fd.y) else Vector2i(0, roundi(fd.y))
	Input.action_release("move_forward")
	for _f in 30:
		await physics_frame
	var c0: Vector2i = _Nav.column_pos(player.global_position)
	var base_y: float = player.global_position.y
	for k in 3:
		var c: Vector2i = c0 + step * (2 + k)
		for _n in k + 1:
			_TerrainEdits.build_wall(c.x, c.y, _VoxelTypes.STONE)
	for _f in 20:
		await physics_frame
	Input.action_press("move_forward")
	var top := 0.0
	for _f in 300:
		if _f % 30 < 3:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		await physics_frame
		top = maxf(top, player.global_position.y - base_y)
	Input.action_release("jump")
	Input.action_release("move_forward")
	print("P5_JUMP gravity_scale=%.2f apex_layers=%.2f dist_cols=%.2f air_s=%.2f land_dy=%.2f stair_rise_layers=%.2f stair_ok=%s" % [ws.player_gravity_scale, apex / L, dist, air, (p1.y - p0.y) / L, top / L, str(top / L >= 2.75)])
	for _f in 30:
		await physics_frame
	var g0: Vector2i = _Nav.column_pos(player.global_position)
	var gy: float = player.global_position.y
	step = -step
	var gc: Vector2i = g0 + step * 2
	_TerrainEdits.dig(gc.x, gc.y, 3)
	for _f in 20:
		await physics_frame
	Input.action_press("move_back")
	var low := 0.0
	var crossed := false
	for _f in 120:
		if _f % 30 < 3:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		await physics_frame
		low = minf(low, player.global_position.y - gy)
		if Vector2(_Nav.column_pos(player.global_position) - g0).dot(Vector2(step)) >= 3.0:
			crossed = true
	Input.action_release("move_back")
	print("P5_GAP walk_crossed=%s min_dy_layers=%.2f fell_in=%s" % [str(crossed), low / L, str(low / L < -0.9)])
	quit()
