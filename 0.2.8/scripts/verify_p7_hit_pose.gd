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
		var frames_log: Array = []
		for f in 90:
			await physics_frame
			frames_log.append(_tip(w, p))
			if m.hits_taken > h0 and f_hit < 0:
				f_hit = f + 1
			if f_kb < 0 and m.global_position.distance_to(pos0) > 0.05:
				f_kb = f + 1
			if f_end < 0 and (w._playback == null or w._playback.finished()):
				f_end = f + 1
		hits = m.hits_taken - h0
		var d: Dictionary = ItemTypes.get_def(id)
		print("P7_HIT tag=%s id=%s start=0 hit_frame=%d kb_frame=%d anim_end_frame=%d anim_dur=%.3f hits=%d dmg=%.1f cd=%.2f dps=%.1f" % [tag, id, f_hit, f_kb, f_end, dur, hits, hp0 - m.health, float(d.get("cooldown", 0)), float(d.get("entity_damage", d.get("damage", 0))) / float(d.get("cooldown", 0.5))])
		var low_f := -1
		var far_f := -1
		var mid_f := -1
		var lo := 1e9
		var far := -1e9
		var mid := 1e9
		for i in mini(frames_log.size(), maxi(f_end, 1)):
			var v: Vector3 = frames_log[i]
			if v == Vector3.INF:
				continue
			if v.y < lo:
				lo = v.y
				low_f = i + 1
			if v.z > far:
				far = v.z
				far_f = i + 1
			if absf(v.x) < mid:
				mid = absf(v.x)
				mid_f = i + 1
		var trace := ""
		for i in mini(frames_log.size(), maxi(f_end, 1)):
			var v: Vector3 = frames_log[i]
			trace += "%d:%.1f/%.1f/%.1f " % [i + 1, v.x, v.y, v.z]
		print("P7_TRACE id=%s x/y/fwd %s" % [id, trace])
		print("P7_POSE id=%s hit_frame=%d tip_lowest_frame=%d tip_farthest_frame=%d tip_centered_frame=%d anim_end=%d" % [id, f_hit, low_f, far_f, mid_f, f_end])
		await C.clear_mites(self)
	await _slowdown(p, w)
	quit(0)


func _tip(w, p) -> Vector3:
	var held = w._held
	if held == null:
		held = p.find_child("*HeldItem*", true, false)
	if held == null or held.get("_item") == null:
		for n in p.find_children("*", "Node3D", true, false):
			if n.get("_item") is MeshInstance3D:
				held = n
				break
	if held == null:
		return Vector3.INF
	var best := Vector3.INF
	var by := -1e9
	var parts: Array = []
	if held.get("_item") != null:
		parts.append(held._item)
		parts.append_array(held._item.get_children())
	for mi in parts:
		if not (mi is MeshInstance3D) or not mi.visible or mi.mesh == null:
			continue
		var bb: AABB = mi.get_aabb()
		for k in 8:
			var corner: Vector3 = mi.global_transform * bb.get_endpoint(k)
			var local: Vector3 = p.global_transform.affine_inverse() * corner
			var score := local.length()
			if score > by:
				by = score
				best = Vector3(local.x, local.y, -local.z)
	return best


func _slowdown(p, w) -> void:
	var slot := _slot(w, "wooden_sword")
	w.set_active_hotbar_index(slot)
	Input.action_press("move_forward")
	for _f in 40:
		await physics_frame
	var a: Vector3 = p.global_position
	var t0 := Time.get_ticks_usec()
	for _f in 60:
		await physics_frame
	var walk := Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
	var walk_ms := (Time.get_ticks_usec() - t0) / 60000.0
	a = p.global_position
	t0 = Time.get_ticks_usec()
	var worst := 0.0
	for f in 60:
		if f % 20 == 0:
			w._cooldown_timer = 0.0
			w._try_attack()
		var ft := Time.get_ticks_usec()
		await physics_frame
		worst = maxf(worst, (Time.get_ticks_usec() - ft) / 1000.0)
	var atk := Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
	var atk_ms := (Time.get_ticks_usec() - t0) / 60000.0
	Input.action_release("move_forward")
	print("P7_SLOW walk_dist_60f=%.2f attack_dist_60f=%.2f ratio=%.2f walk_frame_ms=%.2f attack_frame_ms=%.2f attack_worst_ms=%.2f" % [walk, atk, atk / maxf(walk, 0.001), walk_ms, atk_ms, worst])
