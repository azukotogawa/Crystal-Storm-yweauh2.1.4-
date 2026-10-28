extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	for _i in 1800:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 30:
		await physics_frame
	var held = player.get_node_or_null("HeldItemView")
	var bad := 0
	for aim in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]:
		player.face_aim(aim)
		for _i in 20:
			await physics_frame
		held.show_item("shortbow")
		held._pose_unit = 0.0
		held.face(aim)
		held.pose_rig(aim)
		var parts: Array = held._parts
		var grip: Vector3 = parts[0].global_position
		var tip: Vector3 = (parts[2].global_position + parts[4].global_position) * 0.5
		var s0: Vector3 = parts[5].global_position
		held._set_string_draw(1.0)
		var s1: Vector3 = parts[5].global_position
		held._set_string_draw(0.0)
		var flat := Vector3(aim.x, 0, aim.z).normalized()
		var tip_d := (tip - grip).dot(flat)
		var str_d := (s0 - grip).dot(flat)
		var pull_d := (s1 - s0).dot(flat)
		var ok := tip_d < 0.0 and str_d < 0.0 and pull_d < 0.0
		if not ok:
			bad += 1
		print("BOW aim=%s socketed=%s tips_along_aim=%.2f string_along_aim=%.2f pull_along_aim=%.2f %s" % [aim, held.is_socketed(), tip_d, str_d, pull_d, "OK" if ok else "BACKWARDS"])
	print("P5 BOW " + ("OK" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)