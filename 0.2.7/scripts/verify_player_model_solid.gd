extends SceneTree
## The player visual must be a closed solid from every yaw and pitch.
## Front art is assets/player/player.png. Sides and back are darkened texels.

const _Body = preload("res://player/player_body_mesh.gd")
const _WS = preload("res://config/world_settings.gd")

const _TUNICS := Color(0.22, 0.42, 0.34, 1.0)
const _SKIN := Color(0.86, 0.62, 0.42, 1.0)
const _BOOT := Color(0.20, 0.14, 0.10, 1.0)
const _EYE := Color(0.08, 0.08, 0.10, 1.0)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var src := FileAccess.get_file_as_string("res://player/player.gd")
	if src.find("_PlayerBodyMesh.apply_to") < 0:
		push_error("player.gd must build the body through PlayerBodyMesh.apply_to")
		failed = true
	else:
		print("OK player.gd calls PlayerBodyMesh.apply_to")

	var ws = _WS.get_active()
	var height: float = ws.player_height()
	var radius: float = ws.player_radius()
	var mi := MeshInstance3D.new()
	_Body.apply_to(mi, height, radius)
	var mesh := mi.mesh as ArrayMesh
	var mat := mi.material_override as StandardMaterial3D
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("player visual has no mesh surface")
		quit(1)
		return
	if mat == null:
		push_error("player visual has no material")
		quit(1)
		return
	if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		push_error("player material must stay unshaded")
		failed = true
	if mat.cull_mode != BaseMaterial3D.CULL_BACK:
		push_error("player material must cull back faces, cull=%s" % mat.cull_mode)
		failed = true
	if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		push_error("player material must be opaque (no alpha holes)")
		failed = true
	if not mat.vertex_color_use_as_albedo:
		push_error("player material must use vertex colors for the scout texels")
		failed = true
	if mat.albedo_texture != null:
		push_error("player material must not sample the cutout texture (alpha would reopen the shell)")
		failed = true
	if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		push_error("player mesh must not cast shadows")
		failed = true
	if absf(mi.position.y - height * 0.5) > 0.001:
		push_error("player mesh center must sit at half the capsule height")
		failed = true
	if not failed:
		print("OK material unshaded, cull back, opaque, shadow off")

	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or indices.size() < 12 or normals.size() != verts.size() or colors.size() != verts.size():
		push_error("player mesh arrays are incomplete verts=%d idx=%d" % [verts.size(), indices.size()])
		quit(1)
		return

	var box_sign := _box_wind_sign()
	var tri_count := 0
	var open_edges := 0
	var bad_wind := 0
	var bad_alpha := 0
	var dir_counts := {"+X": 0, "-X": 0, "+Y": 0, "-Y": 0, "+Z": 0, "-Z": 0}
	var bound_counts := {"+X": 0, "-X": 0, "+Y": 0, "-Y": 0, "+Z": 0, "-Z": 0}
	var inward_bounds := 0
	var found := {"tunic": false, "skin": false, "boot": false, "eye": false}
	var front_lum := 0.0
	var front_n := 0
	var back_lum := 0.0
	var back_n := 0
	var side_lum := 0.0
	var side_n := 0
	var edges := {}
	var aabb := AABB()
	var have_aabb := false
	var i := 0
	while i + 2 < indices.size():
		var ia := int(indices[i])
		var ib := int(indices[i + 1])
		var ic := int(indices[i + 2])
		var a: Vector3 = verts[ia]
		var b: Vector3 = verts[ib]
		var c: Vector3 = verts[ic]
		for v in [a, b, c]:
			if not have_aabb:
				aabb = AABB(v, Vector3.ZERO)
				have_aabb = true
			else:
				aabb = aabb.expand(v)
		var cr: Vector3 = (b - a).cross(c - a)
		if cr.length_squared() < 0.0000000001:
			i += 3
			continue
		tri_count += 1
		var gn: Vector3 = cr.normalized()
		var sn: Vector3 = normals[ia]
		var wind_dot := cr.dot(sn)
		var tri_sign := -1.0 if wind_dot < 0.0 else 1.0
		if tri_sign != box_sign:
			bad_wind += 1
		_count_edge(edges, a, b)
		_count_edge(edges, b, c)
		_count_edge(edges, c, a)
		var dom := _dominant(sn)
		dir_counts[dom] = int(dir_counts[dom]) + 1
		var col: Color = colors[ia]
		if col.a < 0.99:
			bad_alpha += 1
		var lum := (col.r + col.g + col.b) / 3.0
		if sn.z > 0.5:
			front_lum += lum
			front_n += 1
			if _near(col, _TUNICS):
				found["tunic"] = true
			if _near(col, _SKIN):
				found["skin"] = true
			if _near(col, _BOOT):
				found["boot"] = true
			if _near(col, _EYE):
				found["eye"] = true
		elif sn.z < -0.5:
			back_lum += lum
			back_n += 1
		elif absf(sn.x) > 0.5:
			side_lum += lum
			side_n += 1
		i += 3

	for key in edges.keys():
		if int(edges[key]) != 2:
			open_edges += 1
	if open_edges > 0:
		push_error("player mesh is not closed: %d edges are not shared by 2 triangles" % open_edges)
		failed = true
	else:
		print("OK closed manifold tris=%d" % tri_count)
	if bad_wind > 0:
		push_error("player winding does not match BoxMesh (outside visible under CULL_BACK): %d tris" % bad_wind)
		failed = true
	else:
		print("OK winding matches BoxMesh sign=%.0f" % box_sign)
	if bad_alpha > 0:
		push_error("player vertices must be opaque, punched=%d" % bad_alpha)
		failed = true

	var eps := 0.001
	i = 0
	while i + 2 < indices.size():
		var ia2 := int(indices[i])
		var a2: Vector3 = verts[ia2]
		var b2: Vector3 = verts[int(indices[i + 1])]
		var c2: Vector3 = verts[int(indices[i + 2])]
		var sn2: Vector3 = normals[ia2]
		var cen := (a2 + b2 + c2) / 3.0
		var max_pt := aabb.position + aabb.size
		if absf(cen.x - max_pt.x) < eps and absf(sn2.x) > 0.5:
			bound_counts["+X"] = int(bound_counts["+X"]) + 1
			if sn2.x < 0.5:
				inward_bounds += 1
		if absf(cen.x - aabb.position.x) < eps and absf(sn2.x) > 0.5:
			bound_counts["-X"] = int(bound_counts["-X"]) + 1
			if sn2.x > -0.5:
				inward_bounds += 1
		if absf(cen.y - max_pt.y) < eps and absf(sn2.y) > 0.5:
			bound_counts["+Y"] = int(bound_counts["+Y"]) + 1
			if sn2.y < 0.5:
				inward_bounds += 1
		if absf(cen.y - aabb.position.y) < eps and absf(sn2.y) > 0.5:
			bound_counts["-Y"] = int(bound_counts["-Y"]) + 1
			if sn2.y > -0.5:
				inward_bounds += 1
		if absf(cen.z - max_pt.z) < eps and absf(sn2.z) > 0.5:
			bound_counts["+Z"] = int(bound_counts["+Z"]) + 1
			if sn2.z < 0.5:
				inward_bounds += 1
		if absf(cen.z - aabb.position.z) < eps and absf(sn2.z) > 0.5:
			bound_counts["-Z"] = int(bound_counts["-Z"]) + 1
			if sn2.z > -0.5:
				inward_bounds += 1
		i += 3

	for axis_name in ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]:
		if int(dir_counts[axis_name]) <= 0 or int(bound_counts[axis_name]) <= 0:
			push_error("missing outward faces on %s dir=%s bound=%s" % [axis_name, dir_counts[axis_name], bound_counts[axis_name]])
			failed = true
	if inward_bounds > 0:
		push_error("AABB shell normals point inward: %d" % inward_bounds)
		failed = true
	elif not failed:
		print("OK six directions, shell normals outward")

	if aabb.size.z < aabb.size.x * 0.35:
		push_error("body is too thin in Z (size %s); sides would still read as a card" % aabb.size)
		failed = true
	elif aabb.size.y < height * 0.55:
		push_error("body height span %.3f is far below the capsule %.3f" % [aabb.size.y, height])
		failed = true
	else:
		print("OK volume size=%s" % aabb.size)

	if not found["tunic"] or not found["skin"] or not found["boot"] or not found["eye"]:
		push_error("front faces lost scout colors tunic=%s skin=%s boot=%s eye=%s" % [found["tunic"], found["skin"], found["boot"], found["eye"]])
		failed = true
	else:
		print("OK front carries tunic, skin, boot, and eyes")
	if front_n <= 0 or back_n <= 0 or side_n <= 0:
		push_error("missing front/back/side faces for tint check")
		failed = true
	elif (back_lum / float(back_n)) >= (front_lum / float(front_n)) * 0.92:
		push_error("back faces should be a darker tint of the front art")
		failed = true
	elif (side_lum / float(side_n)) >= (front_lum / float(front_n)) * 0.98:
		push_error("side faces should be a darker tint of the front art")
		failed = true
	else:
		print("OK sides and back are darker than the front")

	var aim := _aim_on_front(verts, indices, normals)
	# Sit the aim inside the shell so side rays are not coplanar with the front.
	aim.z -= maxf(aabb.size.z * 0.35, 0.001)
	var views: Array = [
		{"yaw": 0.0, "pitch": 0.0, "axis": Vector3(0, 0, 1)},
		{"yaw": 90.0, "pitch": 0.0, "axis": Vector3(1, 0, 0)},
		{"yaw": 180.0, "pitch": 0.0, "axis": Vector3(0, 0, -1)},
		{"yaw": 270.0, "pitch": 0.0, "axis": Vector3(-1, 0, 0)},
		{"yaw": 0.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 90.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 180.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 270.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 45.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 135.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 225.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 315.0, "pitch": -35.264, "axis": Vector3.ZERO},
		{"yaw": 0.0, "pitch": -89.0, "axis": Vector3.UP},
		{"yaw": 45.0, "pitch": 25.0, "axis": Vector3.ZERO},
	]
	var missed := 0
	for view in views:
		var yaw := float(view["yaw"])
		var pitch := float(view["pitch"])
		var axis: Vector3 = view["axis"]
		var ray := _view_ray(yaw, pitch, aim)
		var hit: Dictionary = _closest_hit(verts, indices, normals, ray["origin"], ray["dir"])
		if not bool(hit["hit"]):
			push_error("no solid hit from yaw %.0f pitch %.1f" % [yaw, pitch])
			missed += 1
			continue
		var n: Vector3 = hit["normal"]
		var to_cam: Vector3 = (ray["origin"] - hit["point"]).normalized()
		if n.dot(to_cam) < 0.2:
			push_error("inside-out hit from yaw %.0f pitch %.1f normal=%s" % [yaw, pitch, n])
			missed += 1
			continue
		if axis != Vector3.ZERO and n.dot(axis) < 0.7:
			push_error("yaw %.0f should show %s, got normal %s" % [yaw, axis, n])
			missed += 1
	if missed > 0:
		failed = true
	else:
		print("OK solid from cardinal yaw, iso pitch, above, and below")

	# Swings are not parented to a bone. They start at the feet + 0.7 voxels
	# and step forward (spear 1.15, hammer 0.9). The body must still cover
	# that height and stay narrower than the forward step.
	var vs: float = ws.voxel_scale
	var swing_y := 0.7 * vs
	var world_y0 := aabb.position.y + height * 0.5
	var world_y1 := world_y0 + aabb.size.y
	if swing_y < world_y0 - 0.02 or swing_y > world_y1 + 0.02:
		push_error("swing origin y=%.3f is outside the body span %.3f..%.3f" % [swing_y, world_y0, world_y1])
		failed = true
	elif maxf(aabb.size.x, aabb.size.z) * 0.5 >= 0.9 * vs:
		push_error("body half-extent overlaps the held-swing step")
		failed = true
	elif aabb.position.x < -radius - 0.02 or aabb.position.x + aabb.size.x > radius + 0.02:
		push_error("body wider than the player radius")
		failed = true
	elif aabb.position.y < -height * 0.5 - 0.02 or aabb.position.y + aabb.size.y > height * 0.5 + 0.02:
		push_error("body taller than the player capsule")
		failed = true
	else:
		print("OK body stays in the capsule; swings still clear the chest")

	mi.free()
	if failed:
		quit(1)
		return
	print("All player model solid tests OK")
	quit(0)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.04 and absf(a.g - b.g) < 0.04 and absf(a.b - b.b) < 0.04


func _dominant(n: Vector3) -> String:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if ax >= ay and ax >= az:
		return "+X" if n.x >= 0.0 else "-X"
	if ay >= ax and ay >= az:
		return "+Y" if n.y >= 0.0 else "-Y"
	return "+Z" if n.z >= 0.0 else "-Z"


func _q(v: Vector3) -> Vector3i:
	return Vector3i(int(round(v.x * 10000.0)), int(round(v.y * 10000.0)), int(round(v.z * 10000.0)))


func _count_edge(edges: Dictionary, p: Vector3, q: Vector3) -> void:
	var a := _q(p)
	var b := _q(q)
	var left := a
	var right := b
	if b.x < a.x or (b.x == a.x and (b.y < a.y or (b.y == a.y and b.z < a.z))):
		left = b
		right = a
	var key := "%d,%d,%d|%d,%d,%d" % [left.x, left.y, left.z, right.x, right.y, right.z]
	edges[key] = int(edges.get(key, 0)) + 1


func _box_wind_sign() -> float:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var arrays: Array = box.surface_get_arrays(0)
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var i0 := 0
	var i1 := 1
	var i2 := 2
	if idx.size() >= 3:
		i0 = int(idx[0])
		i1 = int(idx[1])
		i2 = int(idx[2])
	var cr: Vector3 = (vs[i1] - vs[i0]).cross(vs[i2] - vs[i0])
	return -1.0 if cr.dot(ns[i0]) < 0.0 else 1.0


func _aim_on_front(verts: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> Vector3:
	var minv := Vector3(1.0e9, 1.0e9, 1.0e9)
	var maxv := Vector3(-1.0e9, -1.0e9, -1.0e9)
	var cents: Array = []
	var i := 0
	while i + 2 < indices.size():
		var ia := int(indices[i])
		if normals[ia].z > 0.9:
			var cen := (verts[ia] + verts[int(indices[i + 1])] + verts[int(indices[i + 2])]) / 3.0
			cents.append(cen)
			minv = minv.min(cen)
			maxv = maxv.max(cen)
		i += 3
	if cents.is_empty():
		return Vector3.ZERO
	var center := (minv + maxv) * 0.5
	var best: Vector3 = cents[0]
	var best_d := 1.0e20
	for cen in cents:
		var d: float = (cen as Vector3).distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = cen
	return best


func _view_ray(yaw_deg: float, pitch_deg: float, target: Vector3) -> Dictionary:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var horiz := Vector3(sin(yaw), 0.0, cos(yaw))
	var dist := 6.0
	var origin := target + horiz * dist * cos(pitch) + Vector3.UP * dist * sin(-pitch)
	var dir := (target - origin).normalized()
	return {"origin": origin, "dir": dir}


func _closest_hit(verts: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array, origin: Vector3, dir: Vector3) -> Dictionary:
	var best_t := 1.0e20
	var best_n := Vector3.ZERO
	var best_p := Vector3.ZERO
	var hit := false
	var i := 0
	while i + 2 < indices.size():
		var ia := int(indices[i])
		var a: Vector3 = verts[ia]
		var b: Vector3 = verts[int(indices[i + 1])]
		var c: Vector3 = verts[int(indices[i + 2])]
		var t := _ray_tri(origin, dir, a, b, c)
		if t > 0.0001 and t < best_t:
			best_t = t
			best_p = origin + dir * t
			best_n = normals[ia]
			hit = true
		i += 3
	return {"hit": hit, "t": best_t, "point": best_p, "normal": best_n}


func _ray_tri(o: Vector3, d: Vector3, v0: Vector3, v1: Vector3, v2: Vector3) -> float:
	var e1 := v1 - v0
	var e2 := v2 - v0
	var pvec := d.cross(e2)
	var det := e1.dot(pvec)
	if absf(det) < 0.0000001:
		return -1.0
	var inv := 1.0 / det
	var tvec := o - v0
	var u := tvec.dot(pvec) * inv
	if u < 0.0 or u > 1.0:
		return -1.0
	var qvec := tvec.cross(e1)
	var v := d.dot(qvec) * inv
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := e2.dot(qvec) * inv
	if t <= 0.0001:
		return -1.0
	return t
