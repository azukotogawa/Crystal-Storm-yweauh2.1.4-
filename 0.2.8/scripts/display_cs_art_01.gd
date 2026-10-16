extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _Types = preload("res://helpers/crystal_types.gd")
const _Marks = preload("res://world/distant_landmarks.gd")

var _cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-01 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-01")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage()
	var crystal := _CrystalManager.new()
	crystal.name = "CrystalManager"
	crystal.cancel_bootstrap()
	crystal.set_process(false)
	root.add_child(crystal)
	await process_frame
	var cells: Array = []
	for z in range(4, 12):
		for x in range(4, 12):
			var cell := _CrystalCell.new(Vector2i(x, z), 0.0, 2.4, 1)
			cell.neighbor_mask = 15
			cells.append(cell)
	var layer := crystal._make_chunk_layer(Vector2i.ZERO)
	layer.rebuild(cells)
	await _aim(Vector3(8.0, 0.6, 8.0))
	await _Probe.capture_step("cs-art-01-%s-crystal-ground" % phase)
	layer.visible = false
	var spire := _Marks.build_visual("rock_spire")
	spire.position = Vector3(8.0, 0.0, 8.0)
	root.add_child(spire)
	var spawn := _Spawn.new(1, Vector2i(6, 8), _Types.SpawnKind.RUIN, 100.0, false)
	crystal._spawn_points.append(spawn)
	crystal._refresh_spawn_markers()
	await _aim(Vector3(7.2, 1.6, 8.0))
	await _Probe.capture_step("cs-art-01-%s-rock-spire" % phase)
	print("CS ART 01 SHOTS %s" % phase)
	quit(0)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 1.05
	root.add_child(light)
	light.look_at_from_position(Vector3(12.0, 18.0, 8.0), Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 16.0
	_cam.current = true
	root.add_child(_cam)


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	_cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 8:
		await process_frame
