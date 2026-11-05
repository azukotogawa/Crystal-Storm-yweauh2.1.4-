extends SceneTree
## Capture pixel-look evidence into CRYSTALSTORM_SCRATCH.
## Avoids WorldManager.wipe_worlds / start_fresh_run entirely.

const _PixelLook = preload("res://helpers/pixel_look.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _TutorialOverlay = preload("res://ui/tutorial_overlay.gd")
const _Loader = preload("res://helpers/crystal_voxel_loader.gd")

const TREE_OAK := "res://assets/voxel/vegetation/lod/tree_oak_v0_s2_lod0.json"

var _out := ""
var _mode := "compare"
var _log := PackedStringArray()


func _init() -> void:
	_out = OS.get_environment("CRYSTALSTORM_SCRATCH")
	var mode_env := OS.get_environment("CS_PIXEL_SHOT_MODE").strip_edges()
	if not mode_env.is_empty():
		_mode = mode_env
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--mode="):
			_mode = a.substr(7)
	call_deferred("_run")


func _note(msg: String) -> void:
	_log.append(msg)
	print("SHOT " + msg)


func _stage_name(compose, st: int) -> String:
	if compose == null:
		return "?"
	var names = compose.get("STAGE_NAMES")
	if names != null and names.has(st):
		return str(names[st])
	return str(st)


func _loading_visible(game: Node) -> bool:
	var ls := game.get_node_or_null("LoadingLayer/LoadingScreen")
	if ls == null:
		ls = game.find_child("LoadingScreen", true, false)
	if ls == null:
		return false
	return bool(ls.visible)


func _wait_frames(n: int, label: String) -> void:
	var i := 0
	while i < n:
		await process_frame
		i += 1
		if i % 60 == 0:
			_note("%s frames=%d/%d" % [label, i, n])


func _hide_chrome() -> void:
	# In-memory only. Do not write player_settings.json.
	_PlayerSettings.tutorial_completed = true
	if ClassDB.class_exists("TutorialOverlay"):
		TutorialOverlay.dismiss()
	_TutorialOverlay.dismiss()
	for node in get_nodes_in_group("loading_screen"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	for node in get_nodes_in_group("debug_panel"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	for node in get_nodes_in_group("pause_menu"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		if node.has_method("close"):
			node.call("close")
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is TutorialOverlay:
			(node as CanvasLayer).visible = false
		var n := str(node.name).to_lower()
		if n.contains("tutorial") and node is CanvasItem:
			(node as CanvasItem).visible = false


func _aim_trees_character(cam: Camera3D, player: Node) -> void:
	if cam == null or player == null:
		return
	# Look across the planted grove with the player in frame.
	if cam.has_method("snap_yaw_degrees"):
		cam.call("snap_yaw_degrees", 45.0)
	elif "yaw_degrees" in cam:
		cam.set("yaw_degrees", 45.0)
		cam.set("yaw_target_degrees", 45.0)
		if cam.has_method("_update_camera_transform"):
			cam.call("_update_camera_transform")
	if "pitch_degrees" in cam:
		cam.set("pitch_degrees", -28.0)
		if "pitch_target_degrees" in cam:
			cam.set("pitch_target_degrees", -28.0)
		if cam.has_method("_update_camera_transform"):
			cam.call("_update_camera_transform")


func _plant_oak_grove(game: Node, player: Node) -> void:
	if player == null:
		return
	var mesh: ArrayMesh = _Loader.mesh_for(TREE_OAK)
	if mesh == null:
		_note("FAIL oak mesh null")
		return
	var origin: Vector3 = player.global_position if player is Node3D else Vector3.ZERO
	# Ring of oaks around the player so they read clearly under pixel look.
	# Far arc ahead/side so tall oak canopies do not cover the player.
	var offsets := [
		Vector3(22, 0, 18), Vector3(28, 0, 14), Vector3(18, 0, 26),
		Vector3(32, 0, 22), Vector3(24, 0, 30), Vector3(36, 0, 16),
		Vector3(-18, 0, 24), Vector3(24, 0, -16),
	]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = offsets.size()
	for i in offsets.size():
		var p: Vector3 = origin + offsets[i]
		p.y = origin.y
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PixelShotOakGrove"
	mmi.multimesh = mm
	game.add_child(mmi)
	_note("PLANTED_OAKS n=%d quads_per=%d at %s" % [offsets.size(), _Loader.quad_count(mesh), str(origin)])


func _run() -> void:
	if _out.is_empty():
		_out = OS.get_user_data_dir().path_join("pixel_shots")
	DirAccess.make_dir_recursive_absolute(_out)
	_PlayerSettings.settings_path = _out.path_join("player_settings.json")
	_PlayerSettings.tutorial_completed = true
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _wait_frames(5, "INIT")

	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	var ready_min := 5
	var failed := 9
	var running := 7
	while frames < 18000:
		var st := -1
		if compose != null:
			st = int(compose.stage)
		if compose != null and st == failed:
			_note("BOOT_FAILED stage=FAILED frames=%d" % frames)
			break
		if compose != null and st >= running:
			break
		if compose != null and st >= ready_min and not _loading_visible(game):
			break
		if frames % 180 == 0:
			_note(
				"WAIT frames=%d stage=%d(%s) loading=%s"
				% [frames, st, _stage_name(compose, st), str(_loading_visible(game))]
			)
		await process_frame
		frames += 1

	# Give main._ready time to return from boot_async and run maybe_install.
	var want_pixel := _PixelLook.parse_enabled()
	var wait_install := 0
	while wait_install < 180:
		await process_frame
		wait_install += 1
		if (not want_pixel) or game.get_node_or_null("PixelLookController") != null:
			break
		if wait_install % 30 == 0:
			_note("WAIT_INSTALL n=%d ctrl=%s" % [wait_install, str(game.get_node_or_null("PixelLookController") != null)])

	# If still missing and env wants it, install from harness (main may have skipped).
	if want_pixel and game.get_node_or_null("PixelLookController") == null:
		_note("HARNESS_INSTALL")
		load("res://systems/pixel_look_controller.gd").maybe_install(game)
		await _wait_frames(10, "POST_INSTALL")

	_note(
		"BOOT frames=%d stage=%d(%s) loading=%s pixel_env=%s height_env=%s ctrl=%s want=%s"
		% [
			frames,
			int(compose.stage) if compose else -1,
			_stage_name(compose, int(compose.stage) if compose else -1),
			str(_loading_visible(game)),
			OS.get_environment(_PixelLook.ENV_ENABLE),
			OS.get_environment(_PixelLook.ENV_HEIGHT),
			str(game.get_node_or_null("PixelLookController") != null),
			str(want_pixel),
		]
	)
	if compose != null and int(compose.stage) == failed:
		_note("ABORT boot failed")
		_write_log()
		quit(2)
		return

	await _wait_frames(90, "SETTLE")
	_hide_chrome()
	if InputMap.has_action("pause"):
		for _i in 2:
			Input.action_press("pause")
			await process_frame
			Input.action_release("pause")
			await _wait_frames(10, "PAUSE")
	_hide_chrome()

	var player := get_first_node_in_group("player")
	if player == null:
		_note("FAIL no player")
		_write_log()
		quit(1)
		return
	player.set("dev_god", true)
	player.set("voxel_position", Vector3(504.0, 19.0, -744.0))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	var cm = get_first_node_in_group("chunk_manager")
	var waited := 0
	while waited < 600:
		await process_frame
		waited += 1
		if cm != null and cm.get("chunks") != null and int(cm.chunks.size()) > 8:
			break
		if waited % 60 == 0:
			_note("CHUNKS_WAIT n=%d count=%s" % [waited, str(cm.chunks.size() if cm else -1)])
	_note("CHUNKS wait=%d count=%s" % [waited, str(cm.chunks.size() if cm else -1)])
	await _wait_frames(60, "POST_CHUNK")
	_hide_chrome()

	_plant_oak_grove(game, player)
	await _wait_frames(30, "GROVE")

	var cam := get_first_node_in_group("camera") as Camera3D
	if cam == null and player != null:
		cam = player.get_node_or_null("Camera3D") as Camera3D

	var ctrl = game.get_node_or_null("PixelLookController")
	if ctrl != null and ctrl.has_method("get_internal_size"):
		_note("INTERNAL_SIZE %s" % str(ctrl.call("get_internal_size")))

	_PlayerSettings.tutorial_completed = true
	_hide_chrome()
	await _wait_frames(20, "HIDE_CHROME")
	_hide_chrome()
	_aim_trees_character(cam, player)
	await _wait_frames(30, "AIM")
	_hide_chrome()

	match _mode:
		"orbit":
			await _orbit(cam)
		"fps":
			await _fps_sample()
		_:
			await _grab("frame")
	_write_log()
	print("PIXEL_SHOTS OK mode=%s" % _mode)
	quit(0)


func _grab(name: String) -> void:
	_hide_chrome()
	await process_frame
	await process_frame
	var path := "%s/%s.png" % [_out, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	_note("SAVE %s err=%d %dx%d" % [path, err, img.get_width(), img.get_height()])


func _orbit(cam: Camera3D) -> void:
	if cam == null:
		_note("NO_CAMERA")
		return
	var yaws := [45.0, 75.0, 105.0, 135.0, 165.0, 195.0, 225.0, 255.0]
	var i := 0
	for yaw in yaws:
		_hide_chrome()
		if cam.has_method("snap_yaw_degrees"):
			cam.call("snap_yaw_degrees", float(yaw))
		elif "yaw_degrees" in cam:
			cam.set("yaw_degrees", float(yaw))
			cam.set("yaw_target_degrees", float(yaw))
			if cam.has_method("_update_camera_transform"):
				cam.call("_update_camera_transform")
		await _wait_frames(20, "ORBIT")
		await _grab("orbit_%02d_yaw%d" % [i, int(yaw)])
		i += 1


func _fps_sample() -> void:
	await _wait_frames(30, "FPS_WARM")
	var samples: PackedFloat64Array = PackedFloat64Array()
	var start_us := Time.get_ticks_usec()
	var prev := start_us
	var frames := 0
	while frames < 180:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - prev) / 1000.0)
		prev = now
		frames += 1
	var total_ms := float(prev - start_us) / 1000.0
	var mean := total_ms / float(maxi(frames, 1))
	var sorted := samples.duplicate()
	sorted.sort()
	var p50 := sorted[int(sorted.size() * 0.5)]
	var p95 := sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]
	var fps := 1000.0 / maxf(mean, 0.001)
	var line := "FPS_SAMPLE enable=%s height=%s frames=%d mean_ms=%.3f p50_ms=%.3f p95_ms=%.3f fps=%.2f" % [
		OS.get_environment(_PixelLook.ENV_ENABLE),
		OS.get_environment(_PixelLook.ENV_HEIGHT),
		frames, mean, p50, p95, fps
	]
	_note(line)
	var fa := FileAccess.open(_out.path_join("fps.txt"), FileAccess.WRITE)
	if fa:
		fa.store_string(line + "\n")
		fa.close()


func _write_log() -> void:
	var fa := FileAccess.open(_out.path_join("shot_log.txt"), FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(_log))
		fa.close()
