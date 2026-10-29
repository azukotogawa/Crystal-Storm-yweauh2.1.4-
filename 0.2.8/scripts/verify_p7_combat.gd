extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _Reg = preload("res://entities/entity_brain_registry.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var w = C.weapon(p)
	var pspeed = p.get("move_speed") if "move_speed" in p else p.get("speed")
	for eid in [&"crystal_mite", &"origin_warden"]:
		var cfg = _Reg.get_def(eid)
		print("P7_ENEMY id=%s speed=%.2f hp=%.1f atk_cd=%.2f contact=%.1f player_speed=%s" % [eid, cfg.move_speed, cfg.max_health, cfg.attack_cooldown, cfg.contact_damage, str(pspeed)])
	var mite_hp: float = _Reg.get_def(&"crystal_mite").max_health
	var ward_hp: float = _Reg.get_def(&"origin_warden").max_health
	for id in ItemTypes.ITEMS.keys():
		var d: Dictionary = ItemTypes.ITEMS[id]
		if int(d.get("category", -1)) != ItemTypes.Category.WEAPON:
			continue
		var dmg := float(d.get("entity_damage", d.get("damage", 0.0)))
		var cd := float(d.get("cooldown", 0.5))
		print("P7_WEAPON id=%s range=%.1f cd=%.2f dmg=%.1f dps=%.1f kb=%.1f hits_mite=%d hits_warden=%d ttk_mite=%.2fs ttk_warden=%.2fs" % [id, float(d.get("range", 0)), cd, dmg, dmg / cd, float(d.get("knockback", 0)), ceili(mite_hp / dmg), ceili(ward_hp / dmg), (ceili(mite_hp / dmg) - 1) * cd, (ceili(ward_hp / dmg) - 1) * cd])
	var melee_far := 0
	for id in ["spear", "wooden_sword", "crystal_hammer"]:
		w.inventory.add_item(id, 1)
		var slot := -1
		for i in 9:
			var it = w.inventory.get_hotbar_item(i)
			if it != null and it.id == id:
				slot = i
		if slot < 0:
			print("P7_MELEEFAR id=%s noslot" % id)
			continue
		w.set_active_hotbar_index(slot)
		var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(1, 0))
		for _f in 20:
			await physics_frame
		C.point_at(p, C.col_center(C.pcol(p) + Vector2i(-9, 0), p.global_position.y))
		await physics_frame
		var h0: int = m.hits_taken
		var r0: int = w.refused_count
		w._cooldown_timer = 0.0
		w._try_attack()
		var resolved: int = w._cursor_capsule_targets(w._attack_origin(0.5), float(ItemTypes.get_def(id).get("range", 2.0)), 2).size()
		print("P7_MELEEDBG id=%s nearest=%s near=%d mdist=%.2f vs=%.2f pending=%d cap=%d feel=%s" % [id, w._melee_nearest, w._near_melee_targets(w._attack_origin(0.0), 2.8).size(), m.global_position.distance_to(p.global_position), C.vs(), w._pending_mode, w._cursor_capsule_targets(w._attack_origin(0.5), 2.8, 2).size(), w._configured_attack_id(id, ItemTypes.get_def(id))])
		for _f in 90:
			await physics_frame
		var h: int = m.hits_taken - h0
		if w.refused_count == r0 and resolved > 0:
			melee_far += 1
		print("P7_MELEEFAR id=%s hits=%d refused=%d resolved=%d" % [id, h, w.refused_count - r0, resolved])
		await C.clear_mites(self)
	var line := ""
	var def := ItemTypes.get_def("sling")
	var far := 0
	for dist in [4, 6, 8, 10, 11, 13]:
		var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(dist, 0))
		for _f in 20:
			await physics_frame
		C.point_at(p, m.get_combat_center())
		await physics_frame
		w.inventory.add_item("stone", 2)
		w._draw_charge = 1.0
		var h0: int = m.hits_taken
		w._do_ranged_attack("sling", def)
		var tr: Dictionary = await C.track_shot(self, w, m, 120)
		var h: int = m.hits_taken - h0
		if h > 0:
			far = dist
		line += " d%d=%d(%s)" % [dist, h, tr.kind]
		await C.clear_mites(self)
		for _f in 10:
			await physics_frame
	print("P7_SLING listed=%.0f max_hit=%d%s" % [float(def.get("range", 0)), far, line])
	print("P7_COMBAT melee_far_hits=%d/3 %s" % [melee_far, "OK" if melee_far >= 2 else "FAIL"])
	quit(0)