extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _case(p, mite_off: Vector2, cursor_cols: float) -> int:
	var w = C.weapon(p)
	var pc: Vector2i = C.pcol(p)
	var mc := pc + Vector2i(roundi(mite_off.x), roundi(mite_off.y))
	var m = await C.spawn_mite(self, mc)
	for _f in 20:
		await physics_frame
	var vs := C.vs()
	var start: Vector3 = p.global_position
	var aim := Vector3(start.x + cursor_cols * vs, start.y, start.z)
	C.point_at(p, aim)
	await physics_frame
	var h0: int = m.hits_taken
	w._do_melee_attack("wooden_sword", ItemTypes.get_def("wooden_sword"))
	for _f in 5:
		await physics_frame
	var h: int = m.hits_taken - h0
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return h


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var between := await _case(p, Vector2(1, 0), 2.6)
	var on := await _case(p, Vector2(2, 0), 2.0)
	var beyond := await _case(p, Vector2(5, 0), 5.0)
	var side := await _case(p, Vector2(1, 2), 2.6)
	var behind := await _case(p, Vector2(-2, 0), 2.6)
	var ok := between > 0 and on > 0 and beyond == 0 and side == 0 and behind == 0
	print("P6_SWORD between=%d on_cursor=%d beyond_range=%d off_side=%d behind=%d %s" % [between, on, beyond, side, behind, "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
