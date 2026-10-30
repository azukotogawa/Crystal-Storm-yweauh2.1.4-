extends SceneTree

const _Builder = preload("res://helpers/voxel_creature_builder.gd")
const _Model = preload("res://helpers/voxel_model_builder.gd")
const _Types = preload("res://helpers/world_feature_types.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	var loaded = load("res://helpers/voxel_creature_builder.gd")
	if loaded == null:
		_fail("import voxel_creature_builder failed")
		_finish()
		return
	print("OK import voxel_creature_builder")
	var cube := _Builder.cube_edge()
	print("ART cube_edge=%.4f" % cube)
	for kind in [&"sheep", &"wolf", &"heron"]:
		_prove(kind, cube)
	_finish()


func _prove(kind: StringName, cube: float) -> void:
	var palette := _Builder.palette_for(kind)
	if palette.size() < 3:
		_fail("%s palette %d" % [kind, palette.size()])
		return
	var spread := _neighbour_spread(palette)
	print("ART kind=%s palette=%d neighbour_luma_min=%.3f neighbour_luma_max=%.3f %s" % [kind, palette.size(), float(spread.x), float(spread.y), _palette_line(palette)])
	if float(spread.x) < 0.08:
		_fail("%s neighbouring materials are too close luma=%.3f" % [kind, float(spread.x)])
	var rig := _Builder.build(kind)
	if rig == null:
		_fail("%s build returned null" % kind)
		return
	root.add_child(rig)
	var height := float(rig.get_meta("model_height", 0.0))
	var nodes := _nodes(rig)
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	var meshes := 0
	var faces := 0
	var flat_faces := 0
	var mixed_faces := 0
	var atlas := -1
	var tex_w := 0
	var tex_h := 0
	var nearest := true
	if skel != null:
		for child in skel.get_children():
			if not (child is BoneAttachment3D):
				continue
			var mi := (child as Node).get_node_or_null("Mesh") as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			meshes += 1
			var mesh := mi.mesh as ArrayMesh
			var n := _Model.face_count(mesh)
			faces += n
			var face_stat := _face_colors(mesh)
			flat_faces += int(face_stat.x)
			mixed_faces += int(face_stat.y)
			var mat := mi.material_override as StandardMaterial3D
			if mat != null:
				if mat.albedo_texture != null:
					tex_w = mat.albedo_texture.get_width()
					tex_h = mat.albedo_texture.get_height()
					atlas = 0
				if mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
					nearest = false
	print("ART kind=%s height=%.3f nodes=%d meshes=%d faces=%d flat_faces=%d mixed_faces=%d texture=%dx%d atlas=%d nearest=%s cube=%.4f" % [kind, height, nodes, meshes, faces, flat_faces, mixed_faces, tex_w, tex_h, atlas, nearest, cube])
	if height < 0.4 or height > 4.0:
		_fail("%s height %.3f" % [kind, height])
	elif nodes < 8 or meshes < 5 or faces < 24:
		_fail("%s nodes=%d meshes=%d faces=%d" % [kind, nodes, meshes, faces])
	elif mixed_faces > 0:
		_fail("%s has %d faces painted with more than one material" % [kind, mixed_faces])
	elif not nearest or tex_w != 0 or tex_h != 0 or atlas != -1:
		_fail("%s texture %dx%d atlas=%d nearest=%s" % [kind, tex_w, tex_h, atlas, nearest])
	elif float(spread.x) < 0.08:
		pass
	else:
		print("OK art %s" % kind)
	rig.free()


func _neighbour_spread(palette: PackedColorArray) -> Vector2:
	var lo := 99.0
	var hi := 0.0
	for i in range(1, palette.size() - 1):
		var d := absf(_luma(palette[i]) - _luma(palette[i + 1]))
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _palette_line(palette: PackedColorArray) -> String:
	var parts: PackedStringArray = []
	for i in range(1, palette.size()):
		parts.append("%.3f" % _luma(palette[i]))
	return "luma=" + ",".join(parts)


func _face_colors(mesh: ArrayMesh) -> Vector2:
	if mesh == null or mesh.get_surface_count() < 1:
		return Vector2.ZERO
	var arrays: Array = mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var flat := 0
	var mixed := 0
	var i := 0
	while i + 5 < idx.size():
		var first := colors[idx[i]]
		var same := true
		for k in range(1, 6):
			if colors[idx[i + k]].is_equal_approx(first) == false:
				same = false
				break
		if same:
			flat += 1
		else:
			mixed += 1
		i += 6
	return Vector2(flat, mixed)


func _nodes(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _nodes(child)
	return n


func _finish() -> void:
	if _failed == 0:
		print("ANIMAL CONTENT OK")
		quit(0)
	else:
		print("ANIMAL CONTENT FAIL %d" % _failed)
		quit(1)
