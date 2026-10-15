class_name PlayerBodyMesh
extends RefCounted

const ALBEDO := "res://assets/player/player.png"
const DEPTH_STEPS := 8
const ALPHA_CUTOFF := 0.5
const CONTENT_W := 16
const CONTENT_H := 34
const USE_SLAB_BODY := false
const _Author = preload("res://assets/player/author_player.gd")

const _TINT_SIDE := 0.62
const _TINT_BACK := 0.50
const _TINT_TOP := 0.84
const _TINT_BOTTOM := 0.42
const _ANIM_LEN := TAU
const _ANIM_STEPS := 16
const _WALK_AMP := 0.70
const _RUN_AMP := 1.05
const _ARM_SHARE := 0.65

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


static func half_width_for_height(body_height: float) -> float:
	return body_height * float(CONTENT_W) / float(CONTENT_H) * 0.5


static func apply_to(mesh_instance: MeshInstance3D, height: float, radius: float) -> void:
	_drop_rig(mesh_instance)
	if USE_SLAB_BODY:
		_apply_slab(mesh_instance, height, radius)
	else:
		_apply_rig(mesh_instance, height, radius)


static func _apply_slab(mesh_instance: MeshInstance3D, height: float, radius: float) -> void:
	var built: Dictionary = build(radius * 2.0, height)
	mesh_instance.mesh = built["mesh"]
	mesh_instance.material_override = built["material"]
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position.y = height * 0.5


static func _drop_rig(mesh_instance: MeshInstance3D) -> void:
	for node_name in ["PlayerRig", "PlayerAnim"]:
		var old := mesh_instance.get_node_or_null(node_name)
		if old == null:
			continue
		mesh_instance.remove_child(old)
		old.free()


static func play_pose(mesh_instance: MeshInstance3D, pose: String, phase: float) -> void:
	if USE_SLAB_BODY or mesh_instance == null:
		return
	var skel := mesh_instance.get_node_or_null("PlayerRig") as Skeleton3D
	var player := mesh_instance.get_node_or_null("PlayerAnim") as AnimationPlayer
	if skel == null or player == null:
		return
	var clip := pose if player.has_animation(pose) else "idle"
	if str(player.assigned_animation) != clip:
		player.play(clip)
	var length := _ANIM_LEN
	var anim := player.get_animation(clip)
	if anim != null:
		length = anim.length
	skel.reset_bone_poses()
	player.seek(fposmod(phase, maxf(length, 0.001)), true)
	_flush_bones(skel)


static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat


static func build(width: float, height: float) -> Dictionary:
	_ensure_wind()
	var img := _load_image()
	var opaque := 0
	var body_d := maxf(width, 0.001) * float(DEPTH_STEPS) / 32.0
	var mesh: ArrayMesh = null
	if img != null and img.get_width() > 0 and img.get_height() > 0 and width > 0.0 and height > 0.0:
		var extruded: Dictionary = _extrude(img, width, height)
		mesh = extruded["mesh"]
		opaque = int(extruded["opaque"])
		body_d = float(extruded["depth"])
	if opaque <= 0:
		push_error("PlayerBodyMesh: albedo had no opaque pixels; using a solid fallback box")
		body_d = maxf(width, 0.001) * 0.25
		mesh = _fallback_box(maxf(width, 0.001), maxf(height, 0.001), body_d)
	return {
		"mesh": mesh,
		"material": make_material(),
		"opaque": opaque,
		"depth": body_d,
		"width": width,
		"height": height,
	}


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


static func _load_image() -> Image:
	var tex := load(ALBEDO) as Texture2D
	var img: Image = null
	if tex != null:
		img = tex.get_image()
	if img == null or img.is_empty():
		img = Image.new()
		if img.load(ProjectSettings.globalize_path(ALBEDO)) != OK:
			return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _shade(texel: Color, n: Vector3) -> Color:
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
	return Color(texel.r * k, texel.g * k, texel.b * k, 1.0)


static func _extrude(img: Image, width: float, height: float, lim_x: int = -1, lim_y: int = -1, lim_w: int = -1, lim_h: int = -1) -> Dictionary:
	var use_limit := lim_w > 0 and lim_h > 0
	var w := img.get_width()
	var h := img.get_height()
	var d := DEPTH_STEPS
	var buf := _Buf.new()
	buf.wind_sign = _wind_sign
	buf.setup_grid(w, h, d)
	var opaque := 0
	var min_ix := w
	var max_ix := -1
	var min_my := h
	var max_my := -1
	for iy in h:
		var my := h - 1 - iy
		for ix in w:
			var pix := img.get_pixel(ix, iy)
			if pix.a < ALPHA_CUTOFF:
				continue
			if ix < min_ix:
				min_ix = ix
			if ix > max_ix:
				max_ix = ix
			if my < min_my:
				min_my = my
			if my > max_my:
				max_my = my
			if use_limit and not _pixel_in(ix, iy, lim_x, lim_y, lim_w, lim_h):
				continue
			opaque += 1
			for iz in d:
				buf.occupy(ix, my, iz)
	var span_x := 1
	var span_y := 1
	if opaque > 0:
		span_x = max_ix - min_ix + 1
		span_y = max_my - min_my + 1
	var pixel := height / float(span_y)
	var cap := width / float(maxi(span_x, 1))
	if pixel > cap:
		pixel = cap
	var body_d := pixel * float(d)
	var z_step := body_d / float(d)
	var x_origin := -float(span_x) * pixel * 0.5
	var y_origin := -height * 0.5
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
				if not buf.occ(ix + 1, my, iz):
					buf.emit_quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(1, 0, 0), _shade(texel, Vector3(1, 0, 0)))
				if not buf.occ(ix - 1, my, iz):
					buf.emit_quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0), _shade(texel, Vector3(-1, 0, 0)))
				if not buf.occ(ix, my + 1, iz):
					buf.emit_quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 1, 0), _shade(texel, Vector3(0, 1, 0)))
				if not buf.occ(ix, my - 1, iz):
					buf.emit_quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0), _shade(texel, Vector3(0, -1, 0)))
				if not buf.occ(ix, my, iz + 1):
					buf.emit_quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1), _shade(texel, Vector3(0, 0, 1)))
				if not buf.occ(ix, my, iz - 1):
					buf.emit_quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(0, 0, -1), _shade(texel, Vector3(0, 0, -1)))
	if buf.indices.is_empty():
		return {"mesh": null, "opaque": opaque, "depth": body_d}
	return {"mesh": buf.commit(), "opaque": opaque, "depth": body_d}


static func _pixel_in(ix: int, iy: int, lim_x: int, lim_y: int, lim_w: int, lim_h: int) -> bool:
	return ix >= lim_x and iy >= lim_y and ix < lim_x + lim_w and iy < lim_y + lim_h


static func _joint_pivot(part_id: String, box: AABB) -> Vector3:
	var mid := box.position + box.size * 0.5
	if part_id == "head" or part_id == "torso":
		return Vector3(mid.x, box.position.y, mid.z)
	return Vector3(mid.x, box.position.y + box.size.y, mid.z)


static func _apply_rig(mesh_instance: MeshInstance3D, height: float, radius: float) -> void:
	_ensure_wind()
	var width := radius * 2.0
	var mat := make_material()
	mesh_instance.mesh = null
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position.y = height * 0.5
	var img := _load_image()
	if img == null or width <= 0.0 or height <= 0.0:
		_apply_slab(mesh_instance, height, radius)
		return
	var full: Dictionary = _extrude(img, width, height)
	var skel := Skeleton3D.new()
	skel.name = "PlayerRig"
	var root := skel.add_bone("Root")
	skel.set_bone_rest(root, Transform3D.IDENTITY)
	var bone_of := {"Root": root}
	var pivot_of := {"Root": Vector3.ZERO}
	var covered := 0
	for part in _Author.PARTS:
		var extruded: Dictionary = _extrude(img, width, height, int(part["x"]), int(part["y"]), int(part["w"]), int(part["h"]))
		var mesh: ArrayMesh = extruded["mesh"]
		if mesh == null or int(extruded["opaque"]) <= 0:
			continue
		covered += int(extruded["opaque"])
		var pivot := _joint_pivot(str(part["id"]), mesh.get_aabb())
		var bone_name := str(part["bone"])
		var parent_name := str(part["parent"])
		var idx := skel.add_bone(bone_name)
		var parent_pivot: Vector3 = pivot_of[parent_name]
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
	if covered != int(full["opaque"]) or covered <= 0:
		skel.free()
		push_error("PlayerBodyMesh: part regions covered %d of %d opaque pixels; using the slab" % [covered, int(full["opaque"])])
		_apply_slab(mesh_instance, height, radius)
		return
	skel.reset_bone_poses()
	_flush_bones(skel)
	mesh_instance.add_child(skel)
	_attach_anim(mesh_instance, height, pivot_of)


static func _flush_bones(skel: Skeleton3D) -> void:
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()


static func _attach_anim(mesh_instance: MeshInstance3D, height: float, pivots: Dictionary) -> void:
	var player := AnimationPlayer.new()
	player.name = "PlayerAnim"
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	mesh_instance.add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _anim_idle(height, pivots))
	lib.add_animation(&"walk", _anim_gait(_WALK_AMP, height, pivots))
	lib.add_animation(&"run", _anim_gait(_RUN_AMP, height, pivots))
	lib.add_animation(&"jump", _anim_jump(height, pivots))
	lib.add_animation(&"fall", _anim_fall(height, pivots))
	lib.add_animation(&"land", _anim_land())
	player.add_animation_library(&"", lib)


static func _new_clip() -> Animation:
	var anim := Animation.new()
	anim.length = _ANIM_LEN
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


static func _bone_path(bone_name: String) -> NodePath:
	return NodePath("PlayerRig:" + bone_name)


static func _track(anim: Animation, kind: Animation.TrackType, bone_name: String) -> int:
	var track := anim.add_track(kind)
	anim.track_set_path(track, _bone_path(bone_name))
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	return track


static func _add_rot_sin(anim: Animation, bone_name: String, amp: float) -> void:
	var track := _track(anim, Animation.TYPE_ROTATION_3D, bone_name)
	for i in _ANIM_STEPS:
		var t := _ANIM_LEN * float(i) / float(_ANIM_STEPS)
		anim.rotation_track_insert_key(track, t, Quaternion(Vector3(1, 0, 0), sin(t) * amp))


static func _add_pos_sin(anim: Animation, bone_name: String, base: Vector3, lift: float, freq: float) -> void:
	var track := _track(anim, Animation.TYPE_POSITION_3D, bone_name)
	for i in _ANIM_STEPS:
		var t := _ANIM_LEN * float(i) / float(_ANIM_STEPS)
		anim.position_track_insert_key(track, t, base + Vector3(0, sin(t * freq) * lift, 0))


static func _add_pos_hold(anim: Animation, bone_name: String, offset: Vector3) -> void:
	var track := _track(anim, Animation.TYPE_POSITION_3D, bone_name)
	anim.position_track_insert_key(track, 0.0, offset)


static func _add_scale_hold(anim: Animation, bone_name: String, scale: Vector3) -> void:
	var track := _track(anim, Animation.TYPE_SCALE_3D, bone_name)
	anim.scale_track_insert_key(track, 0.0, scale)


static func _anim_idle(height: float, pivots: Dictionary) -> Animation:
	var anim := _new_clip()
	_add_pos_sin(anim, "Torso", pivots["Torso"], height * 0.045, 1.0)
	return anim


static func _anim_gait(amp: float, height: float, pivots: Dictionary) -> Animation:
	var anim := _new_clip()
	_add_pos_sin(anim, "Torso", pivots["Torso"], height * 0.018, 2.0)
	_add_rot_sin(anim, "Leg_R", amp)
	_add_rot_sin(anim, "Leg_L", -amp)
	_add_rot_sin(anim, "UpperArm_R", -amp * _ARM_SHARE)
	_add_rot_sin(anim, "UpperArm_L", amp * _ARM_SHARE)
	return anim


static func _anim_jump(height: float, pivots: Dictionary) -> Animation:
	var anim := _new_clip()
	var tuck := Vector3(0, height * 0.22, height * 0.08)
	_add_scale_hold(anim, "Torso", Vector3(1, 1.08, 1))
	_add_pos_hold(anim, "Leg_L", pivots["Leg_L"] + tuck)
	_add_pos_hold(anim, "Leg_R", pivots["Leg_R"] + tuck)
	return anim


static func _anim_fall(height: float, pivots: Dictionary) -> Animation:
	var anim := _new_clip()
	var reach := Vector3(0, -height * 0.02, height * 0.18)
	_add_pos_hold(anim, "Leg_L", pivots["Leg_L"] + reach)
	_add_pos_hold(anim, "Leg_R", pivots["Leg_R"] + reach)
	return anim


static func _anim_land() -> Animation:
	var anim := _new_clip()
	_add_scale_hold(anim, "Root", Vector3(1.16, 0.68, 1.10))
	return anim


static func _fallback_box(width: float, height: float, body_d: float) -> ArrayMesh:
	var buf := _Buf.new()
	buf.wind_sign = _wind_sign
	var tunic := Color(0.22, 0.42, 0.34, 1.0)
	var x0 := -width * 0.5
	var x1 := width * 0.5
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var z0 := -body_d * 0.5
	var z1 := body_d * 0.5
	buf.emit_quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(1, 0, 0), _shade(tunic, Vector3(1, 0, 0)))
	buf.emit_quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(-1, 0, 0), _shade(tunic, Vector3(-1, 0, 0)))
	buf.emit_quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(0, 1, 0), _shade(tunic, Vector3(0, 1, 0)))
	buf.emit_quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3(0, -1, 0), _shade(tunic, Vector3(0, -1, 0)))
	buf.emit_quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 0, 1), _shade(tunic, Vector3(0, 0, 1)))
	buf.emit_quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(0, 0, -1), _shade(tunic, Vector3(0, 0, -1)))
	return buf.commit()
