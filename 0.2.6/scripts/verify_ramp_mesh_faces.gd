extends SceneTree
## Regression: all cardinal/corner ramps derive from west/WN reference face layouts.


const _VoxelPrimitiveMeshes = preload("res://helpers/voxel_primitive_meshes.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_TerrainRamps.invalidate_mesh_cache()

	var s: float = _VoxelPrimitiveMeshes._s()
	var west_faces: Array = _VoxelPrimitiveMeshes._cardinal_west_faces(s)
	var wn_faces: Array = _VoxelPrimitiveMeshes._corner_wn_faces(s)

	var west_tris := _face_triangle_count(west_faces)
	var wn_tris := _face_triangle_count(wn_faces)
	if west_tris != 8:
		push_error("west cardinal reference must have 8 triangles, got %d" % west_tris)
		failed = true
	else:
		print("OK west cardinal reference tris=%d" % west_tris)
	if wn_tris != 10:
		push_error("WN corner reference must have 10 triangles, got %d" % wn_tris)
		failed = true
	else:
		print("OK WN corner reference tris=%d" % wn_tris)

	for toward_low in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var mesh := _VoxelPrimitiveMeshes.get_cardinal_ramp_mesh(toward_low)
		if _mesh_triangle_count(mesh) != west_tris:
			push_error("cardinal %s triangle count mismatch" % toward_low)
			failed = true
		else:
			print("OK cardinal %s derived tris=%d" % [toward_low, west_tris])

	for legs in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var hx: int = legs.x
		var hz: int = legs.y
		var dir_a := Vector2i(hx, 0)
		var dir_b := Vector2i(0, hz)
		var mesh := _VoxelPrimitiveMeshes.get_corner_ramp_mesh(dir_a, dir_b)
		if _mesh_triangle_count(mesh) != wn_tris:
			push_error("corner legs %s triangle count mismatch" % legs)
			failed = true
		else:
			print("OK corner legs %s derived tris=%d" % [legs, wn_tris])

	var nw_faces: Array = _VoxelPrimitiveMeshes._concave_nw_faces(s)
	var ref_up_floor := false
	for face in nw_faces:
		if face["kind"] == &"tri" and face["normal"].is_equal_approx(Vector3.UP):
			ref_up_floor = true
	if not ref_up_floor:
		push_error("concave NW reference must include upward interior floor tri")
		failed = true
	else:
		print("OK concave NW reference up floor")

	for legs in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var concave: Mesh = _VoxelPrimitiveMeshes.get_concave_mesh(legs.x, legs.y)
		var concave_tris := _mesh_triangle_count(concave)
		if concave_tris != 8:
			push_error("concave legs %s must have 8 triangles, got %d" % [legs, concave_tris])
			failed = true
		else:
			print("OK concave legs %s tris=%d" % [legs, concave_tris])

	if failed:
		print("Ramp mesh face tests FAILED")
		quit(1)
		return
	print("All ramp mesh face tests OK")
	quit(0)


func _face_triangle_count(faces: Array) -> int:
	var n := 0
	for face in faces:
		n += 2 if face["kind"] == &"quad" else 1
	return n


func _mesh_triangle_count(mesh: Mesh) -> int:
	return int(mesh.get_faces().size() / 3)


func _face_normal(face: PackedVector3Array) -> Vector3:
	if face.size() < 3:
		return Vector3.ZERO
	return (face[1] - face[0]).cross(face[2] - face[0]).normalized()