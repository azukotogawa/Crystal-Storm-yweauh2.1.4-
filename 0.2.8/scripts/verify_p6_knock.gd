extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _trial(p, item: String, mode: String) -> Dictionary:
	var moving := mode == "moving"
	var w = C.weapon(p)
	var d := Vector2i(2, 0) if not moving else Vector2i(4, 0)
	var m = await C.spawn_mite(self, C.pcol(p) + d, not moving)
	if mode == "station":
		m.bind_station(C.pcol(p) + d, C.pcol(p) + d + Vector2i(3, 0))
	if moving:
		m.contact_damage = 0.0
	for _f in 20:
		await physics_frame
	var h0: int = m.hits_taken
	var k0: float = m.knock_moved
	var start: Vector3 = m.global_position
	C.point_at(p, m.global_position)
	if moving:
		for _f in 13:
			await physics_frame
	var def := ItemTypes.get_def(item)
	if item == "crystal_bomb":
		w.inventory.add_item(item, 1)
		w._cooldown_timer = 0.0
		var thrown: bool = w._throw_bomb(item, def)
		var tr: Dictionary = await C.track_shot(self, w, m, 120)
		print("BOMBDBG thrown=%s n=%d kind=%s min_d=%.2f start=%s end=%s tc=%s" % [thrown, tr.n, tr.kind, tr.min_d, tr.start, tr.end, tr.tc])
	else:
		w._do_melee_attack(item, def)
		for _f in 45:
			await physics_frame
	var out := {"hits": m.hits_taken - h0, "knock": (m.knock_moved - k0) / C.vs(), "net": Vector2(m.global_position.x - start.x, m.global_position.z - start.z).length() / C.vs()}
	await C.clear_mites(self)
	for _f in 15:
		await physics_frame
	return out


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var bad := 0
	var line := ""
	for mode in ["still", "moving", "station"]:
		var moving: bool = mode != "still"
		for item in ["wooden_sword", "crystal_hammer", "spear", "crystal_bomb"]:
			if mode != "still" and item == "crystal_bomb":
				continue
			var r: Dictionary = await _trial(p, item, mode)
			p.health = 100000.0
			var ok: bool = int(r.hits) > 0 and float(r.net) > 0.3
			if not ok:
				bad += 1
			print("KNOCK %s mode=%s hits=%d knock_vox=%.2f net_vox=%.2f %s" % [item, mode, r.hits, r.knock, r.net, "OK" if ok else "NO_KNOCK"])
			line += " %s%s=%.2f" % [item, "" if mode == "still" else "_" + mode, r.knock]
	print("P6_KNOCK" + line + (" OK" if bad == 0 else " FAIL bad=%d" % bad))
	quit(0 if bad == 0 else 1)
