extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _Mesh = preload("res://helpers/main_crystal_mesh.gd")
const _Palette = preload("res://ui/crystal_palette.gd")

var _cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-05 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-05")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage()
	_ground()
	var marker_size := 1.6
	var anchor := Node3D.new()
	anchor.name = "SpawnMarker"
	anchor.position = Vector3(1.0, 0.92, 1.0)
	root.add_child(anchor)
	if phase == "before":
		_pink_cube(anchor, marker_size)
	else:
		_Mesh.attach(anchor, marker_size, false)
	_hp_bar(anchor, marker_size)
	await _aim(anchor.position + Vector3(0.0, marker_size * 0.35, 0.0))
	await _Probe.capture_step("cs-art-05-%s-main-crystal" % phase)
	print("CS ART 05 SHOTS %s" % phase)
	quit(0)


func _pink_cube(anchor: Node3D, marker_size: float) -> void:
	var prism := MeshInstance3D.new()
	prism.name = "FallbackPrism"
	var box := BoxMesh.new()
	box.size = Vector3(marker_size, marker_size * 1.4, marker_size)
	prism.mesh = box
	var pmat := StandardMaterial3D.new()
	pmat.emission_enabled = true
	_Palette.paint_mass(pmat, false)
	pmat.emission_energy_multiplier = 2.0
	prism.material_override = pmat
	prism.position.y = marker_size * 0.15
	anchor.add_child(prism)


func _hp_bar(anchor: Node3D, marker_size: float) -> void:
	var vs := 2.0
	var width := vs * 1.1
	var height := vs * 0.14
	var bg := MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(width, height, vs * 0.08)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.08, 0.05, 0.12, 0.92)
	bg.material_override = bg_mat
	bg.position = Vector3(0.0, marker_size * 1.25, 0.0)
	anchor.add_child(bg)
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(width * 0.92, height * 0.62, vs * 0.1)
	fill.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = _Palette.spawn_fill(false, false, false)
	fill.material_override = fill_mat
	fill.position = Vector3(0.0, marker_size * 1.25, vs * 0.02)
	anchor.add_child(fill)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.16, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.4, 0.5)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 0.85
	root.add_child(light)
	light.look_at_from_position(Vector3(6.0, 10.0, 4.0), Vector3(1.0, 1.2, 1.0), Vector3.UP)
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 8.0
	_cam.current = true
	root.add_child(_cam)


func _ground() -> void:
	var vs := 2.0
	for x in range(-1, 3):
		for z in range(-1, 3):
			var box := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(vs, 0.4, vs)
			box.mesh = mesh
			box.position = Vector3((float(x) + 0.5) * vs, 0.2, (float(z) + 0.5) * vs)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.72, 0.22, 0.85) if abs(x) + abs(z) < 2 else Color(0.34, 0.3, 0.28)
			mat.emission_enabled = abs(x) + abs(z) < 2
			mat.emission = Color(0.45, 0.12, 0.7)
			mat.emission_energy_multiplier = 0.4
			box.material_override = mat
			root.add_child(box)


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	_cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 8:
		await process_frame
