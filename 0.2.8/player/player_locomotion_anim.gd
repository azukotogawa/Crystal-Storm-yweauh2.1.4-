extends RefCounted
## Poses the extruded scout from the movement state.
## The mesh is one shell. Each pose rewrites vertices from the rest capture,
## so the feet stay planted at rest and a landing squash does not lift them.
## This is not the juice walk-bob, which only scaled the whole node.

var _mesh_id: int = 0
var _rest := PackedVector3Array()
var _normals: PackedVector3Array
var _colors: PackedColorArray
var _indices: PackedInt32Array
var _y_min: float = 0.0
var _span: float = 1.0
var _max_abs_x: float = 1.0


func apply(mi: MeshInstance3D, pose: String, phase: float) -> void:
	if mi == null:
		return
	_bind(mi)
	if _rest.is_empty() or _span < 0.001:
		return
	var posed := _rest.duplicate()
	var hip_y := _y_min + _span * 0.46
	var shoulder_y := _y_min + _span * 0.72
	var arm_x := _max_abs_x * 0.55
	var n := posed.size()
	for i in n:
		var p: Vector3 = _rest[i]
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
		posed[i] = p
	_write(mi, posed)


func _bind(mi: MeshInstance3D) -> void:
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
	var lo := 1.0e9
	var hi := -1.0e9
	var max_x := 0.0
	for p in _rest:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		max_x = maxf(max_x, absf(p.x))
	_y_min = lo
	_span = maxf(hi - lo, 0.001)
	_max_abs_x = maxf(max_x, 0.001)


func _write(mi: MeshInstance3D, posed: PackedVector3Array) -> void:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = posed
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _rot_x(p: Vector3, pivot_y: float, angle: float) -> Vector3:
	var dy := p.y - pivot_y
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(p.x, pivot_y + dy * c - p.z * s, dy * s + p.z * c)
