class_name CrystalVoxelLoader
extends RefCounted

const _Builder = preload("res://helpers/voxel_model_builder.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const CACHE_ROOT := "user://crystal_voxel_cache"
const _DIR_AXIS := [0, 0, 1, 1, 2, 2]
const _DIR_SIGN := [1, -1, 1, -1, 1, -1]

static var _memory := {}
static var _wind_sign := 0.0


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


static func load_model(path: String) -> CrystalVoxelModel:
	if not FileAccess.file_exists(path):
		push_error("voxel model missing %s" % path)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("voxel model json %s" % path)
		return null
	return model_from_dict(parsed)


static func model_from_dict(data: Dictionary) -> CrystalVoxelModel:
	if str(data.get("format", "")) != "crystalstorm-voxel-v1":
		push_error("voxel model format")
		return null
	var model := CrystalVoxelModel.new()
	model.model_name = str(data.get("name", ""))
	model.size = _ivec3(data.get("size", []))
	model.vpb = int(data.get("vpb", 0))
	model.base_cell = int(data.get("base_cell", 0))
	model.scale_mode = str(data.get("scale", ""))
	model.pivot = _vec3(data.get("pivot", []))
	if model.model_name == "" or model.vpb <= 0 or model.base_cell < 1:
		push_error("voxel model fields")
		return null
	if model.scale_mode != "terrain_block":
		push_error("voxel model scale")
		return null
	if model.size.x <= 0 or model.size.y <= 0 or model.size.z <= 0:
		push_error("voxel model size")
		return null
	var raw_palette = data.get("palette", [])
	if typeof(raw_palette) != TYPE_ARRAY or raw_palette.is_empty() or raw_palette.size() > 16:
		push_error("voxel model palette")
		return null
	var pal := PackedColorArray()
	for entry in raw_palette:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 3:
			push_error("voxel model palette entry")
			return null
		pal.append(Color8(int(entry[0]), int(entry[1]), int(entry[2])))
	model.palette = pal
	var parts = data.get("parts", {})
	if typeof(parts) != TYPE_DICTIONARY or parts.is_empty():
		push_error("voxel model parts")
		return null
	for key in parts.keys():
		var raw_cells = parts[key]
		if typeof(raw_cells) != TYPE_ARRAY:
			push_error("voxel model part")
			return null
		var cells: Array = []
		for item in raw_cells:
			if typeof(item) != TYPE_ARRAY or item.size() < 4:
				push_error("voxel model cell")
				return null
			cells.append(Vector4i(int(item[0]), int(item[1]), int(item[2]), int(item[3])))
		var part_name := str(key)
		model.part_order.append(part_name)
		model.part_cells[part_name] = cells
	return model


static func import_vox(path: String, model_name: String = "", pivot: Vector3 = Vector3.ZERO) -> CrystalVoxelModel:
	if not FileAccess.file_exists(path):
		push_error("vox missing %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("vox open %s" % path)
		return null
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "VOX ":
		f.close()
		push_error("vox magic %s" % path)
		return null
	if int(f.get_32()) != 150:
		f.close()
		push_error("vox version %s" % path)
		return null
	var into := {"cells": [], "size": Vector3i.ZERO, "rgba": PackedByteArray()}
	_read_vox(f, f.get_length(), into)
	f.close()
	var raw_cells: Array = into["cells"]
	if raw_cells.is_empty():
		push_error("vox empty %s" % path)
		return null
	var compact := _compact_vox(raw_cells, into["rgba"])
	var model := CrystalVoxelModel.new()
	model.model_name = model_name if model_name != "" else path.get_file().get_basename()
	model.size = into["size"]
	if model.size.x <= 0 or model.size.y <= 0 or model.size.z <= 0:
		model.size = _size_from_cells(compact["cells"])
	model.vpb = 16
	model.base_cell = 2
	model.scale_mode = "terrain_block"
	model.pivot = pivot
	model.palette = compact["palette"]
	model.part_order = PackedStringArray(["body"])
	model.part_cells = {"body": compact["cells"]}
	return model


static func mesh_for(path: String) -> ArrayMesh:
	var rig := rig_for(path)
	return rig.get("mesh", null) as ArrayMesh


static func mesh_variant(path: String, variant: int) -> ArrayMesh:
	if variant <= 0:
		return mesh_for(path)
	var key := "%s#m%d" % [path, variant]
	if _memory.has(key):
		var cached: Dictionary = _memory[key]
		return cached.get("mesh", null) as ArrayMesh
	var model := load_model(path)
	if model == null:
		return null
	var mirrored := _mirror_model(model, 0 if variant == 1 else 2)
	var built := build_rig(mirrored)
	_memory[key] = built
	return built.get("mesh", null) as ArrayMesh


static func part_meshes(path: String) -> Dictionary:
	var rig := rig_for(path)
	var parts: Dictionary = rig.get("parts", {})
	var meshes := {}
	for key in parts.keys():
		meshes[key] = (parts[key] as Dictionary).get("mesh", null)
	return meshes


static func rig_for(path: String) -> Dictionary:
	if _memory.has(path):
		return _memory[path]
	var model := load_model(path)
	if model == null:
		return {}
	var cached := _load_cache(path, model)
	if not cached.is_empty():
		_memory[path] = cached
		return cached
	var built := build_rig(model)
	_memory[path] = built
	_save_cache(path, built)
	return built


static func build_rig(model: CrystalVoxelModel) -> Dictionary:
	var full := build_part(model, "")
	var parts := {}
	for part_name_i in model.part_order:
		var part_name := str(part_name_i)
		parts[part_name] = build_part(model, part_name)
	return {
		"model": model,
		"mesh": full["mesh"],
		"quads": full["quads"],
		"voxels": full["voxels"],
		"parts": parts,
	}


static func build_part(model: CrystalVoxelModel, part_name: String) -> Dictionary:
	var cells := model.cells_for(part_name)
	var size := model.size
	var volume := size.x * size.y * size.z
	var grid := PackedInt32Array()
	grid.resize(volume)
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var zs := PackedInt32Array()
	var filled := 0
	for cell in cells:
		var c: Vector4i = cell
		if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= size.x or c.y >= size.y or c.z >= size.z:
			continue
		if c.w < 0 or c.w >= model.palette.size():
			continue
		var at := _idx(size, c.x, c.y, c.z)
		if grid[at] != 0:
			continue
		grid[at] = c.w + 1
		xs.push_back(c.x)
		ys.push_back(c.y)
		zs.push_back(c.z)
		filled += 1
	var mesh_pack := _mesh_grid(grid, xs, ys, zs, size, model.pivot, _cell_world(model), _mesh_palette(model.palette))
	var mesh: ArrayMesh = mesh_pack["mesh"]
	if mesh != null:
		mesh.resource_name = model.model_name if part_name == "" else part_name
	return {"mesh": mesh, "quads": mesh_pack["quads"], "voxels": filled}


static func quad_count(mesh: ArrayMesh) -> int:
	return _Builder.face_count(mesh)


static func cache_file(path: String, part_name: String = "") -> String:
	var tag := "full" if part_name == "" else part_name
	return "%s/%s_%s_%s.res" % [CACHE_ROOT, FileAccess.get_md5(path), _scale_token(), tag]


static func drop_memory() -> void:
	_memory = {}


static func _mesh_palette(palette: PackedColorArray) -> PackedColorArray:
	var pal := PackedColorArray()
	pal.resize(palette.size() + 1)
	pal[0] = Color(0, 0, 0, 0)
	for i in palette.size():
		pal[i + 1] = palette[i]
	return pal


static func _cell_world(model: CrystalVoxelModel) -> float:
	return _WorldSettings.get_active().voxel_scale / float(model.vpb)


static func _scale_token() -> String:
	return str(int(round(_WorldSettings.get_active().voxel_scale * 1000.0)))


static func _mesh_grid(
	grid: PackedInt32Array,
	xs: PackedInt32Array,
	ys: PackedInt32Array,
	zs: PackedInt32Array,
	size: Vector3i,
	pivot: Vector3,
	cube: float,
	palette: PackedColorArray
) -> Dictionary:
	_ensure_wind()
	var buf := _Buf.new()
	buf.wind_sign = _wind_sign
	var quads := 0
	if cube > 0.0 and not xs.is_empty():
		for d in 6:
			quads += _emit_direction(buf, grid, xs, ys, zs, size, d, palette, cube, pivot)
	var mesh := buf.commit()
	if mesh != null:
		mesh.surface_set_material(0, _Builder.make_material())
	return {"mesh": mesh, "quads": quads}


static func _emit_direction(
	buf: _Buf,
	grid: PackedInt32Array,
	xs: PackedInt32Array,
	ys: PackedInt32Array,
	zs: PackedInt32Array,
	size: Vector3i,
	d: int,
	palette: PackedColorArray,
	cube: float,
	pivot: Vector3
) -> int:
	var axis: int = _DIR_AXIS[d]
	var sign: int = _DIR_SIGN[d]
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var du := _comp(size, u)
	var dv := _comp(size, v)
	var dw := _comp(size, axis)
	var buckets: Array = []
	buckets.resize(dw)
	for i in xs.size():
		var coord := Vector3i(xs[i], ys[i], zs[i])
		var w := _comp(coord, axis)
		var neighbor := coord
		neighbor = _set_comp(neighbor, axis, w + sign)
		if _solid(grid, size, neighbor.x, neighbor.y, neighbor.z):
			continue
		var bucket = buckets[w]
		if bucket == null:
			bucket = []
			buckets[w] = bucket
		bucket.append(_comp(coord, u))
		bucket.append(_comp(coord, v))
		bucket.append(grid[_idx(size, coord.x, coord.y, coord.z)])
	var quads := 0
	var shift := -pivot * cube
	for w in dw:
		var bucket = buckets[w]
		if bucket == null or (bucket as Array).is_empty():
			continue
		var mask := PackedInt32Array()
		mask.resize(du * dv)
		var bi := 0
		while bi < bucket.size():
			var iu := int(bucket[bi])
			var iv := int(bucket[bi + 1])
			mask[iu + du * iv] = int(bucket[bi + 2])
			bi += 3
		quads += _greedy_mask(buf, mask, du, dv, axis, sign, w, u, v, palette, cube, shift)
	return quads


static func _greedy_mask(
	buf: _Buf,
	mask: PackedInt32Array,
	du: int,
	dv: int,
	axis: int,
	sign: int,
	w: int,
	u: int,
	v: int,
	palette: PackedColorArray,
	cube: float,
	shift: Vector3
) -> int:
	var quads := 0
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
			for yy in wv:
				for xx in wu:
					mask[scan_u + xx + du * (scan_v + yy)] = 0
			_emit_rect(buf, axis, sign, scan_u, scan_v, w, wu, wv, _palette_at(palette, mat), cube, shift, u, v)
			quads += 1
			scan_u += wu
		scan_v += 1
	return quads


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


static func _palette_at(palette: PackedColorArray, mat: int) -> Color:
	if mat < 0 or mat >= palette.size():
		return Color.WHITE
	return palette[mat]


static func _solid(grid: PackedInt32Array, size: Vector3i, x: int, y: int, z: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= size.x or y >= size.y or z >= size.z:
		return false
	return grid[_idx(size, x, y, z)] > 0


static func _idx(size: Vector3i, x: int, y: int, z: int) -> int:
	return x + size.x * (y + size.y * z)


static func _comp(p: Vector3i, axis: int) -> int:
	if axis == 0:
		return p.x
	if axis == 1:
		return p.y
	return p.z


static func _set_comp(p: Vector3i, axis: int, value: int) -> Vector3i:
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


static func _save_cache(path: String, rig: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_ROOT))
	var mesh: ArrayMesh = rig.get("mesh", null)
	if mesh != null:
		ResourceSaver.save(mesh, cache_file(path, ""))
	var parts: Dictionary = rig.get("parts", {})
	for key in parts.keys():
		var part_mesh: ArrayMesh = (parts[key] as Dictionary).get("mesh", null)
		if part_mesh != null:
			ResourceSaver.save(part_mesh, cache_file(path, str(key)))


static func _load_cache(path: String, model: CrystalVoxelModel) -> Dictionary:
	var full_path := cache_file(path, "")
	if not FileAccess.file_exists(full_path):
		return {}
	var mesh := ResourceLoader.load(full_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if mesh == null:
		return {}
	var parts := {}
	for part_name_i in model.part_order:
		var part_name := str(part_name_i)
		var part_path := cache_file(path, part_name)
		if not FileAccess.file_exists(part_path):
			return {}
		var part_mesh := ResourceLoader.load(part_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if part_mesh == null:
			return {}
		parts[part_name] = {
			"mesh": part_mesh,
			"quads": quad_count(part_mesh),
			"voxels": model.voxel_count(part_name),
		}
	return {
		"model": model,
		"mesh": mesh,
		"quads": quad_count(mesh),
		"voxels": model.voxel_count(""),
		"parts": parts,
	}


static func _read_vox(f: FileAccess, end_pos: int, into: Dictionary) -> void:
	while f.get_position() + 12 <= end_pos:
		var id := f.get_buffer(4).get_string_from_ascii()
		var content_len := int(f.get_32())
		var children_len := int(f.get_32())
		var content_pos := f.get_position()
		var after := content_pos + content_len + children_len
		if id == "MAIN":
			f.seek(content_pos + content_len)
			_read_vox(f, after, into)
		elif id == "SIZE" and content_len >= 12:
			var sx := int(f.get_32())
			var sy := int(f.get_32())
			var sz := int(f.get_32())
			into["size"] = Vector3i(sx, sz, sy)
		elif id == "XYZI" and content_len >= 4:
			var count := int(f.get_32())
			var cells: Array = into["cells"]
			for _i in count:
				var x := int(f.get_8())
				var y := int(f.get_8())
				var z := int(f.get_8())
				var c := int(f.get_8())
				var idx := c - 1
				if idx < 0:
					idx = 0
				cells.append(Vector4i(x, z, y, idx))
			into["cells"] = cells
		elif id == "RGBA" and content_len >= 4:
			into["rgba"] = f.get_buffer(mini(content_len, 1024))
		if f.get_position() != after:
			f.seek(after)


static func _compact_vox(cells: Array, rgba: PackedByteArray) -> Dictionary:
	var map := {}
	var pal := PackedColorArray()
	var out: Array = []
	for cell in cells:
		var c: Vector4i = cell
		var src := c.w
		if not map.has(src):
			map[src] = pal.size()
			pal.append(_rgba_at(rgba, src))
		out.append(Vector4i(c.x, c.y, c.z, int(map[src])))
	return {"cells": out, "palette": pal}


static func _rgba_at(rgba: PackedByteArray, idx: int) -> Color:
	var at := idx * 4
	if at < 0 or at + 2 >= rgba.size():
		return Color8(255, 255, 255)
	return Color8(rgba[at], rgba[at + 1], rgba[at + 2])


static func _size_from_cells(cells: Array) -> Vector3i:
	var max_v := Vector3i.ZERO
	for cell in cells:
		var c: Vector4i = cell
		max_v.x = maxi(max_v.x, c.x + 1)
		max_v.y = maxi(max_v.y, c.y + 1)
		max_v.z = maxi(max_v.z, c.z + 1)
	return max_v


static func _mirror_model(model: CrystalVoxelModel, axis: int) -> CrystalVoxelModel:
	var copy := CrystalVoxelModel.new()
	copy.model_name = model.model_name
	copy.size = model.size
	copy.vpb = model.vpb
	copy.base_cell = model.base_cell
	copy.scale_mode = model.scale_mode
	copy.palette = model.palette
	var span := copy.size.x - 1 if axis == 0 else copy.size.z - 1
	if axis == 0:
		copy.pivot = Vector3(float(span) - model.pivot.x, model.pivot.y, model.pivot.z)
	else:
		copy.pivot = Vector3(model.pivot.x, model.pivot.y, float(span) - model.pivot.z)
	copy.part_order = model.part_order.duplicate()
	var parts := {}
	for part_name_i in model.part_order:
		var part_name := str(part_name_i)
		var src: Array = model.part_cells.get(part_name, [])
		var dst: Array = []
		for cell in src:
			var c: Vector4i = cell
			if axis == 0:
				dst.append(Vector4i(span - c.x, c.y, c.z, c.w))
			else:
				dst.append(Vector4i(c.x, c.y, span - c.z, c.w))
		parts[part_name] = dst
	copy.part_cells = parts
	return copy


static func _ivec3(raw) -> Vector3i:
	if typeof(raw) != TYPE_ARRAY or raw.size() < 3:
		return Vector3i.ZERO
	return Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))


static func _vec3(raw) -> Vector3:
	if typeof(raw) != TYPE_ARRAY or raw.size() < 3:
		return Vector3.ZERO
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
