extends SceneTree
## t543u: full tree voxel (LOD0) vs simplified (LOD1) vs coarse silhouette under pixel look.
## Env: CS_TREE_MESH_MODE=full|simple|silhouette
##      CS_PIXEL_HEIGHT=216|270|360  CS_PIXEL_RENDER=1
##      CS_TREE_INSTANCES=256  CRYSTALSTORM_SCRATCH=outdir

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _PixelLook = preload("res://helpers/pixel_look.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const TREE_FULL := "res://assets/voxel/vegetation/lod/tree_oak_v0_s2_lod0.json"
const TREE_SIMPLE := "res://assets/voxel/vegetation/lod/tree_oak_v0_s2_lod1.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if out.is_empty():
		out = OS.get_user_data_dir().path_join("pixel_tree_lod")
	DirAccess.make_dir_recursive_absolute(out)

	var mode := OS.get_environment("CS_TREE_MESH_MODE").strip_edges().to_lower()
	if mode.is_empty():
		mode = "full"
	var height := int(OS.get_environment("CS_PIXEL_HEIGHT"))
	if height <= 0:
		height = _PixelLook.DEFAULT_HEIGHT
	var instances := int(OS.get_environment("CS_TREE_INSTANCES"))
	if instances <= 0:
		instances = 256

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Engine.max_fps = 0
	for _i in 5:
		await process_frame

	_Loader.drop_memory()
	var mesh: ArrayMesh
	var path := ""
	if mode == "silhouette":
		mesh = _make_silhouette_mesh()
		path = "procedural_silhouette"
	elif mode == "simple":
		path = TREE_SIMPLE
		mesh = _Loader.mesh_for(path)
	else:
		mode = "full"
		path = TREE_FULL
		mesh = _Loader.mesh_for(path)

	var quads_per := _Loader.quad_count(mesh) if mode != "silhouette" else _count_quads(mesh)
	var mesh_bytes := _mesh_bytes(mesh)
	print(
		"TREE_MESH mode=%s path=%s quads_per=%d mesh_bytes=%d instances=%d vsync=%d"
		% [mode, path.get_file() if path.begins_with("res://") else path, quads_per, mesh_bytes, instances, int(DisplayServer.window_get_vsync_mode())]
	)

	var holder := Node3D.new()
	holder.name = "TreeLodMeasureRoot"
	root.add_child(holder)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = instances
	var cols := int(ceil(sqrt(float(instances))))
	var spacing := 6.0
	for i in instances:
		var x := float(i % cols) * spacing
		var z := float(int(i / cols)) * spacing
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TreeForest"
	mmi.multimesh = mm
	holder.add_child(mmi)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(cols * spacing * 0.75, 24.0)
	cam.near = 0.05
	cam.far = 500.0
	var center := Vector3((cols - 1) * spacing * 0.5, 8.0, (cols - 1) * spacing * 0.5)
	cam.global_position = center + Vector3(28.0, 36.0, 28.0)
	cam.look_at(center, Vector3.UP)
	cam.add_to_group("camera")
	cam.current = true
	holder.add_child(cam)

	OS.set_environment("CS_PIXEL_RENDER", "1")
	OS.set_environment("CS_PIXEL_HEIGHT", str(height))
	var ctrl := Node.new()
	ctrl.name = "PixelLookController"
	ctrl.set_script(load("res://systems/pixel_look_controller.gd"))
	ctrl.set("enabled", true)
	ctrl.set("internal_height", height)
	ctrl.set("banding", false)
	ctrl.set("outline", false)
	ctrl.process_priority = -50
	holder.add_child(ctrl)
	ctrl.call("install", holder)
	for _w in 45:
		await process_frame

	var internal := Vector2i.ZERO
	if ctrl.has_method("get_internal_size"):
		internal = ctrl.call("get_internal_size")
	print("TREE_PIXEL height=%d internal=%sx%s" % [height, internal.x, internal.y])

	for _w in 120:
		await process_frame
	var n := 180
	var sum_ms := 0.0
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		samples[i] = dt
		sum_ms += dt
	var mean_ms := sum_ms / float(n)
	var sorted := samples.duplicate()
	sorted.sort()
	var p50 := sorted[int(n * 0.50)]
	var p95 := sorted[mini(n - 1, int(n * 0.95))]
	var fps := 1000.0 / maxf(mean_ms, 0.001)

	var mem_static := float(Performance.get_monitor(Performance.MEMORY_STATIC))
	var mem_static_max := float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var total_quads := quads_per * instances
	var total_tris := total_quads * 2
	if prim <= 0:
		prim = total_tris

	var report := {
		"mode": mode,
		"path": path,
		"height": height,
		"internal_w": internal.x,
		"internal_h": internal.y,
		"instances": instances,
		"quads_per_tree": quads_per,
		"quads_total": total_quads,
		"tris_total": total_tris,
		"mesh_bytes": mesh_bytes,
		"instance_xform_bytes_est": instances * 48,
		"frame_mean_ms": mean_ms,
		"frame_p50_ms": p50,
		"frame_p95_ms": p95,
		"fps": fps,
		"mem_static_mb": mem_static / (1024.0 * 1024.0),
		"mem_static_max_mb": mem_static_max / (1024.0 * 1024.0),
		"draw_calls": draw,
		"primitives": prim,
		"vsync": int(DisplayServer.window_get_vsync_mode()),
	}
	var line := (
		"TREE_LOD_SAMPLE mode=%s height=%d internal=%dx%d instances=%d quads_per=%d quads=%d tris=%d mesh_bytes=%d mean_ms=%.3f p50=%.3f p95=%.3f fps=%.2f mem_mb=%.2f mem_max_mb=%.2f draw=%d prim=%d vsync=%d"
		% [
			mode, height, internal.x, internal.y, instances, quads_per, total_quads, total_tris, mesh_bytes,
			mean_ms, p50, p95, fps,
			report["mem_static_mb"], report["mem_static_max_mb"], draw, prim, report["vsync"],
		]
	)
	print(line)
	var txt := FileAccess.open(out.path_join("sample.txt"), FileAccess.WRITE)
	if txt:
		txt.store_string(line + "\n")
		txt.close()
	var jf := FileAccess.open(out.path_join("sample.json"), FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(report, "\t"))
		jf.close()
	print("WROTE %s" % out.path_join("sample.json"))
	_ProbeExit.finish_tree(self, 0, "TREE_LOD_MEASURE_OK")


func _make_silhouette_mesh() -> ArrayMesh:
	## Coarse same-palette stand-in: trunk + canopy boxes (silhouette/colour only).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(0.45, 0.28, 0.14)
	var leaf := Color(0.22, 0.48, 0.18)
	_box(st, Vector3(0, 1.5, 0), Vector3(0.7, 3.0, 0.7), trunk)
	_box(st, Vector3(0, 5.0, 0), Vector3(4.5, 3.5, 4.5), leaf)
	_box(st, Vector3(0, 7.2, 0), Vector3(3.0, 2.2, 3.0), leaf)
	st.generate_normals()
	return st.commit()


func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := center
	var v := [
		c + Vector3(-hx, -hy, -hz),
		c + Vector3(hx, -hy, -hz),
		c + Vector3(hx, hy, -hz),
		c + Vector3(-hx, hy, -hz),
		c + Vector3(-hx, -hy, hz),
		c + Vector3(hx, -hy, hz),
		c + Vector3(hx, hy, hz),
		c + Vector3(-hx, hy, hz),
	]
	var faces := [
		[0, 1, 2, 3],
		[5, 4, 7, 6],
		[4, 0, 3, 7],
		[1, 5, 6, 2],
		[3, 2, 6, 7],
		[4, 5, 1, 0],
	]
	for f in faces:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], color)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(c)
	st.set_color(color)
	st.add_vertex(d)


func _count_quads(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			tris += (idx as PackedInt32Array).size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			tris += verts.size() / 3
	return tris / 2


func _mesh_bytes(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var cols = arrays[Mesh.ARRAY_COLOR]
		var idx = arrays[Mesh.ARRAY_INDEX]
		total += verts.size() * 12
		if norms is PackedVector3Array:
			total += (norms as PackedVector3Array).size() * 12
		if uvs is PackedVector2Array:
			total += (uvs as PackedVector2Array).size() * 8
		if cols is PackedColorArray:
			total += (cols as PackedColorArray).size() * 16
		if idx is PackedInt32Array:
			total += (idx as PackedInt32Array).size() * 4
	return total
