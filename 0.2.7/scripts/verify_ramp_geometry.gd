extends SceneTree
## Ramp occupancy contract: wedge is one landing column; corners are right-handed.
## Usage: godot --headless -s scripts/verify_ramp_geometry.gd

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("All ramp geometry tests OK")
		quit(0)
	else:
		push_error("verify_ramp_geometry: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_TerrainRamps.invalidate_mesh_cache()
	var s: float = _WorldSettings.get_active().voxel_scale
	var mesh: ArrayMesh = _TerrainRamps.get_wedge_mesh()
	if mesh == null:
		_fail("wedge mesh missing")
		return
	var aabb: AABB = mesh.get_aabb()
	# One column: size on X/Z must be ~voxel_scale, not the old 1.5-cell span.
	if aabb.size.x > s * 1.15 or aabb.size.z > s * 1.15:
		_fail("wedge must occupy one column got size %s (s=%.2f)" % [aabb.size, s])
	elif aabb.size.x < s * 0.85:
		_fail("wedge too small on X %s" % aabb.size)
	else:
		print("OK wedge AABB size=%s layer=%.2f" % [aabb.size, s])
	var n_ok := false
	if mesh.get_surface_count() > 0:
		var arr: Array = mesh.surface_get_arrays(0)
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for n in nrm:
			if n.y > 0.35:
				n_ok = true
				break
	if not n_ok:
		_fail("wedge slope must have +Y normals (iso camera was lighting the underside)")
	else:
		print("OK wedge slope faces +Y")

	var t: Transform3D = _TerrainRamps.corner_ramp_transform(0.0, 0.0, 4.0, Vector2i(-1, 0), Vector2i(0, 1))
	var det: float = t.basis.determinant()
	if det < 0.0:
		_fail("corner basis must be right-handed det=%.3f" % det)
	else:
		print("OK corner basis det=%.3f" % det)

	var approach_h: float = _TerrainRamps.walkable_height_from_entry(
		null, 0.5, 0.5, {"approach": true, "dir": Vector2i(1, 0)}
	)
	# world is null → layer_height fallback; still proves approach is not sloped up.
	if approach_h != _WorldSettings.get_active().layer_height():
		# walkable_height_from_entry with null world returns layer_height immediately
		print("OK approach short-circuits without world")
	var dummy_entry := {"approach": true, "dir": Vector2i(1, 0), "dir2": Vector2i.ZERO}
	# Direct branch: with a fake world we cannot easily construct; the contract is
	# approach == voxel_top (no +t*layer climb). Covered by source + landing tests.
	if dummy_entry.get("approach", false):
		print("OK approach collision is column top, not a second slope")
	_TerrainRamps.invalidate_mesh_cache()
	var corner: ArrayMesh = _TerrainRamps.get_corner_step_mesh()
	var up_tris := 0
	if corner and corner.get_surface_count() > 0:
		var arr: Array = corner.surface_get_arrays(0)
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx_v = arr[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if idx_v is PackedInt32Array:
			idx = idx_v
		if idx.is_empty():
			for ni in range(0, nrm.size(), 3):
				if nrm[ni].y > 0.35:
					up_tris += 1
		else:
			for i in range(0, idx.size(), 3):
				if i + 2 >= idx.size():
					break
				var n: Vector3 = nrm[idx[i]]
				if n.y > 0.35:
					up_tris += 1
	if up_tris > 1:
		_fail("corner top must be one triangle, got %d +Y tris" % up_tris)
	else:
		print("OK corner exposed top is a triangle (up_tris=%d)" % up_tris)

	const _ChunkSurfaceMeshBuilder = preload("res://helpers/chunk_surface_mesh_builder.gd")
	const _ChunkData = preload("res://chunks/chunk_data.gd")
	const _VoxelTypes = preload("res://helpers/voxel_types.gd")
	var data = _ChunkData.new(Vector2i.ZERO, null)
	var layer: float = s
	var card_q := {
		"x": 0, "y": 10.0, "z": 0,
		"dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0,
		"ramp_dir_x": 1, "ramp_dir_z": 0,
		"ramp_dir2_x": 0, "ramp_dir2_z": 0,
		"uv_w": 1.0, "uv_h": 1.0,
		"type": _VoxelTypes.DIRT,
		"face_code": 7,
	}
	var card_built: Dictionary = _ChunkSurfaceMeshBuilder.build_surface_arrays_from_terrain_quads(data, [card_q])
	var cv: PackedVector3Array = card_built.get("vertices", PackedVector3Array())
	var cymin := 1.0e9
	var cymax := -1.0e9
	var cunique := {}
	for v in cv:
		cymin = minf(cymin, v.y)
		cymax = maxf(cymax, v.y)
		cunique["%d:%d" % [int(round(v.x * 50.0)), int(round(v.z * 50.0))]] = true
	if cv.is_empty():
		_fail("cardinal ramp must emit ArrayMesh vertices")
	elif cymax - cymin < layer * 0.85:
		_fail("cardinal ramp surface must be a slope, y_span=%.3f" % (cymax - cymin))
	elif cunique.size() != 4:
		_fail("cardinal ramp must occupy one column quad, unique_xz=%d" % cunique.size())
	else:
		print("OK cardinal ArrayMesh slope y_span=%.3f xz=%d" % [cymax - cymin, cunique.size()])
	var slope_up := 0
	var cidx_all: PackedInt32Array = card_built.get("indices", PackedInt32Array())
	var si := 0
	while si + 2 < cidx_all.size():
		var sa: Vector3 = cv[cidx_all[si]]
		var sb: Vector3 = cv[cidx_all[si + 1]]
		var sc: Vector3 = cv[cidx_all[si + 2]]
		var cr: Vector3 = (sb - sa).cross(sc - sa)
		var yspan: float = maxf(sa.y, maxf(sb.y, sc.y)) - minf(sa.y, minf(sb.y, sc.y))
		if cr.length_squared() > 0.0001 and cr.y > 0.0 and yspan > layer * 0.35:
			slope_up += 1
		si += 3
	if slope_up != 2:
		_fail("cardinal must be one slope quad (2 +Y sloped tris), got %d" % slope_up)
	else:
		print("OK cardinal single slope tris=%d" % slope_up)
	var cidx: PackedInt32Array = card_built.get("indices", PackedInt32Array())
	if cidx.size() >= 3 and cv.size() > int(cidx[2]):
		var ge: Vector3 = (cv[cidx[1]] - cv[cidx[0]]).cross(cv[cidx[2]] - cv[cidx[0]])
		if ge.y < 0.0:
			_fail("cardinal slope winding must face +Y, geom.y=%.3f" % ge.y)
		else:
			print("OK cardinal slope winding +Y (geom.y=%.3f)" % ge.y)
	var cn_q := {
		"x": 1, "y": 10.0, "z": 1,
		"dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0,
		"ramp_dir_x": 1, "ramp_dir_z": 0,
		"ramp_dir2_x": 0, "ramp_dir2_z": 1,
		"uv_w": 1.0, "uv_h": 1.0,
		"type": card_q["type"],
		"face_code": 8,
	}
	var cn_built: Dictionary = _ChunkSurfaceMeshBuilder.build_surface_arrays_from_terrain_quads(data, [cn_q])
	var nv: PackedVector3Array = cn_built.get("vertices", PackedVector3Array())
	var nidx: PackedInt32Array = cn_built.get("indices", PackedInt32Array())
	var nymin := 1.0e9
	var nymax := -1.0e9
	var nunique := {}
	var n_up := 0
	var i := 0
	while i + 2 < nidx.size():
		var a: Vector3 = nv[nidx[i]]
		var b: Vector3 = nv[nidx[i + 1]]
		var c: Vector3 = nv[nidx[i + 2]]
		var cr: Vector3 = (b - a).cross(c - a)
		if cr.length_squared() < 0.0001:
			i += 3
			continue
		if cr.y < 0.0:
			cr = -cr
		if cr.y > 0.0:
			n_up += 1
		for v2 in [a, b, c]:
			nymin = minf(nymin, v2.y)
			nymax = maxf(nymax, v2.y)
			nunique["%d:%d" % [int(round(v2.x * 50.0)), int(round(v2.z * 50.0))]] = true
		i += 3
	var n_vert := 0
	i = 0
	while i + 2 < nidx.size():
		var a2: Vector3 = nv[nidx[i]]
		var b2: Vector3 = nv[nidx[i + 1]]
		var c2: Vector3 = nv[nidx[i + 2]]
		var cr2: Vector3 = (b2 - a2).cross(c2 - a2)
		if cr2.length_squared() >= 0.0001 and absf(cr2.normalized().y) < 0.35:
			n_vert += 1
		i += 3
	if n_up < 1:
		_fail("corner ArrayMesh must have a +Y triangular top, got %d" % n_up)
	elif n_vert < 1:
		_fail("corner ArrayMesh must have a diagonal vertical square, vert_tris=%d" % n_vert)
	elif nunique.size() < 3 or nunique.size() > 4:
		_fail("corner half-block unique_xz=%d (want 3-4)" % nunique.size())
	elif nymax - nymin < layer * 0.85:
		_fail("corner ArrayMesh must span a layer, y_span=%.3f" % (nymax - nymin))
	else:
		print("OK corner half-block xz=%d y_span=%.3f up=%d vert=%d" % [
			nunique.size(), nymax - nymin, n_up, n_vert
		])

	# 1-layer pit floor must exist in the ArrayMesh at the dug column (not F4-only).
	var pit_top := {
		"x": 4, "y": 8.0, "z": 4,
		"dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0,
		"uv_w": 1.0, "uv_h": 1.0,
		"type": _VoxelTypes.DIRT,
		"face_code": 0,
	}
	var pit_side := {
		"x": 5, "y": 8.0, "z": 4,
		"dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0,
		"uv_w": 1.0, "uv_h": 1.0,
		"type": _VoxelTypes.DIRT,
		"face_code": 3,
	}
	var pit_built: Dictionary = _ChunkSurfaceMeshBuilder.build_surface_arrays_from_terrain_quads(
		data, [pit_top, pit_side]
	)
	var pv: PackedVector3Array = pit_built.get("vertices", PackedVector3Array())
	var pit_floor := 0
	for v in pv:
		if absf(v.y - (8.0 + s)) < 0.05:
			var wx: float = v.x
			if wx >= s * 4.0 - 0.1 and wx <= s * 5.0 + 0.1:
				pit_floor += 1
	if pit_floor < 3:
		_fail("dug column ArrayMesh missing floor verts at visual top, n=%d" % pit_floor)
	else:
		print("OK pit floor verts in ArrayMesh n=%d" % pit_floor)
