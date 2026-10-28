extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _angle(p, dir: Vector2) -> float:
	var f: Vector3 = -(p.player_mesh.global_transform.basis.z)
	var a := Vector2(f.x, f.z)
	if a.length_squared() < 0.0001 or dir.length_squared() < 0.0001:
		return 180.0
	return rad_to_deg(absf(a.angle_to(dir)))


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
	var worst := 0.0
	for act in ["move_forward", "move_right", "move_back", "move_left"]:
		Input.action_press(act)
		for _i in 1200:
			if (player._wish_xz as Vector2).length() > 0.5:
				break
			await physics_frame
		for _i in 30:
			await physics_frame
		var ang := _angle(player, player._wish_xz)
		worst = maxf(worst, ang)
		print("FACE move %s angle=%.1f" % [act, ang])
		Input.action_release(act)
		for _i in 10:
			await physics_frame
	var aims := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, -1)]
	for aim in aims:
		var t := 0
		var ang := 180.0
		while t < 15:
			if player.has_method("face_aim"):
				player.face_aim(aim)
			await physics_frame
			t += 1
		ang = _angle(player, Vector2(aim.x, aim.z))
		worst = maxf(worst, ang)
		print("FACE aim %s angle=%.1f" % [aim, ang])
	print("FACE worst=%.1f" % worst)
	print("P5 FACE " + ("OK" if worst < 10.0 else "FAIL"))
	quit(0 if worst < 10.0 else 1)