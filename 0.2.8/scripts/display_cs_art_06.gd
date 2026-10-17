extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _Highlight = preload("res://player/target_highlight.gd")

var _cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-06 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-06")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage()
	_ground()
	if phase == "before":
		_legacy_pair()
	else:
		_live_pair()
	await _aim(Vector3(5.0, 2.2, 2.4))
	await _Probe.capture_step("cs-art-06-%s-dig-build" % phase)
	print("CS ART 06 SHOTS %s" % phase)
	quit(0)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 0.9
	root.add_child(light)
	light.look_at_from_position(Vector3(8.0, 12.0, 6.0), Vector3(5.0, 2.0, 2.0), Vector3.UP)
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 14.0
	_cam.current = true
	root.add_child(_cam)


func _ground() -> void:
	for x in range(0, 6):
		for z in range(0, 4):
			var box := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(2.0, 1.2, 2.0)
			box.mesh = mesh
			box.position = Vector3(float(x) * 2.0 + 1.0, 0.6, float(z) * 2.0 + 1.0)
			var mat := StandardMaterial3D.new()
			var shade := 0.34 + 0.04 * float((x + z) % 2)
			mat.albedo_color = Color(shade, shade * 0.96, shade * 0.9)
			box.material_override = mat
			root.add_child(box)


func _legacy_pair() -> void:
	_legacy_marker(Vector3(3.0, 2.2, 2.0), Color(1.0, 0.52, 0.1, 0.4), Color(1.0, 0.45, 0.05), Color(1.0, 0.25, 0.95, 1.0), Color(1.0, 0.2, 0.9), 1.6, 0.055)
	_legacy_marker(Vector3(7.0, 3.4, 2.0), Color(0.25, 1.0, 0.4, 0.55), Color(0.2, 0.95, 0.35), Color(1.0, 0.25, 0.95, 1.0), Color(1.0, 0.2, 0.9), 1.1, 0.055)
	_legacy_marker(Vector3(5.0, 2.2, 4.2), Color(0.25, 1.0, 0.4, 0.55), Color(0.2, 0.95, 0.35), Color(0.25, 1.0, 0.4, 1.0), Color(0.2, 0.95, 0.35), 0.7, 0.04)
	_legacy_marker(Vector3(7.0, 2.2, 4.2), Color(0.25, 1.0, 0.4, 0.55), Color(0.2, 0.95, 0.35), Color(0.25, 1.0, 0.4, 1.0), Color(0.2, 0.95, 0.35), 0.7, 0.04)
	_legacy_marker(Vector3(9.0, 2.2, 4.2), Color(0.25, 1.0, 0.4, 0.55), Color(0.2, 0.95, 0.35), Color(0.25, 1.0, 0.4, 1.0), Color(0.2, 0.95, 0.35), 0.7, 0.04)


func _live_pair() -> void:
	_live_marker(&"dig", Vector3(3.0, 2.2, 2.0), false)
	_live_marker(&"build", Vector3(7.0, 3.4, 2.0), true)


func _live_marker(mode: StringName, at: Vector3, with_ghost: bool) -> void:
	var hl = _Highlight.new()
	hl.name = "LiveMarker"
	root.add_child(hl)
	hl.set_process(false)
	hl._mesh.visible = true
	hl._mesh.global_position = at
	hl._mesh.scale = Vector3(2.06, 2.0, 2.06)
	hl._paint_marker(mode, 0.7, 0.0, false)
	if not with_ghost:
		return
	hl.show_structure_ghost([
		{"valid": true, "position": Vector3(5.0, 2.2, 4.2)},
		{"valid": true, "position": Vector3(7.0, 2.2, 4.2)},
		{"valid": true, "position": Vector3(9.0, 2.2, 4.2)},
	])


func _legacy_marker(at: Vector3, fill: Color, glow: Color, edge: Color, edge_glow: Color, energy: float, thickness: float) -> void:
	var root_box := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	root_box.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.emission_enabled = true
	mat.albedo_color = fill
	mat.emission = glow
	mat.emission_energy_multiplier = energy
	root_box.material_override = mat
	root_box.scale = Vector3(2.06, 2.0, 2.06)
	root_box.position = at
	root_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var outline := MeshInstance3D.new()
	outline.mesh = _edge_mesh(thickness)
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.cull_mode = BaseMaterial3D.CULL_DISABLED
	emat.no_depth_test = true
	emat.emission_enabled = true
	emat.albedo_color = edge
	emat.emission = edge_glow
	emat.emission_energy_multiplier = 1.6
	outline.material_override = emat
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_box.add_child(outline)
	root.add_child(root_box)


func _edge_mesh(thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.5
	var corners: Array[Vector3] = [
		Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(-h, -h, h),
		Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h),
	]
	var edges: Array[int] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	for i in range(0, edges.size(), 2):
		var a: Vector3 = corners[edges[i]]
		var b: Vector3 = corners[edges[i + 1]]
		var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3(thickness, thickness, thickness)
		var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3(thickness, thickness, thickness)
		_add_box(st, lo, hi)
	return st.commit()


func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var p: Array[Vector3] = [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var quads: Array[int] = [
		0, 1, 2, 3, 5, 4, 7, 6, 4, 0, 3, 7, 1, 5, 6, 2, 3, 2, 6, 7, 4, 5, 1, 0,
	]
	for i in range(0, quads.size(), 4):
		st.add_vertex(p[quads[i]])
		st.add_vertex(p[quads[i + 1]])
		st.add_vertex(p[quads[i + 2]])
		st.add_vertex(p[quads[i]])
		st.add_vertex(p[quads[i + 2]])
		st.add_vertex(p[quads[i + 3]])


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	_cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 8:
		await process_frame
