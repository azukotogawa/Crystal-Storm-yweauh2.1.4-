extends SceneTree

const _Marks = preload("res://world/distant_landmarks.gd")
const _Sun = preload("res://helpers/terrain_lighting.gd")

const CLEAR := Color(1.0, 0.0, 1.0)
const MIN_SPAN := 0.40


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("distant landmark shot needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_DENSITY_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/density"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm distant landmarks")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage()
	var failed := false
	for kind in _Marks.KINDS:
		var node := _Marks.build_visual(kind)
		root.add_child(node)
		_aim(node)
		var span := await _span()
		var path := "%s/%s.png" % [folder, kind.replace("_", "-")]
		if not await _save(path):
			failed = true
		else:
			print("LANDMARK_SHOT=%s span=%.3f" % [path, span])
		if span < MIN_SPAN:
			push_error("%s span %.3f under %.2f of the ortho 16 frame" % [kind, span, MIN_SPAN])
			failed = true
		node.free()
	var skyline := Node3D.new()
	root.add_child(skyline)
	var x := -8.0
	for kind in _Marks.KINDS:
		var piece := _Marks.build_visual(kind)
		piece.position = Vector3(x, 0.0, 0.0)
		skyline.add_child(piece)
		x += 8.0
	_aim(skyline)
	var sky_path := "%s/skyline.png" % folder
	if not await _save(sky_path):
		failed = true
	else:
		print("LANDMARK_SHOT=%s" % sky_path)
	if failed:
		quit(1)
		return
	print("DISTANT LANDMARK WINDOW OK")
	quit(0)


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = CLEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.50)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun: Vector3 = _Sun.SUN.normalized()
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.light_energy = 1.1
	root.add_child(light)
	light.look_at_from_position(sun * 40.0, Vector3.ZERO, Vector3.UP)
	var cam := Camera3D.new()
	cam.name = "ShotCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.current = true
	root.add_child(cam)


func _aim(node: Node3D) -> void:
	var cam := root.get_node("ShotCam") as Camera3D
	var height := _Marks.model_height(node)
	var focus := node.global_position + Vector3(0.0, height * 0.45, 0.0)
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)


func _span() -> float:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return 0.0
	var top := img.get_height()
	var bot := -1
	for y in img.get_height():
		var hit := false
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, y)
			if absf(px.r - CLEAR.r) > 0.08 or absf(px.g - CLEAR.g) > 0.08 or absf(px.b - CLEAR.b) > 0.08:
				hit = true
				break
		if hit:
			top = mini(top, y)
			bot = maxi(bot, y)
	if bot < top:
		return 0.0
	return float(bot - top + 1) / float(img.get_height())


func _save(path: String) -> bool:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("empty shot %s" % path)
		return false
	var err := img.save_png(path)
	if err != OK:
		push_error("save shot %s %s" % [path, str(err)])
		return false
	return true
