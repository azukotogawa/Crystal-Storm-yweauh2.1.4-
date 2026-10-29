extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _err(p, want: Vector3) -> float:
	var y: float = p.face_yaw
	var body := Vector2(-sin(y), -cos(y))
	var w := Vector2(want.x, want.z).normalized()
	return absf(rad_to_deg(body.angle_to(w)))


func _run() -> void:
	var p = await C.boot(self)
	Input.action_press("move_forward")
	for _i in 60:
		await physics_frame
	var mv := Vector3(p._move_vel_xz.x, 0, p._move_vel_xz.y)
	if mv.length() < 0.01:
		mv = Vector3(-sin(p.face_yaw), 0, -cos(p.face_yaw))
	mv = mv.normalized()
	var worst := 0.0
	var sides := [Vector3(mv.z, 0, -mv.x), Vector3(-mv.z, 0, mv.x), -mv]
	for side in sides:
		for f in 45:
			var pt: Vector3 = p.global_position + side * 3.0 * C.vs()
			pt.y = p.global_position.y
			C.point_at(p, pt)
			if f % 2 == 0:
				var at: Vector2 = C._AT._event_pos + Vector2(1.5, 0)
				C._AT.note_event_mouse(at, p.get_viewport().get_visible_rect().size)
			await physics_frame
		var e := _err(p, side)
		worst = maxf(worst, e)
		print("FACE cursor_side=%s moving=%.2f body_vs_cursor_deg=%.1f" % [side, p._move_vel_xz.length(), e])
	for _f in 150:
		await physics_frame
	var mv2 := Vector3(p._move_vel_xz.x, 0, p._move_vel_xz.y)
	var idle_e := _err(p, mv2)
	Input.action_release("move_forward")
	print("FACE idle_cursor body_vs_move_deg=%.1f" % idle_e)
	var ok := worst < 15.0 and idle_e < 15.0
	print("P6_FACE worst_cursor_deg=%.1f idle_move_deg=%.1f %s" % [worst, idle_e, "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
