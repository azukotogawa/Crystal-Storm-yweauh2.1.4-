extends RefCounted

var _mesh_id: int = 0
var _rest := PackedVector3Array()
var _normals: PackedVector3Array
var _colors: PackedColorArray
var _indices: PackedInt32Array
var _part_binds: Array = []
var _y_min: float = 0.0
var _span: float = 1.0
var _max_abs_x: float = 1.0


func apply(mi: MeshInstance3D, pose: String, phase: float) -> void:
	if mi == null:
		return
	_bind(mi)
	if _span < 0.001:
		return
	if not _part_binds.is_empty():
		for bind in _part_binds:
			var posed: PackedVector3Array = _pose_array(bind["rest"], pose, phase)
			_write_mesh(bind["mi"], posed, bind["normals"], bind["colors"], bind["indices"])
		return
	if _rest.is_empty():
		return
	_write_mesh(mi, _pose_array(_rest, pose, phase), _normals, _colors, _indices)


func _pose_array(rest: PackedVector3Array, pose: String, phase: float) -> PackedVector3Array:
	var posed := rest.duplicate()
	var hip_y := _y_min + _span * 0.46
	var shoulder_y := _y_min + _span * 0.72
	var arm_x := _max_abs_x * 0.55
	var n := posed.size()
	for i in n:
		posed[i] = _pose_point(rest[i], pose, phase, hip_y, shoulder_y, arm_x)
	return posed


func _pose_point(p: Vector3, pose: String, phase: float, hip_y: float, shoulder_y: float, arm_x: float) -> Vector3:
	var t := (p.y - _y_min) / _span
	if pose == "walk" or pose == "run":
		var amp := 1.05 if pose == "run" else 0.70
		var swing := sin(phase)
		if t < 0.46:
			var side := 1.0 if p.x >= 0.0 else -1.0
			p = _rot_x(p, hip_y, swing * side * amp)
		elif t < 0.80 and absf(p.x) > arm_x:
			var side := 1.0 if p.x >= 0.0 else -1.0
			p = _rot_x(p, shoulder_y, -swing * side * amp * 0.65)
		p.y += sin(phase * 2.0) * _span * 0.018 * clampf(t, 0.0, 1.0)
	elif pose == "jump":
		if t < 0.48:
			var k := (0.48 - t) / 0.48
			p.y += _span * 0.22 * k
			p.z += _span * 0.08 * k
		else:
			p.y = hip_y + (p.y - hip_y) * 1.08
	elif pose == "fall":
		if t < 0.48:
			var k := (0.48 - t) / 0.48
			p.z += _span * 0.18 * k
			p.y -= _span * 0.02 * k
		else:
			p.y = hip_y + (p.y - hip_y) * 1.06
	elif pose == "land":
		var u := clampf(t, 0.0, 1.0)
		p.y = _y_min + u * _span * 0.68
		p.x *= 1.16
		p.z *= 1.10
	else:
		if t > 0.55:
			p.y += sin(phase) * _span * 0.045 * (t - 0.55) / 0.45
	return p


func _bind(mi: MeshInstance3D) -> void:
	var parts := _collect_parts(mi)
	if not parts.is_empty():
		_bind_parts(parts)
		return
	_part_binds = []
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() < 1:
		return
	var id := mesh.get_instance_id()
	if id == _mesh_id and not _rest.is_empty():
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	_mesh_id = id
	_rest = verts.duplicate()
	_normals = arrays[Mesh.ARRAY_NORMAL]
	_colors = arrays[Mesh.ARRAY_COLOR]
	_indices = arrays[Mesh.ARRAY_INDEX]
	_measure(verts)


func _bind_parts(parts: Array) -> void:
	var first: MeshInstance3D = parts[0]
	var mesh := first.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() < 1:
		_part_binds = []
		return
	var id := mesh.get_instance_id()
	if id == _mesh_id and _part_binds.size() == parts.size():
		return
	_mesh_id = id
	_rest = PackedVector3Array()
	_part_binds = []
	var all := PackedVector3Array()
	for part_mi in parts:
		var pm := (part_mi as MeshInstance3D).mesh as ArrayMesh
		if pm == null or pm.get_surface_count() < 1:
			continue
		var arrays: Array = pm.surface_get_arrays(0)
		var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if rest.is_empty():
			continue
		var copy := rest.duplicate()
		_part_binds.append({
			"mi": part_mi,
			"rest": copy,
			"normals": arrays[Mesh.ARRAY_NORMAL],
			"colors": arrays[Mesh.ARRAY_COLOR],
			"indices": arrays[Mesh.ARRAY_INDEX],
		})
		for v in copy:
			all.push_back(v)
	_measure(all)


func _collect_parts(root: MeshInstance3D) -> Array:
	var skel := root.get_node_or_null("PlayerRig")
	if skel == null:
		return []
	var out: Array = []
	for att in skel.get_children():
		for ch in att.get_children():
			if ch is MeshInstance3D:
				out.append(ch)
	return out


func _measure(verts: PackedVector3Array) -> void:
	var lo := 1.0e9
	var hi := -1.0e9
	var max_x := 0.0
	for p in verts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		max_x = maxf(max_x, absf(p.x))
	_y_min = lo
	_span = maxf(hi - lo, 0.001)
	_max_abs_x = maxf(max_x, 0.001)


func _write_mesh(mi: MeshInstance3D, posed: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = posed
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _rot_x(p: Vector3, pivot_y: float, angle: float) -> Vector3:
	var dy := p.y - pivot_y
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(p.x, pivot_y + dy * c - p.z * s, dy * s + p.z * c)
