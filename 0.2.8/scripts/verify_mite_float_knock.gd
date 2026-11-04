extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _WS = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _refusal(m, dir: Vector3, step: float) -> String:
	var cur: Vector3 = m.global_position
	var dest := cur + dir * step
	if _EntityNavigation._segment_hits_blocking_wall(cur, dest):
		return "wall"
	var ground := _EntityNavigation._knock_ground_y(m._world, m._chunk_manager, m._crystal, dest, cur.y)
	var here := _EntityNavigation._knock_ground_y(m._world, m._chunk_manager, m._crystal, cur, cur.y)
	var max_up: float = _WS.get_active().max_step_up_walk()
	var why := "none"
	if absf(ground - cur.y) > max_up + 0.05:
		why = "height_vs_current_y"
	return "%s y=%.2f ground_here=%.2f ground_dest=%.2f max_up=%.2f" % [why, cur.y, here, ground, max_up]


func _trial(p, lift: float) -> Dictionary:
	var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(2, 0), true)
	m.contact_damage = 0.0
	for _f in 20:
		await physics_frame
	var dir := Vector3(m.global_position.x - p.global_position.x, 0.0, m.global_position.z - p.global_position.z).normalized()
	if lift > 0.0:
		m.global_position.y += lift
	var why := _refusal(m, dir, 9.0 / 60.0)
	var k0: float = m.knock_moved
	m.apply_knockback(dir, 1.7 * C.vs())
	for _f in 30:
		await physics_frame
	var out := {"knock": m.knock_moved - k0, "why": why}
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return out


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var bad := 0
	var max_up: float = _WS.get_active().max_step_up_walk()
	for lift in [0.0, max_up * 1.5]:
		var r: Dictionary = await _trial(p, lift)
		var ok: bool = float(r.knock) > 0.0
		if not ok:
			bad += 1
		print("MITE_FLOAT_KNOCK lift=%.2f knock_moved=%.3f check=%s %s" % [lift, r.knock, r.why, "OK" if ok else "FAIL"])
	print("MITE_FLOAT_KNOCK %s" % ("OK" if bad == 0 else "FAIL bad=%d" % bad))
	quit(1 if bad > 0 else 0)
