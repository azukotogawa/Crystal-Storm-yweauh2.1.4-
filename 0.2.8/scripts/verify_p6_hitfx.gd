extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")

var _hit := Vector3.ZERO


func _init() -> void:
	call_deferred("_run")


func _on_attacked(_id: String, at: Vector3) -> void:
	_hit = at


func _fx_center(vfx) -> Vector3:
	var best: MeshInstance3D = null
	for m in vfx._pool._swings:
		if m.visible:
			best = m
	if best == null or best.mesh == null:
		return Vector3.INF
	return best.global_transform * best.mesh.get_aabb().get_center()


func _run() -> void:
	var p = await C.boot(self)
	var w = C.weapon(p)
	w.attacked.connect(_on_attacked)
	var vfx = get_first_node_in_group("combat_visual_feedback")
	var cam: Camera3D = p.camera
	var vs := C.vs()
	var worst := 0.0
	for item in ["wooden_sword", "crystal_hammer"]:
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var col: Vector2i = C.pcol(p) + d
			var m = await C.spawn_mite(self, col)
			for _f in 20:
				await physics_frame
			var target := C.col_center(col, m.global_position.y)
			for _f in 4:
				C.point_at(p, target)
				await physics_frame
			w._do_melee_attack(item, ItemTypes.get_def(item))
			await process_frame
			var fx := _fx_center(vfx)
			var dh := (_hit - target) / vs
			var df := (fx - target) / vs
			var flat_h := Vector2(dh.x, dh.z).length()
			var flat_f := Vector2(df.x, df.z).length()
			var sp := cam.unproject_position(fx) - cam.unproject_position(target)
			var sh := cam.unproject_position(_hit) - cam.unproject_position(target)
			worst = maxf(worst, maxf(flat_f, flat_h))
			print("HITFX %s dir=%s hit_off_vox=(%.2f,%.2f,%.2f) fx_off_vox=(%.2f,%.2f,%.2f) hit_px=(%.0f,%.0f) fx_px=(%.0f,%.0f)" % [item, d, dh.x, dh.y, dh.z, df.x, df.y, df.z, sh.x, sh.y, sp.x, sp.y])
			await C.clear_mites(self)
			for _f in 20:
				await physics_frame
	var ok := worst <= 0.35
	print("P6_HITFX worst_flat_vox=%.2f %s" % [worst, "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
