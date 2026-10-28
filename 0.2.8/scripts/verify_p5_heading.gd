extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _heading(p) -> float:
	var v: Vector2 = p._wish_xz
	return rad_to_deg(atan2(v.y, v.x))


func _run() -> void:
	var game: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	for _i in 1800:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 120:
		await physics_frame
	var cam = player.camera
	Input.action_press("move_forward")
	for _i in 1200:
		if (player._wish_xz as Vector2).length() > 0.5:
			break
		await physics_frame
	for _i in 30:
		await physics_frame
	print("W0 %s vel %s" % [player._wish_xz, player._move_vel_xz])
	var h0 := _heading(player)
	var y0 := float(cam.yaw_degrees)
	var n := Engine.physics_ticks_per_second
	for i in n:
		cam.snap_yaw_degrees(y0 + 90.0 * float(i + 1) / float(n))
		await physics_frame
	print("W1 %s vel %s" % [player._wish_xz, player._move_vel_xz])
	var h1 := _heading(player)
	var held := absf(wrapf(h1 - h0, -180.0, 180.0))
	Input.action_release("move_forward")
	for _i in 10:
		await physics_frame
	Input.action_press("move_forward")
	for _i in 1200:
		if (player._wish_xz as Vector2).length() > 0.5:
			break
		await physics_frame
	var h2 := _heading(player)
	var repress := absf(wrapf(h2 - h0, -180.0, 180.0))
	Input.action_release("move_forward")
	print("HEADING cam_yaw %.1f->%.1f held_change=%.1f repress_change=%.1f speed=%.2f" % [y0, float(cam.yaw_degrees), held, repress, (player._move_vel_xz as Vector2).length()])
	var ok := held < 2.0 and repress > 80.0
	print("P5 HEADING " + ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)
