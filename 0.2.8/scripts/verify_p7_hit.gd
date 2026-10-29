extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _slot(w, id: String) -> int:
	for i in 9:
		var it = w.inventory.get_hotbar_item(i)
		if it != null and it.id == id:
			return i
	w.inventory.set_hotbar_item(8, null) if w.inventory.has_method("set_hotbar_item") else null
	w.inventory.add_item(id, 1)
	for i in 9:
		var it = w.inventory.get_hotbar_item(i)
		if it != null and it.id == id:
			return i
	return -1


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	p.health = 100000.0
	var w = C.weapon(p)
	var GI = preload("res://helpers/gameplay_input.gd")
	print("P7_HITFLAGS dev=%s loading=%s pause=%s modal=%s" % [GI.dev_chat_open, GI.world_loading, GI.pause_open, GI.modal_open])
	GI.modal_open = false
	GI.pause_open = false
	GI.world_loading = false
	var feel = root.get_node_or_null("GameFeel")
	print("P7_HITDBG blocks=%s paused=%s wproc=%s" % [preload("res://helpers/gameplay_input.gd").blocks_world(), str(preload("res://helpers/gameplay_input.gd")._panels.keys()) + " menus=" + str(preload("res://helpers/gameplay_input.gd").blocks_menus()) + " map=" + str(preload("res://helpers/gameplay_input.gd").map_open), w.can_process()])
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		var slot := _slot(w, id)
		if slot < 0:
			print("P7_HIT tag=%s id=%s noslot" % [tag, id])
			continue
		w.set_active_hotbar_index(slot)
		var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(1, 0))
		for _f in 30:
			await physics_frame
		C.point_at(p, m.get_combat_center())
		await physics_frame
		w._cooldown_timer = 0.0
		var h0: int = m.hits_taken
		var hp0: float = m.health
		var pos0: Vector3 = m.global_position
		var f_hit := -1
		var f_end := -1
		var f_kb := -1
		var hits := 0
		w._try_attack()
		var dur := -1.0
		if w._playback != null:
			dur = w._playback.duration
		for f in 90:
			await physics_frame
			if m.hits_taken > h0 and f_hit < 0:
				f_hit = f + 1
			if f_kb < 0 and m.global_position.distance_to(pos0) > 0.05:
				f_kb = f + 1
			if f_end < 0 and (w._playback == null or w._playback.finished()):
				f_end = f + 1
		hits = m.hits_taken - h0
		var d: Dictionary = ItemTypes.get_def(id)
		print("P7_HIT tag=%s id=%s start=0 hit_frame=%d kb_frame=%d anim_end_frame=%d anim_dur=%.3f hits=%d dmg=%.1f cd=%.2f dps=%.1f" % [tag, id, f_hit, f_kb, f_end, dur, hits, hp0 - m.health, float(d.get("cooldown", 0)), float(d.get("entity_damage", d.get("damage", 0))) / float(d.get("cooldown", 0.5))])
		await C.clear_mites(self)
	quit(0)
