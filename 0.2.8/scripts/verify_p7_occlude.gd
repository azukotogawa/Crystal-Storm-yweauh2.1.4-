extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _Cut = preload("res://helpers/camera_cutaway.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")


func _init() -> void:
	call_deferred("_run")


func _samples(box: AABB) -> Array:
	var out: Array = []
	for ix in 3:
		for iy in 3:
			for iz in 3:
				out.append(box.position + box.size * Vector3(0.05 + 0.45 * ix, 0.05 + 0.45 * iy, 0.05 + 0.45 * iz))
	return out


func _run() -> void:
	var p = await C.boot(self)
	var ws = WorldSettings.get_active()
	var L: float = ws.layer_height()
	var vs: float = ws.voxel_scale
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var feet: Vector3 = p.global_position
	var campos: Vector3 = cam.global_position
	var to_cam := Vector2(campos.x - feet.x, campos.z - feet.z).normalized()
	var fwd := Vector2i(roundi(to_cam.x), roundi(to_cam.y))
	var perp := Vector2i(-fwd.y, fwd.x)
	var pc: Vector2i = C.pcol(p)
	var false_cut := 0
	var missed := 0
	var occl := 0
	var cut_n := 0
	var detail := ""
	var t0 := Time.get_ticks_usec()
	var calls := 0
	for a in range(-2, 4):
		for b in range(-2, 3):
			if a == 0 and b == 0:
				continue
			for layer in 3:
				var c: Vector2i = pc + fwd * a + perp * b
				var center: Vector3 = _Coords.column_to_world_pos(float(c.x) + 0.5, feet.y + (float(layer) + 0.5) * L, float(c.y) + 0.5)
				var box := AABB(center - Vector3(vs, L, vs) * 0.5, Vector3(vs, L, vs))
				var cut := false
				for s in _samples(box):
					calls += 1
					if _Cut.contains(s, feet, campos):
						cut = true
				var occ := false
				var miss := false
				for k in 6:
					var body_pt: Vector3 = feet + Vector3(0, L * (0.1 + 0.25 * k), 0)
					var hit = box.intersects_segment(campos, body_pt)
					if hit != null:
						occ = true
						var hp: Vector3 = hit
						calls += 1
						if hp.y > feet.y + _Cut.FEET_CLEAR + 0.01 and not _Cut.contains(hp + (body_pt - campos).normalized() * 0.02, feet, campos):
							miss = true
				if occ:
					occl += 1
				if cut:
					cut_n += 1
				if cut and not occ:
					false_cut += 1
					if detail.length() < 900:
						detail += " fc(a%d,b%d,h%d)" % [a, b, layer + 1]
				if miss:
					missed += 1
					if detail.length() < 900:
						detail += " miss(a%d,b%d,h%d)" % [a, b, layer + 1]
	var us := Time.get_ticks_usec() - t0
	print("P7_OCCLUDE_GEOM L=%.2f vs=%.2f cam_dist=%.2f cam_h=%.2f fwd=%s" % [L, vs, campos.distance_to(feet), campos.y - feet.y, fwd])
	print("P7_OCCLUDE_DETAIL%s" % detail)
	print("P7_OCCLUDE tag=%s blocks=%d occluding=%d cut=%d false_cut=%d missed=%d contains_calls=%d us_per_call=%.2f radius=%.2f feet_clear=%.2f %s" % [OS.get_environment("P7_TAG"), 5 * 6 * 3 - 3, occl, cut_n, false_cut, missed, calls, float(us) / maxf(calls, 1), _Cut.RADIUS_AT_PLAYER, _Cut.FEET_CLEAR, "OK" if false_cut == 0 and missed == 0 else "FAIL"])
	quit()
