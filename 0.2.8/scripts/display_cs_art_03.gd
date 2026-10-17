extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Types = preload("res://helpers/voxel_types.gd")
const _Quality = preload("res://config/performance_quality_config.gd")
const _Light = preload("res://helpers/scene_lighting.gd")
const _Terrain = preload("res://helpers/terrain_lighting.gd")
const _Mat = preload("res://shaders/ChunkSurfaceMesh.tres")

var _cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-03 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-03")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_Terrain.apply_preset(int(_Quality.Preset.MEDIUM))
	RenderingServer.global_shader_parameter_set("cutaway_enabled", 0.0)
	_stage()
	_terrain()
	_caster()
	await _aim(Vector3(6.0, 4.0, 6.0))
	await _Probe.capture_step("cs-art-03-%s-depth" % phase)
	print("CS ART 03 SHOTS %s" % phase)
	quit(0)


func _stage() -> void:
	var host := Node3D.new()
	host.name = "Game"
	root.add_child(host)
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.72, 0.84)
	world_env.environment = env
	host.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.light_color = Color(0.72, 0.78, 0.9, 1)
	light.light_energy = 0.58
	var locked := Basis(
		Vector3(0.568432, 0.0, -0.82273),
		Vector3(-0.637673, 0.631876, -0.440574),
		Vector3(0.519864, 0.775069, 0.359179)
	)
	light.transform = Transform3D(locked, Vector3.ZERO)
	host.add_child(light)
	_Light.apply_host(host, _Quality.apply_preset(_Quality.Preset.MEDIUM))
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 16.0
	_cam.far = 520.0
	_cam.current = true
	root.add_child(_cam)


func _terrain() -> void:
	var data = _ChunkData.new(Vector2i.ZERO)
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			data.patch_local_column(x, z, 0.0, _Types.GRASSLAND)
	var quads: Array = []
	for x in 6:
		for z in 6:
			var raised := x >= 2 and x <= 3 and z >= 2 and z <= 3
			var top := 4.0 if raised else 0.0
			data.patch_local_column(x, z, top, _Types.GRASSLAND if not raised else _Types.STONE)
			quads.append(_quad(x, z, top, 0, 1.0))
			if not raised:
				continue
			for face in [3, 4, 5, 6]:
				quads.append(_quad(x, z, 2.0, face, 2.0))
	var built: Dictionary = _Builder.build_surface_arrays_from_terrain_quads(data, quads)
	var mesh := _Builder.build_array_mesh(built)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _Mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("texture_atlas", load("res://assets/tiles/Cube.png"))
	mat.set_shader_parameter("atlas_grid", Vector2(7, 10))
	mi.material_override = mat
	root.add_child(mi)


func _quad(x: int, z: int, y: float, face: int, dim_y: float) -> Dictionary:
	return {
		"x": x,
		"z": z,
		"y": y,
		"dim_x": 1.0,
		"dim_y": dim_y,
		"dim_z": 1.0,
		"face_code": face,
		"type": _Types.STONE if y > 0.5 else _Types.GRASSLAND,
	}


func _caster() -> void:
	var body := MeshInstance3D.new()
	body.name = "Caster"
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 4.2, 1.8)
	body.mesh = box
	body.position = Vector3(11.0, 6.2, 6.5)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.72, 0.38)
	body.material_override = mat
	root.add_child(body)


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	var lift := 101.0
	_cam.position = focus + Vector3(sin(yaw) * hdist, lift, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 20:
		await process_frame
