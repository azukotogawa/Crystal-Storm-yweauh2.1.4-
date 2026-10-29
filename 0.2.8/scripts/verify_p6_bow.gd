extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var w = C.weapon(p)
	var def := ItemTypes.get_def("shortbow")
	var ammo := str(def.get("ammo_id", "arrow"))
	var hits := 0
	var shots := 0
	var line := ""
	for dist in [3, 5, 8, 11]:
		for spot in ["feet", "center"]:
			var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(dist, 0))
			for _f in 20:
				await physics_frame
			var pt: Vector3 = m.global_position if spot == "feet" else m.get_combat_center()
			C.point_at(p, pt)
			await physics_frame
			w.inventory.add_item(ammo, 2)
			w._draw_charge = 1.0
			var h0: int = m.hits_taken
			w._do_ranged_attack("shortbow", def)
			var tr: Dictionary = await C.track_shot(self, w, m, 90)
			print("BOWDBG d%d %s n=%d kind=%s min_d=%.2f start=%s end=%s tc=%s" % [dist, spot, tr.n, tr.kind, tr.min_d, tr.start, tr.end, tr.tc])
			var h: int = m.hits_taken - h0
			shots += 1
			hits += mini(h, 1)
			line += " d%d_%s=%d" % [dist, spot, h]
			await C.clear_mites(self)
			for _f in 10:
				await physics_frame
	print("P6_BOW hits=%d/%d%s %s" % [hits, shots, line, "OK" if hits == shots else "FAIL"])
	quit(0 if hits == shots else 1)
