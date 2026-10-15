class_name VoxelCreatureBuilder
extends RefCounted

const USE_PART_RIG := false
const CANVAS := 32
const DEPTH_STEPS := 8
const ALPHA_CUTOFF := 0.5

const _TINT_SIDE := 0.62
const _TINT_BACK := 0.50
const _TINT_TOP := 0.84
const _TINT_BOTTOM := 0.42

const DEFAULT_PARTS := [
	{"id": "body", "kind": "body", "bone": "Body", "parent": "Root", "x": 8, "y": 8, "w": 16, "h": 12},
	{"id": "head", "kind": "head", "bone": "Head", "parent": "Body", "x": 12, "y": 0, "w": 8, "h": 8},
	{"id": "leg_l", "kind": "leg", "bone": "Leg_L", "parent": "Root", "x": 8, "y": 20, "w": 6, "h": 12},
	{"id": "leg_r", "kind": "leg", "bone": "Leg_R", "parent": "Root", "x": 18, "y": 20, "w": 6, "h": 12},
	{"id": "tail", "kind": "tail", "bone": "Tail", "parent": "Body", "x": 24, "y": 16, "w": 8, "h": 8},
	{"id": "wing_l", "kind": "wing", "bone": "Wing_L", "parent": "Body", "x": 0, "y": 8, "w": 8, "h": 8},
	{"id": "wing_r", "kind": "wing", "bone": "Wing_R", "parent": "Body", "x": 24, "y": 0, "w": 8, "h": 8},
]

static var _wind_sign: float = 0.0


class _Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var grid: Array = []
	var gw := 0
	var gh := 0
	var gd := 0
	var wind_sign := 1.0

	func setup_grid(w: int, h: int, d: int) -> void:
		gw = w
		gh = h
		gd = d
		grid = []
		grid.resize(w * h * d)
		grid.fill(0)

	func occupy(x: int, y: int, z: int) -> void:
		grid[x + gw * (y + gh * z)] = 1

	func occ(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= gw or y >= gh or z >= gd:
			return false
		return int(grid[x + gw * (y + gh * z)]) != 0

	func emit_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
		var cr: Vector3 = (b - a).cross(c - a)
		if cr.dot(outward) * wind_sign < 0.0:
			var swap: Vector3 = b
			b = d
			d = swap
		var base := verts.size()
		verts.push_back(a)
		verts.push_back(b)
		verts.push_back(c)
		verts.push_back(d)
		for _i in 4:
			normals.push_back(outward)
			colors.push_back(col)
		indices.push_back(base)
		indices.push_back(base + 1)
		indices.push_back(base + 2)
		indices.push_back(base)
		indices.push_back(base + 2)
		indices.push_back(base + 3)

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func parts_for(_kind: StringName) -> Array:
	return DEFAULT_PARTS.duplicate(true)


static func parts_fit_canvas(parts: Array) -> bool:
	for part in parts:
		var x := int(part["x"])
		var y := int(part["y"])
		var w := int(part["w"])
		var h := int(part["h"])
		if x < 0 or y < 0 or w <= 0 or h <= 0:
			return false
		if x + w > CANVAS or y + h > CANVAS:
			return false
	return true


static func image_of(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func build(img: Image, parts: Array, height: float, tint: Color = Color.WHITE) -> Node3D:
	if img == null or parts.is_empty() or height <= 0.0:
		return null
	if img.get_width() <= 0 or img.get_height() <= 0:
		return null
	_ensure_wind()
	var frame := _content_frame(img)
	if int(frame["opaque"]) <= 0:
		return null
	var rig := Node3D.new()
	rig.name = "CreatureRig"
	rig.position.y = height * 0.5
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	var root := skel.add_bone("Root")
	skel.set_bone_rest(root, Transform3D.IDENTITY)
	rig.add_child(skel)
	var mat := _material()
	var bone_of := {"Root": root}
	var pivot_of := {"Root": Vector3.ZERO}
	var meta: Array = []
	var pending := parts.duplicate(true)
	var guard := pending.size() + 1
	var missing_required := false
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var later: Array = []
		for part in pending:
			var parent_name := str(part["parent"])
			if not bone_of.has(parent_name):
				later.append(part)
				continue
			if not _attach_part(skel, img, frame, part, height, tint, mat, bone_of, pivot_of, meta):
				if _is_required(str(part["kind"])):
					missing_required = true
		pending = later
	if missing_required or not pending.is_empty() or not _has_body(meta):
		rig.free()
		return null
	skel.set_meta("creature_parts", meta)
	rig.set_meta("model_height", height)
	skel.reset_bone_poses()
	_flush(skel)
	return rig


static func apply_pose(rig: Node3D, pose: String, phase: float) -> void:
	if rig == null:
		return
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	if skel == null:
		return
	var rows: Array = skel.get_meta("creature_parts", [])
	skel.reset_bone_poses()
	var swing := sin(phase)
	var leg_i := 0
	var wing_i := 0
	for row in rows:
		var bone := skel.find_bone(str(row["bone"]))
		if bone < 0:
			continue
		var kind := str(row["kind"])
		if kind == "leg":
			var side := -1.0 if leg_i % 2 == 0 else 1.0
			leg_i += 1
			var amp := 0.0
			if pose == "walk":
				amp = 0.9
			elif pose == "attack":
				amp = 0.45
			skel.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, swing * side * amp))
		elif kind == "body":
			_pose_body(skel, bone, pose, phase, swing)
		elif kind == "head" and pose == "idle":
			skel.set_bone_pose_rotation(bone, Quaternion(Vector3.RIGHT, swing * 0.08))
		elif kind == "tail":
			skel.set_bone_pose_rotation(bone, Quaternion(Vector3.UP, swing * 0.35))
		elif kind == "wing":
			var side := -1.0 if wing_i % 2 == 0 else 1.0
			wing_i += 1
			skel.set_bone_pose_rotation(bone, Quaternion(Vector3.FORWARD, swing * side * 0.55))
	_flush(skel)


static func _pose_body(skel: Skeleton3D, bone: int, pose: String, phase: float, swing: float) -> void:
	if pose == "attack":
		skel.set_bone_pose_position(bone, Vector3(0.0, 0.0, -0.12))
	elif pose == "walk":
		skel.set_bone_pose_position(bone, Vector3(0.0, absf(sin(phase * 2.0)) * 0.05, 0.0))
	else:
		skel.set_bone_pose_position(bone, Vector3(0.0, swing * 0.04, 0.0))


static func _has_body(meta: Array) -> bool:
	var head := false
	var body := false
	var legs := 0
	for row in meta:
		var kind := str(row["kind"])
		if kind == "head":
			head = true
		elif kind == "body":
			body = true
		elif kind == "leg":
			legs += 1
	return head and body and legs >= 2


static func _is_required(kind: String) -> bool:
	return kind == "body" or kind == "head" or kind == "leg"


static func _attach_part(
	skel: Skeleton3D,
	img: Image,
	frame: Dictionary,
	part: Dictionary,
	height: float,
	tint: Color,
	mat: Material,
	bone_of: Dictionary,
	pivot_of: Dictionary,
	meta: Array
) -> bool:
	var kind := str(part["kind"])
	if kind != "body" and kind != "head" and kind != "leg" and kind != "tail" and kind != "wing":
		return false
	var extruded := _extrude(img, frame, height, tint, int(part["x"]), int(part["y"]), int(part["w"]), int(part["h"]))
	var mesh: ArrayMesh = extruded["mesh"]
	if mesh == null or int(extruded["opaque"]) <= 0:
		return false
	var parent_name := str(part["parent"])
	var parent_pivot: Vector3 = pivot_of[parent_name]
	var pivot := _pivot(kind, mesh.get_aabb(), parent_pivot)
	var bone_name := str(part["bone"])
	var idx := skel.add_bone(bone_name)
	skel.set_bone_parent(idx, int(bone_of[parent_name]))
	skel.set_bone_rest(idx, Transform3D(Basis.IDENTITY, pivot - parent_pivot))
	bone_of[bone_name] = idx
	pivot_of[bone_name] = pivot
	var att := BoneAttachment3D.new()
	att.name = str(part["id"])
	att.bone_name = bone_name
	att.bone_idx = idx
	skel.add_child(att)
	var part_mi := MeshInstance3D.new()
	part_mi.name = "Mesh"
	part_mi.mesh = mesh
	part_mi.material_override = mat
	part_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part_mi.position = -pivot
	att.add_child(part_mi)
	meta.append({"bone": bone_name, "kind": kind})
	return true


static func _pivot(kind: String, box: AABB, parent_pivot: Vector3) -> Vector3:
	var mid := box.position + box.size * 0.5
	if kind == "head" or kind == "body":
		return Vector3(mid.x, box.position.y, mid.z)
	if kind == "leg":
		return Vector3(mid.x, box.position.y + box.size.y, mid.z)
	return _face_toward(box, parent_pivot)


static func _face_toward(box: AABB, target: Vector3) -> Vector3:
	var mid := box.position + box.size * 0.5
	var faces: Array[Vector3] = [
		Vector3(box.position.x, mid.y, mid.z),
		Vector3(box.end.x, mid.y, mid.z),
		Vector3(mid.x, box.position.y, mid.z),
		Vector3(mid.x, box.end.y, mid.z),
		Vector3(mid.x, mid.y, box.position.z),
		Vector3(mid.x, mid.y, box.end.z),
	]
	var best := mid
	var best_d := INF
	for face in faces:
		var dist := face.distance_squared_to(target)
		if dist < best_d:
			best_d = dist
			best = face
	return best


static func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat


static func _ensure_wind() -> void:
	if _wind_sign != 0.0:
		return
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
	_wind_sign = -1.0 if cr.dot(ns[i0]) < 0.0 else 1.0


static func _shade(texel: Color, n: Vector3, tint: Color) -> Color:
	var k := 1.0
	if n.z > 0.5:
		k = 1.0
	elif n.z < -0.5:
		k = _TINT_BACK
	elif absf(n.x) > 0.5:
		k = _TINT_SIDE
	elif n.y > 0.5:
		k = _TINT_TOP
	else:
		k = _TINT_BOTTOM
	return Color(texel.r * tint.r * k, texel.g * tint.g * k, texel.b * tint.b * k, 1.0)


static func _content_frame(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var min_ix := w
	var max_ix := -1
	var min_my := h
	var max_my := -1
	var opaque := 0
	for iy in h:
		var my := h - 1 - iy
		for ix in w:
			if img.get_pixel(ix, iy).a < ALPHA_CUTOFF:
				continue
			opaque += 1
			min_ix = mini(min_ix, ix)
			max_ix = maxi(max_ix, ix)
			min_my = mini(min_my, my)
			max_my = maxi(max_my, my)
	return {
		"min_ix": min_ix,
		"max_ix": max_ix,
		"min_my": min_my,
		"max_my": max_my,
		"opaque": opaque,
	}


static func _extrude(img: Image, frame: Dictionary, height: float, tint: Color, lim_x: int, lim_y: int, lim_w: int, lim_h: int) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var d := DEPTH_STEPS
	var buf := _Buf.new()
	buf.wind_sign = _wind_sign
	buf.setup_grid(w, h, d)
	var opaque := 0
	for iy in h:
		var my := h - 1 - iy
		for ix in w:
			if img.get_pixel(ix, iy).a < ALPHA_CUTOFF:
				continue
			if not _pixel_in(ix, iy, lim_x, lim_y, lim_w, lim_h):
				continue
			opaque += 1
			for iz in d:
				buf.occupy(ix, my, iz)
	var span_x := maxi(int(frame["max_ix"]) - int(frame["min_ix"]) + 1, 1)
	var span_y := maxi(int(frame["max_my"]) - int(frame["min_my"]) + 1, 1)
	var pixel := height / float(span_y)
	var cap := height / float(span_x)
	if pixel > cap:
		pixel = cap
	var body_d := pixel * float(d)
	var z_step := body_d / float(d)
	var x_origin := -float(span_x) * pixel * 0.5
	var y_origin := -height * 0.5
	var min_ix := int(frame["min_ix"])
	var min_my := int(frame["min_my"])
	for iz in d:
		for my in h:
			for ix in w:
				if not buf.occ(ix, my, iz):
					continue
				var texel := img.get_pixel(ix, h - 1 - my)
				var x0 := x_origin + float(ix - min_ix) * pixel
				var x1 := x0 + pixel
				var y0 := y_origin + float(my - min_my) * pixel
				var y1 := y0 + pixel
				var z0 := -body_d * 0.5 + float(iz) * z_step
				var z1 := z0 + z_step
				_emit_cell(buf, ix, my, iz, texel, tint, x0, x1, y0, y1, z0, z1)
	if buf.indices.is_empty():
		return {"mesh": null, "opaque": opaque}
	return {"mesh": buf.commit(), "opaque": opaque}


static func _emit_cell(buf: _Buf, ix: int, my: int, iz: int, texel: Color, tint: Color, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	if not buf.occ(ix + 1, my, iz):
		buf.emit_quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(1, 0, 0), _shade(texel, Vector3(1, 0, 0), tint))
	if not buf.occ(ix - 1, my, iz):
		buf.emit_quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0), _shade(texel, Vector3(-1, 0, 0), tint))
	if not buf.occ(ix, my + 1, iz):
		buf.emit_quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 1, 0), _shade(texel, Vector3(0, 1, 0), tint))
	if not buf.occ(ix, my - 1, iz):
		buf.emit_quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0), _shade(texel, Vector3(0, -1, 0), tint))
	if not buf.occ(ix, my, iz + 1):
		buf.emit_quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1), _shade(texel, Vector3(0, 0, 1), tint))
	if not buf.occ(ix, my, iz - 1):
		buf.emit_quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(0, 0, -1), _shade(texel, Vector3(0, 0, -1), tint))


static func _pixel_in(ix: int, iy: int, lim_x: int, lim_y: int, lim_w: int, lim_h: int) -> bool:
	return ix >= lim_x and iy >= lim_y and ix < lim_x + lim_w and iy < lim_y + lim_h


static func _flush(skel: Skeleton3D) -> void:
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
