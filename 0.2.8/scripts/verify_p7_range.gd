extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _try(p, w, item: String, dist: int) -> int:
	var def := ItemTypes.get_def(item)
	var dirv := Vector2i(1, 0)
	var cam: Camera3D = p.camera
	var vsz: Vector2 = p.get_viewport().get_visible_rect().size
	var best := -1.0
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var wpt: Vector3 = C.col_center(C.pcol(p) + dv * dist, p.global_position.y + 1.0)
		var sp: Vector2 = cam.unproject_position(wpt)
		var margin: float = minf(minf(sp.x, vsz.x - sp.x), minf(sp.y, vsz.y - sp.y))
		if margin > best:
			best = margin
			dirv = dv
	var m = await C.spawn_mite(self, C.pcol(p) + dirv * dist)
	for _f in 20:
		await physics_frame
	C.point_at(p, m.get_combat_center())
	await physics_frame
	var h0: int = m.hits_taken
	w._cooldown_timer = 0.0
	if int(def.get("weapon_kind", 0)) == ItemTypes.WeaponKind.RANGED:
		w.inventory.add_item(str(def.get("ammo_id", "arrow")), 2)
		w._draw_charge = 1.0
		w._do_ranged_attack(item, def)
		var tr: Dictionary = await C.track_shot(self, w, m, 90)
		print("DBG %s d%d n=%d kind=%s min_d=%.2f start=%s end=%s tc=%s px=%s onscreen_margin=%.0f" % [item, dist, tr.n, tr.kind, tr.min_d, tr.start, tr.end, tr.tc, p.camera.unproject_position(m.get_combat_center()), best])
	else:
		w._do_melee_attack(item, def)
		for _f in 45:
			await physics_frame
	var h: int = m.hits_taken - h0
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return h


func _run() -> void:
	var p = await C.boot(self)
	root.size = Vector2i(3200, 1800)
	for _f in 5:
		await process_frame
	print("DBG vp=%s" % p.get_viewport().get_visible_rect().size)
	p.health = 100000.0
	var w = C.weapon(p)
	var hl = p.get_node_or_null("TargetHighlight")
	var line := ""
	var bad := 0
	var tag := OS.get_environment("P7_TAG")
	for item in ["wooden_sword", "spear", "crystal_hammer", "shortbow", "sling", "crystal_bomb"]:
		var r: float = float(ItemTypes.get_def(item).get("range", 6.0))
		line += " %s=%.1f" % [item, r]
	print("P7_RANGE_DEFS tag=%s%s" % [tag, line])
	for it in ["shortbow", "sling"]:
		var dd := ItemTypes.get_def(it)
		var sp: float = RangedAim.speed_for(1.0, float(dd.get("projectile_speed", 28.0)))
		var gg: float = float(dd.get("projectile_gravity", 12.0))
		print("DBG_BALLISTIC %s speed=%.2f g=%.2f max45_cols=%.2f flat_cols=%.2f" % [it, sp, gg, RangedAim.simulate_range(sp, Vector3(1, 1, 0).normalized(), gg) / C.vs(), RangedAim.simulate_range(sp, Vector3(1, 0.05, 0).normalized(), gg) / C.vs()])
	line = ""
	for item in ["wooden_sword", "spear", "crystal_hammer"]:
		var base := {"wooden_sword": 5, "spear": 5, "crystal_hammer": 5, "shortbow": 14, "sling": 11}
		var d: int = int(base[item]) + 1
		var h: int = await _try(p, w, item, d)
		line += " %s@%d=%d" % [item, d, h]
		if h <= 0:
			bad += 1
	for ctl in [["shortbow", 8], ["shortbow", 12], ["sling", 8], ["sling", 10]]:
		line += " ctl_%s@%d=%d" % [ctl[0], ctl[1], await _try(p, w, ctl[0], ctl[1])]
	print("P7_RANGE_HITS tag=%s%s" % [tag, line])
	var held: float = w._held_aim_range()
	var hlr: float = hl._active_range() if hl else -1.0
	print("P7_RANGE_HL tag=%s active=%s weapon_range=%.1f highlight_range=%.1f %s" % [tag, w._active_item_id(), held, hlr, "OK" if is_equal_approx(held, hlr) else "MISMATCH"])
	var want := {"wooden_sword": 7.0, "spear": 7.0, "crystal_hammer": 7.0, "shortbow": 16.0, "sling": 13.0, "crystal_bomb": 8.0}
	for k in want:
		if not is_equal_approx(float(ItemTypes.get_def(k).get("range", 6.0)), float(want[k])):
			bad += 1
	print("P7_RANGE tag=%s %s bad=%d note=ranged_beyond_~10cols_offscreen_at_1152x648" % [tag, "OK" if bad == 0 else "FAIL", bad])
	quit()
