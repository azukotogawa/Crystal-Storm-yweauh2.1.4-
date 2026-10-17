extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _Game = preload("res://game/game_manager.gd")

var _cam: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-04 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-04")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage()
	_ground()
	var gm := _Game.new()
	gm.name = "GameManager"
	root.add_child(gm)
	var player := _Dummy.new()
	player.name = "Scout"
	root.add_child(player)
	player.global_position = Vector3(2.0, 1.05, 2.0)
	_body(player.global_position)
	gm._player = player
	gm._crystal = _Pool.new()
	gm.phase = _Game.Phase.ASSAULT
	gm._apply_crystal_damage(0.3)
	var glow := gm.get_node_or_null("BurnWarn")
	if glow == null or not glow.visible:
		push_error("cs-art-04 burn warning missing")
		quit(1)
		return
	await _aim(glow.global_position)
	await _Probe.capture_step("cs-art-04-%s-burn-pool" % phase)
	print("CS ART 04 SHOTS %s" % phase)
	quit(0)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.44, 0.48)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 0.7
	root.add_child(light)
	light.look_at_from_position(Vector3(6.0, 10.0, 4.0), Vector3(2.0, 1.0, 2.0), Vector3.UP)
	_cam = Camera3D.new()
	_cam.name = "ShotCam"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 9.0
	_cam.current = true
	root.add_child(_cam)


func _ground() -> void:
	var vs := 2.0
	for x in range(-1, 4):
		for z in range(-1, 4):
			var box := MeshInstance3D.new()
			box.name = "Stone"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(vs, 0.5, vs)
			box.mesh = mesh
			box.position = Vector3((float(x) + 0.5) * vs, 0.75, (float(z) + 0.5) * vs)
			var mat := StandardMaterial3D.new()
			var shade := 0.28 if (x + z) % 2 == 0 else 0.34
			mat.albedo_color = Color(shade, shade * 0.92, shade * 0.84)
			box.material_override = mat
			root.add_child(box)


func _body(at: Vector3) -> void:
	var box := MeshInstance3D.new()
	box.name = "ScoutBody"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 1.7, 0.7)
	box.mesh = mesh
	box.position = at + Vector3(0.0, 0.85, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.36, 0.62)
	box.material_override = mat
	root.add_child(box)


func _aim(focus: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	_cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	for _i in 8:
		await process_frame


class _Dummy extends Node3D:
	var damage_source_hint: StringName = &""

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		pass


class _Pool extends RefCounted:
	func get_depth_at(_x: int, _z: int) -> float:
		return 1.0
