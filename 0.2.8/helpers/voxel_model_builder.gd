class_name VoxelModelBuilder
extends RefCounted

const PLAYER_VOXEL := "res://assets/voxel/entities/player.json"

static var USE_GRID_PARTS := true

static var _wind_sign: float = 0.0


class _Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var wind_sign := 1.0

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
		if indices.is_empty():
			return null
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


static func player_grid_size() -> Vector3i:
	return Vector3i(8, 17, 4)


static func parts_for(who: StringName) -> Array:
	if who == &"player":
		return _player_parts()
	return []


static func palette_for(who: StringName) -> PackedColorArray:
	if who != &"player":
		return PackedColorArray()
	return PackedColorArray([
		Color(0, 0, 0),
		Color(0.86, 0.62, 0.42),
		Color(0.28, 0.16, 0.10),
		Color(0.22, 0.42, 0.34),
		Color(0.42, 0.28, 0.14),
		Color(0.20, 0.14, 0.10),
		Color(0.08, 0.08, 0.10),
	])


static func _player_parts() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_VOXEL))
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var parts = data.get("parts", {})
	if typeof(parts) != TYPE_DICTIONARY:
		return []
	var rig := [
		["torso", "Torso", "Root"],
		["head", "Head", "Torso"],
		["upper_arm_l", "UpperArm_L", "Torso"],
		["lower_arm_l", "LowerArm_L", "UpperArm_L"],
		["upper_arm_r", "UpperArm_R", "Torso"],
		["lower_arm_r", "LowerArm_R", "UpperArm_R"],
		["leg_l", "Leg_L", "Root"],
		["leg_r", "Leg_R", "Root"],
	]
	var out: Array = []
	for row in rig:
		var raw = parts.get(str(row[0]), [])
		if typeof(raw) != TYPE_ARRAY or raw.is_empty():
			return []
		var cells: Array = []
		for item in raw:
			if typeof(item) != TYPE_ARRAY or item.size() < 4:
				return []
			cells.append(Vector4i(int(item[0]), int(item[1]), int(item[2]), int(item[3]) + 1))
		out.append(_part(str(row[0]), str(row[1]), str(row[2]), cells))
	out.append({"id": "held_item", "bone": "HeldSocket", "parent": "LowerArm_R", "socket": true, "cells": []})
	return out


static func _part(id: String, bone: String, parent: String, cells: Array) -> Dictionary:
	var pivot := "top"
	if id == "head" or id == "torso":
		pivot = "bottom"
	return {"id": id, "bone": bone, "parent": parent, "pivot": pivot, "cells": cells}


static func _fill(into: Array, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, mat: int) -> void:
	for z in range(z0, z1):
		for y in range(y0, y1):
			for x in range(x0, x1):
				into.append(Vector4i(x, y, z, mat))


static func face_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() < 1:
		return 0
	var arrays: Array = mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return idx.size() / 6


static func pivot_of(kind: String, box: AABB) -> Vector3:
	var mid := box.position + box.size * 0.5
	if kind == "top":
		return Vector3(mid.x, box.end.y, mid.z)
	if kind == "center":
		return mid
	return Vector3(mid.x, box.position.y, mid.z)


static func build_mesh(cells: Array, palette, cube: float) -> ArrayMesh:
	if cube <= 0.0 or cells.is_empty():
		return null
	var packed := _pack(cells)
	var occ: Dictionary = packed["occ"]
	if occ.is_empty():
		return null
	_ensure_wind()
	var buf := _Buf.new()
	buf.wind_sign = _wind_sign
	var size: Vector3i = packed["size"]
	var origin: Vector3i = packed["origin"]
	var shift := Vector3(origin) * cube
	for axis in 3:
		_emit_axis(buf, occ, size, palette, cube, shift, axis, 1)
		_emit_axis(buf, occ, size, palette, cube, shift, axis, -1)
	return buf.commit()


static func build_bricks(cells: Array, palette, cube: float) -> ArrayMesh:
	if cube <= 0.0 or cells.is_empty():
		return null
	var packed := _pack(cells)
	var occ: Dictionary = packed["occ"]
	if occ.is_empty():
		return null
	_ensure_wind()
	var buf := _Buf.new()
	buf.wind_sign = _wind_sign
	var shift: Vector3 = Vector3(packed["origin"]) * cube
	for key in occ.keys():
		var at: Vector3i = key
		var col := _palette_at(palette, int(occ[key]))
		for axis in 3:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			for sign in [-1, 1]:
				var nb := at
				if axis == 0:
					nb.x += sign
				elif axis == 1:
					nb.y += sign
				else:
					nb.z += sign
				if int(occ.get(nb, 0)) > 0:
					continue
				_emit_rect(buf, axis, sign, _axis_i(at, u), _axis_i(at, v), _axis_i(at, axis), 1, 1, col, cube, shift, u, v)
	return buf.commit()


static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = false
	return mat


static func make_glow_material(emission: Color) -> StandardMaterial3D:
	var mat := make_material()
	mat.emission_enabled = true
	mat.emission = emission
	return mat


static func attach_on_pivot(parent: Node3D, part_name: String, mesh: ArrayMesh, pivot: Vector3) -> Node3D:
	if parent == null or mesh == null:
		return null
	var pivot_node := Node3D.new()
	pivot_node.name = part_name
	pivot_node.position = pivot
	parent.add_child(pivot_node)
	var mi := _mesh_instance(mesh, -pivot)
	pivot_node.add_child(mi)
	return pivot_node


static func build_rig(parts: Array, palette, cube: float) -> Node3D:
	if parts.is_empty() or cube <= 0.0:
		return null
	var rig := Node3D.new()
	rig.name = "VoxelModel"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	var root := skel.add_bone("Root")
	skel.set_bone_rest(root, Transform3D.IDENTITY)
	rig.add_child(skel)
	var bone_of := {"Root": root}
	var pivot_of_bone := {"Root": Vector3.ZERO}
	var meta: Array = []
	var pending := parts.duplicate(true)
	var guard := pending.size() + 1
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var later: Array = []
		for part in pending:
			if not (part is Dictionary):
				continue
			var parent_name := str(part.get("parent", "Root"))
			if not bone_of.has(parent_name):
				later.append(part)
				continue
			if not _attach_bone(skel, part, palette, cube, bone_of, pivot_of_bone, meta):
				later.append(part)
		pending = later
	if meta.is_empty() or not pending.is_empty():
		rig.free()
		return null
	skel.set_meta("part_pivots", meta)
	skel.reset_bone_poses()
	return rig


static func _attach_bone(
	skel: Skeleton3D,
	part: Dictionary,
	palette,
	cube: float,
	bone_of: Dictionary,
	pivot_of_bone: Dictionary,
	meta: Array
) -> bool:
	var cells: Array = part.get("cells", [])
	var emit: Array = part.get("emit", [])
	var solid_cells: Array = []
	var glow_cells: Array = []
	if emit.is_empty():
		solid_cells = cells
	else:
		var last := {}
		var order: Array = []
		for cell in cells:
			var packed_cell := _as_cell(cell)
			if packed_cell.w <= 0:
				continue
			var key := Vector3i(packed_cell.x, packed_cell.y, packed_cell.z)
			if not last.has(key):
				order.append(key)
			last[key] = packed_cell.w
		for key in order:
			var at: Vector3i = key
			var mat := int(last[key])
			var kept := Vector4i(at.x, at.y, at.z, mat)
			if _listed(emit, mat):
				glow_cells.append(kept)
			else:
				solid_cells.append(kept)
	var solid: ArrayMesh = build_mesh(solid_cells, palette, cube) if not solid_cells.is_empty() else null
	var glow: ArrayMesh = build_mesh(glow_cells, palette, cube) if not glow_cells.is_empty() else null
	if solid == null and glow == null:
		return false
	var box := solid.get_aabb() if solid != null else glow.get_aabb()
	if solid != null and glow != null:
		box = box.merge(glow.get_aabb())
	var kind := str(part.get("pivot", "bottom"))
	var pivot: Vector3 = pivot_of(kind, box)
	if part.has("pivot_at"):
		pivot = part["pivot_at"]
	var parent_name := str(part.get("parent", "Root"))
	var parent_pivot: Vector3 = pivot_of_bone[parent_name]
	var bone_name := str(part.get("bone", part.get("id", "Part")))
	var idx := skel.add_bone(bone_name)
	skel.set_bone_parent(idx, int(bone_of[parent_name]))
	skel.set_bone_rest(idx, Transform3D(Basis.IDENTITY, pivot - parent_pivot))
	bone_of[bone_name] = idx
	pivot_of_bone[bone_name] = pivot
	var att := BoneAttachment3D.new()
	att.name = str(part.get("id", bone_name))
	att.bone_name = bone_name
	att.bone_idx = idx
	skel.add_child(att)
	if solid != null:
		att.add_child(_mesh_instance(solid, -pivot))
	if glow != null:
		var glow_mi := _mesh_instance(glow, -pivot)
		glow_mi.name = "Mesh" if solid == null else "Glow"
		var emission: Color = part.get("glow", Color(0.55, 0.18, 0.95))
		var glow_mat := make_glow_material(emission)
		glow_mat.emission_energy_multiplier = float(part.get("glow_energy", 1.0))
		glow_mi.material_override = glow_mat
		glow_mi.set_meta("crystal_glow", true)
		att.add_child(glow_mi)
	meta.append({"id": att.name, "bone": bone_name, "pivot": pivot})
	return true


static func _mesh_instance(mesh: ArrayMesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = make_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.position = at
	return mi


static func _pack(cells: Array) -> Dictionary:
	var min_v := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var max_v := Vector3i(-(1 << 20), -(1 << 20), -(1 << 20))
	var raw: Array[Vector4i] = []
	for cell in cells:
		var c := _as_cell(cell)
		if c.w <= 0:
			continue
		raw.append(c)
		min_v.x = mini(min_v.x, c.x)
		min_v.y = mini(min_v.y, c.y)
		min_v.z = mini(min_v.z, c.z)
		max_v.x = maxi(max_v.x, c.x)
		max_v.y = maxi(max_v.y, c.y)
		max_v.z = maxi(max_v.z, c.z)
	var occ := {}
	if raw.is_empty():
		return {"occ": occ, "size": Vector3i.ZERO, "origin": Vector3i.ZERO}
	for c in raw:
		occ[Vector3i(c.x - min_v.x, c.y - min_v.y, c.z - min_v.z)] = c.w
	var size := Vector3i(max_v.x - min_v.x + 1, max_v.y - min_v.y + 1, max_v.z - min_v.z + 1)
	return {"occ": occ, "size": size, "origin": min_v}


static func _listed(ids: Array, mat: int) -> bool:
	for id in ids:
		if int(id) == mat:
			return true
	return false


static func _as_cell(cell) -> Vector4i:
	if cell is Vector4i:
		return cell
	if cell is Dictionary:
		return Vector4i(int(cell.get("x", 0)), int(cell.get("y", 0)), int(cell.get("z", 0)), int(cell.get("mat", 0)))
	return Vector4i.ZERO


static func _emit_axis(
	buf: _Buf,
	occ: Dictionary,
	size: Vector3i,
	palette,
	cube: float,
	shift: Vector3,
	axis: int,
	sign: int
) -> void:
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var du := _axis_i(size, u)
	var dv := _axis_i(size, v)
	var dw := _axis_i(size, axis)
	if du <= 0 or dv <= 0 or dw <= 0:
		return
	for w in dw:
		var mask := PackedInt32Array()
		mask.resize(du * dv)
		mask.fill(0)
		for fill_v in dv:
			for fill_u in du:
				var here := _at_i(axis, w, u, fill_u, v, fill_v)
				var filled := int(occ.get(here, 0))
				if filled <= 0:
					continue
				var nb := _at_i(axis, w + sign, u, fill_u, v, fill_v)
				if int(occ.get(nb, 0)) > 0:
					continue
				mask[fill_u + du * fill_v] = filled
		var scan_v := 0
		while scan_v < dv:
			var scan_u := 0
			while scan_u < du:
				var mat := int(mask[scan_u + du * scan_v])
				if mat == 0:
					scan_u += 1
					continue
				var wu := 1
				while scan_u + wu < du and int(mask[scan_u + wu + du * scan_v]) == mat:
					wu += 1
				var wv := 1
				while scan_v + wv < dv and _row_matches(mask, du, scan_u, scan_v + wv, wu, mat):
					wv += 1
				for y in wv:
					for x in wu:
						mask[scan_u + x + du * (scan_v + y)] = 0
				_emit_rect(buf, axis, sign, scan_u, scan_v, w, wu, wv, _palette_at(palette, mat), cube, shift, u, v)
				scan_u += wu
			scan_v += 1


static func _row_matches(mask: PackedInt32Array, du: int, iu: int, iv: int, wu: int, mat: int) -> bool:
	for k in wu:
		if int(mask[iu + k + du * iv]) != mat:
			return false
	return true


static func _emit_rect(
	buf: _Buf,
	axis: int,
	sign: int,
	iu: int,
	iv: int,
	w: int,
	wu: int,
	wv: int,
	col: Color,
	cube: float,
	shift: Vector3,
	u: int,
	v: int
) -> void:
	var face := float(w if sign < 0 else w + 1) * cube
	var ua := float(iu) * cube
	var ub := float(iu + wu) * cube
	var va := float(iv) * cube
	var vb := float(iv + wv) * cube
	var outward := _set_axis(Vector3.ZERO, axis, float(sign))
	var a := _set_axis(_set_axis(_set_axis(Vector3.ZERO, axis, face), u, ua), v, va) + shift
	var b := _set_axis(_set_axis(_set_axis(Vector3.ZERO, axis, face), u, ub), v, va) + shift
	var c := _set_axis(_set_axis(_set_axis(Vector3.ZERO, axis, face), u, ub), v, vb) + shift
	var d := _set_axis(_set_axis(_set_axis(Vector3.ZERO, axis, face), u, ua), v, vb) + shift
	buf.emit_quad(a, b, c, d, outward, col)


static func _palette_at(palette, mat: int) -> Color:
	var n := 0
	if palette is PackedColorArray or palette is Array:
		n = palette.size()
	if mat < 0 or mat >= n:
		return Color.WHITE
	return palette[mat]


static func _at_i(axis: int, w: int, u: int, iu: int, v: int, iv: int) -> Vector3i:
	return _set_i(_set_i(_set_i(Vector3i.ZERO, axis, w), u, iu), v, iv)


static func _axis_i(p: Vector3i, axis: int) -> int:
	if axis == 0:
		return p.x
	if axis == 1:
		return p.y
	return p.z


static func _set_i(p: Vector3i, axis: int, value: int) -> Vector3i:
	if axis == 0:
		p.x = value
	elif axis == 1:
		p.y = value
	else:
		p.z = value
	return p


static func _set_axis(p: Vector3, axis: int, value: float) -> Vector3:
	if axis == 0:
		p.x = value
	elif axis == 1:
		p.y = value
	else:
		p.z = value
	return p


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
