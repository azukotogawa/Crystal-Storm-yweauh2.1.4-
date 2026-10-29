extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _ATRef = preload("res://player/action_targeting.gd")
const _RangedAimRef = preload("res://weapons/ranged_aim.gd")


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
	for dist in [3, 4, 5, 6]:
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
			print("BOWDIR px=%s vp=%s ptr=%s active=%s dir=%s speed=%.2f" % [p.camera.unproject_position(pt), p.get_viewport().get_visible_rect().size, _ATRef.pointer_in(p.get_viewport()), w._active_item_id(), w._launch_direction(w._attack_origin(0.6), Vector3.ZERO, def), _RangedAimRef.speed_for(1.0, float(def.get("projectile_speed", 28.0)))])
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
