extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _Builder = preload("res://helpers/voxel_creature_builder.gd")

var _cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-02 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-02")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage()
	_ground()
	_bush(Vector3(-1.7, 0.0, 0.35), Vector3(1.15, 1.35, 1.05))
	_bush(Vector3(1.55, 0.0, -0.15), Vector3(1.25, 1.55, 1.2))
	_bush(Vector3(0.15, 0.0, 1.65), Vector3(1.4, 1.15, 1.1))
	_bush(Vector3(-0.35, 0.0, -1.55), Vector3(1.05, 0.95, 1.3))
	var mite := _Builder.build(&"crystal_mite")
	if mite == null:
		push_error("cs-art-02 mite did not build")
		quit(1)
		return
	mite.position = Vector3(0.15, 0.0, 0.05)
	root.add_child(mite)
	_Builder.play(mite, "idle", 1.2)
	await _aim(Vector3(0.2, 0.55, 0.1))
	await _Probe.capture_step("cs-art-02-%s-mite-bushes" % phase)
	print("CS ART 02 SHOTS %s" % phase)
	quit(0)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.52, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.42
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 0.95
	root.add_child(light)
	light.look_at_from_position(Vector3(6.0, 10.0, 4.0), Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 16.0
	_cam.current = true
	root.add_child(_cam)


func _ground() -> void:
	var box := MeshInstance3D.new()
	box.name = "PurpleGround"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(14.0, 0.35, 14.0)
	box.mesh = mesh
	box.position = Vector3(0.0, -0.175, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.22, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(0.48, 0.14, 0.82)
	mat.emission_energy_multiplier = 0.16
	box.material_override = mat
	root.add_child(box)


func _bush(at: Vector3, size: Vector3) -> void:
	var box := MeshInstance3D.new()
	box.name = "Bush"
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at + Vector3(0.0, size.y * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.42, 0.16)
	box.material_override = mat
	root.add_child(box)


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	_cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 8:
		await process_frame
