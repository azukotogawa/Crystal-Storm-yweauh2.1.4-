extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GI = preload("res://helpers/gameplay_input.gd")


func _init() -> void:
	call_deferred("_run")


func _slot(w, id: String) -> int:
	for i in 9:
		var it = w.inventory.get_hotbar_item(i)
		if it != null and it.id == id:
			return i
	w.inventory.add_item(id, 1)
	for i in 9:
		var it = w.inventory.get_hotbar_item(i)
		if it != null and it.id == id:
			return i
	return -1


const ACTS := ["move_right", "move_left", "move_back", "move_forward"]


func _release() -> void:
	for a in ACTS:
		Input.action_release(a)


func _press_toward(p, dir: Vector3) -> void:
	_release()
	var best := Vector2.ZERO
	var best_dot := -2.0
	for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var wv: Vector2 = p.rotate_input_to_world(v.normalized(), p.locked_yaw_degrees)
		var dot := wv.normalized().dot(Vector2(dir.x, dir.z).normalized())
		if dot > best_dot:
			best_dot = dot
			best = v
	if best.x > 0:
		Input.action_press("move_right")
	if best.x < 0:
		Input.action_press("move_left")
	if best.y > 0:
		Input.action_press("move_back")
	if best.y < 0:
		Input.action_press("move_forward")


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	GI.world_loading = false
	GI.modal_open = false
	p.health = 100000.0
	var w = C.weapon(p)
	var vs := C.vs()
	var pspeed := float(p.move_speed) * vs
	var start_pos: Vector3 = p.global_position
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		var slot := _slot(w, id)
		if slot < 0:
			print("P7_KITE tag=%s id=%s noslot" % [tag, id])
			continue
		w.set_active_hotbar_index(slot)
		var home: Vector3 = p.global_position
		var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(1, 0), false)
		m.contact_damage = 0.0
		var mspeed: float = m.move_speed
		for _f in 10:
			await physics_frame
		C.point_at(p, m.get_combat_center())
		await physics_frame
		w._cooldown_timer = 0.0
		var h0: int = m.hits_taken
		w._try_attack()
		var f := 0
		while m.hits_taken == h0 and f < 90:
			await physics_frame
			f += 1
		var stun: float = m._stagger_left
		var knock: float = m._knock_left
		var gap0 := _flat(m.global_position, p.global_position)
		var away := Vector3(p.global_position.x - m.global_position.x, 0.0, p.global_position.z - m.global_position.z).normalized()
		var stunned_frames := 0
		for _i in 120:
			if m._stagger_left > 0.0 or m._knock_left > 0.0:
				stunned_frames += 1
			_press_toward(p, away)
			await physics_frame
		_release()
		var gap2 := _flat(m.global_position, p.global_position)
		print("P7_KITE tag=%s id=%s hit=%s stun_after_knock=%.3f knock_left=%.2f stunned_s=%.2f gap_at_hit=%.2f gap_2s=%.2f net_gain=%.2f pspeed=%.1f mspeed=%.1f" % [tag, id, m.hits_taken > h0, stun, knock, float(stunned_frames) / 60.0, gap0 / vs, gap2 / vs, (gap2 - gap0) / vs, pspeed, mspeed])
		await C.clear_mites(self)
		p.global_position = home
		for _i in 20:
			await physics_frame
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		w.set_active_hotbar_index(_slot(w, id))
		var dir := Vector3(1, 0, 0)
		var a0: Vector3 = p.global_position
		for _i in 30:
			_press_toward(p, dir)
			await physics_frame
		var a1: Vector3 = p.global_position
		for _i in 30:
			_press_toward(p, -dir)
			if w._cooldown_timer <= 0.0:
				w._try_attack()
			await physics_frame
		var a2: Vector3 = p.global_position
		_release()
		for _i in 20:
			await physics_frame
		print("P7_ATKSLOW tag=%s id=%s idle_speed=%.2f attack_speed=%.2f mult=%.2f" % [tag, id, _flat(a1, a0) * 2.0 / vs, _flat(a2, a1) * 2.0 / vs, _flat(a2, a1) / maxf(_flat(a1, a0), 0.001)])
	var slot2 := _slot(w, "wooden_sword")
	w.set_active_hotbar_index(slot2)
	_release()
	p.global_position = start_pos
	p.velocity = Vector3.ZERO
	for _i in 30:
		await physics_frame
	var m2 = await C.spawn_mite(self, C.pcol(p) + Vector2i(3, 0), false)
	m2.max_health = 100000.0
	m2.health = 100000.0
	var hp_start: float = p.health
	var hits0: int = m2.hits_taken
	var reach := 2.4 * vs
	var dmin := 1.0e9
	var dmg := 0.0
	p.health = p.max_health
	await physics_frame
	var hp_prev: float = p.health
	for _i in 1200:
		dmg += maxf(hp_prev - p.health, 0.0)
		p.health = p.max_health
		hp_prev = p.health
		if _i % 120 == 0:
			print("DBG kite i=%d d=%.2f tgt=%s ms=%.1f mpos=%s ppos=%s st=%.2f kn=%.2f" % [_i, _flat(m2.global_position, p.global_position) / vs, m2._target, m2.move_speed, m2.global_position, p.global_position, m2._stagger_left, m2._knock_left])
		var d := _flat(m2.global_position, p.global_position)
		dmin = minf(dmin, d)
		if d <= reach and w._cooldown_timer <= 0.0:
			C.point_at(p, m2.get_combat_center())
			w._try_attack()
		elif d < reach * 0.7 and (m2._stagger_left > 0.0 or m2._knock_left > 0.0) == false:
			var away2 := Vector3(p.global_position.x - m2.global_position.x, 0.0, p.global_position.z - m2.global_position.z).normalized()
			_press_toward(p, away2)
		elif d > reach * 0.9:
			_press_toward(p, Vector3(m2.global_position.x - p.global_position.x, 0.0, m2.global_position.z - p.global_position.z))
		else:
			_release()
		await physics_frame
	_release()
	print("P7_KITESCEN tag=%s weapon=wooden_sword secs=20 hits_landed=%d dmg_taken=%.1f min_gap=%.2f" % [tag, m2.hits_taken - hits0, dmg, dmin / vs])
	quit(0)
