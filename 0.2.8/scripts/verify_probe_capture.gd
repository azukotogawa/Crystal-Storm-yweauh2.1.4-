extends SceneTree

const _Capture = preload("res://helpers/probe_capture.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "")
	OS.set_environment("CRYSTALSTORM_EVIDENCE", "D:/csmerge/verify-scratch/probe-capture-%s" % stamp)
	if not _check_names():
		quit(1)
		return
	if not _check_writes():
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		if not await _check_viewport():
			quit(1)
			return
	print("PROBE CAPTURE OK")
	quit(0)


func _check_names() -> bool:
	if _Capture.safe_step_name("dig") != "dig":
		push_error("plain step name")
		return false
	if _Capture.safe_step_name("blue box") != "blue_box":
		push_error("space step name")
		return false
	if _Capture.safe_step_name("foo/bar") != "foo_bar":
		push_error("slash step name")
		return false
	if _Capture.safe_step_name("") != "step":
		push_error("empty step name")
		return false
	if _Capture.safe_step_name("..") != "step":
		push_error("dot step name")
		return false
	var named := _Capture.file_name(3, "a/b")
	if named != "3_a_b.png" or named.contains("/"):
		push_error("file name %s" % named)
		return false
	print("OK probe capture names")
	return true


func _check_writes() -> bool:
	var folder := _Capture.steps_dir()
	var err := DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		push_error("probe capture test mkdir %s" % str(err))
		return false
	var planted := FileAccess.open("%s/9_old.png" % folder, FileAccess.WRITE)
	if planted == null:
		push_error("probe capture test plant")
		return false
	planted.store_8(0)
	planted.close()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	var first := _Capture.write_step("alpha", img)
	img.fill(Color(0, 0, 1))
	var second := _Capture.write_step("blue box", img)
	if first != "%s/10_alpha.png" % folder:
		push_error("first step %s" % first)
		return false
	if second != "%s/11_blue_box.png" % folder:
		push_error("second step %s" % second)
		return false
	var loaded := Image.new()
	if loaded.load(second) != OK or loaded.get_width() != 4 or loaded.get_height() != 4:
		push_error("second step unreadable")
		return false
	var px := loaded.get_pixel(0, 0)
	if px.b < 0.9 or px.r > 0.1:
		push_error("second step pixel %s" % str(px))
		return false
	print("OK probe capture files")
	return true


func _check_viewport() -> bool:
	DisplayServer.window_set_size(Vector2i(320, 180))
	var layer := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.color = Color(0.0, 1.0, 0.0, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	root.add_child(layer)
	for _i in 2:
		await process_frame
	var shot: String = await _Capture.capture_step("green")
	if shot.is_empty() or not shot.ends_with("_green.png"):
		push_error("viewport capture path %s" % shot)
		return false
	var img := Image.new()
	if img.load(shot) != OK:
		push_error("viewport capture unreadable")
		return false
	var px := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	if px.g < 0.8 or px.r > 0.2 or px.b > 0.2:
		push_error("viewport capture pixel %s" % str(px))
		return false
	print("OK probe capture viewport %s" % shot)
	return true
