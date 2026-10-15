class_name ProbeCapture
extends RefCounted

const EVIDENCE_ROOT := "D:/ARCHIVE/CrystalStorm/verify-evidence"
const _NAME_LIMIT := 64


static func capture_step(step_name: String) -> String:
	if not _can_grab():
		return ""
	var tree := Engine.get_main_loop() as SceneTree
	await RenderingServer.frame_post_draw
	if not _can_grab():
		return ""
	var tex := tree.root.get_viewport().get_texture()
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null or img.is_empty():
		return ""
	return write_step(step_name, img)


static func _can_grab() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	return tree.root.get_viewport() != null


static func write_step(step_name: String, image: Image) -> String:
	if image == null or image.is_empty():
		push_error("probe capture empty image %s" % step_name)
		return ""
	var folder := steps_dir()
	var err := DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		push_error("probe capture mkdir %s %s" % [folder, str(err)])
		return ""
	var path := "%s/%s" % [folder, file_name(next_index(folder), step_name)]
	err = image.save_png(path)
	if err != OK:
		push_error("probe capture save %s %s" % [path, str(err)])
		return ""
	print("PROBE CAPTURE %s" % path)
	return path


static func steps_dir() -> String:
	return "%s/steps" % run_dir()


static func run_dir() -> String:
	var explicit := OS.get_environment("CRYSTALSTORM_EVIDENCE").strip_edges().replace("\\", "/")
	while explicit.ends_with("/"):
		explicit = explicit.substr(0, explicit.length() - 1)
	if not explicit.is_empty():
		return explicit
	var run_id := OS.get_environment("CRYSTALSTORM_RUN_ID").strip_edges()
	if run_id.is_empty():
		run_id = "unscoped"
	return "%s/%s" % [EVIDENCE_ROOT, safe_step_name(run_id)]


static func file_name(index: int, step_name: String) -> String:
	return "%d_%s.png" % [maxi(index, 1), safe_step_name(step_name)]


static func safe_step_name(step_name: String) -> String:
	var raw := ""
	var prev_break := false
	for i in step_name.length():
		var c := step_name.unicode_at(i)
		if _is_step_char(c):
			raw += char(c)
			prev_break = false
		elif not prev_break and not raw.is_empty():
			raw += "_"
			prev_break = true
	while raw.ends_with("_"):
		raw = raw.substr(0, raw.length() - 1)
	while raw.begins_with("."):
		raw = raw.substr(1)
	if raw.is_empty():
		return "step"
	if raw.length() > _NAME_LIMIT:
		raw = raw.substr(0, _NAME_LIMIT)
		while raw.ends_with("_"):
			raw = raw.substr(0, raw.length() - 1)
	return raw


static func next_index(folder: String) -> int:
	var highest := 0
	var dir := DirAccess.open(folder)
	if dir == null:
		return 1
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var found := _leading_index(name)
			if found > highest:
				highest = found
		name = dir.get_next()
	dir.list_dir_end()
	return highest + 1


static func _leading_index(file_name: String) -> int:
	var mark := file_name.find("_")
	if mark <= 0 or not file_name.ends_with(".png"):
		return 0
	var digits := file_name.substr(0, mark)
	if not digits.is_valid_int():
		return 0
	return maxi(int(digits), 0)


static func _is_step_char(c: int) -> bool:
	if c >= 48 and c <= 57:
		return true
	if c >= 65 and c <= 90:
		return true
	if c >= 97 and c <= 122:
		return true
	return c == 45 or c == 46 or c == 95
