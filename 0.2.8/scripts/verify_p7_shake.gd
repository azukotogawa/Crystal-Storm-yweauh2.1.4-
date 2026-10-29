extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GI = preload("res://helpers/gameplay_input.gd")
const _Juice = preload("res://systems/juice.gd")


func _init() -> void:
	call_deferred("_run")


func _swing(w, p, pt: Vector3) -> int:
	var s0: int = _Juice.shake_requests
	C.point_at(p, pt)
	await physics_frame
	w._cooldown_timer = 0.0
	w._try_attack()
	for _i in 60:
		await physics_frame
	return _Juice.shake_requests - s0


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	GI.world_loading = false
	GI.modal_open = false
	var vs := C.vs()
	var w = C.weapon(p)
	await C.clear_mites(self)
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		var slot := -1
		for i in 9:
			var it = w.inventory.get_hotbar_item(i)
			if it != null and it.id == id:
				slot = i
		if slot < 0:
			w.inventory.add_item(id, 1)
			for i in 9:
				var it = w.inventory.get_hotbar_item(i)
				if it != null and it.id == id:
					slot = i
		w.set_active_hotbar_index(slot)
		var air := await _swing(w, p, p.global_position + Vector3(3.0 * vs, 3.0 * vs, 0.0))
		var ground := await _swing(w, p, p.global_position + Vector3(1.5 * vs, -0.9 * vs, 0.0))
		var m = await C.spawn_mite(self, C.pcol(p) + Vector2i(1, 0), true)
		for _i in 5:
			await physics_frame
		var h0: int = m.hits_taken
		var hit := await _swing(w, p, m.get_combat_center())
		print("P7_SHAKE tag=%s id=%s air_requests=%d terrain_requests=%d entity_requests=%d entity_hit=%s" % [tag, id, air, ground, hit, m.hits_taken > h0])
		await C.clear_mites(self)
	quit(0)