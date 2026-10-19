extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Capture = preload("res://helpers/probe_capture.gd")

var input = _Hands.new()
var watch = _Nav.StuckWatch.new()
var target := Vector2.ZERO
var home := Vector2.ZERO
var has_target := false
var arrived := false
var gave_up := false
var stuck_lines: PackedStringArray = PackedStringArray()
var stuck_reports := 0
var chapter := ""
var objective := ""
var fail_report := ""
var fail_shot := ""
var _recover_left := 0.0
var _strafe := "move_left"
var extra_held: PackedStringArray = PackedStringArray()
var stuck_limit := 0
var _jump_due := false
var _fail_seq := 0


func set_target(column_xz: Vector2) -> void:
	var same := has_target and home.distance_to(column_xz) <= 2.0
	if same:
		return
	home = column_xz
	target = column_xz
	has_target = true
	arrived = false
	gave_up = false
	stuck_lines = PackedStringArray()
	stuck_reports = 0
	fail_report = ""
	fail_shot = ""
	_recover_left = 0.0
	_jump_due = false
	watch.reset()


func release() -> void:
	input.release_all()


func tick(player_xz: Vector2, yaw_degrees: float, delta: float) -> void:
	input.begin_tick()
	if _jump_due and input.pulse(&"jump"):
		_jump_due = false
	if not has_target or arrived or gave_up:
		input.release_all()
		return
	var step := minf(maxf(delta, 0.0), 0.05)
	var plan: Dictionary = _Nav.choose(player_xz, target, yaw_degrees)
	if bool(plan.get("arrived", false)):
		if target.distance_to(home) > _Nav.ARRIVE_COLUMNS:
			target = home
			watch.reset()
			input.release_all()
			return
		arrived = true
		input.release_all()
		return
	input.set_held(_actions(plan, step))
	if not _moving():
		return
	if not watch.sample(player_xz, step, home):
		return
	stuck_reports += 1
	stuck_lines.append(_Nav.stuck_line(player_xz, watch.last_moved, watch.last_span, home))
	var limit := stuck_limit if stuck_limit > 0 else _Nav.MAX_STUCK_REPORTS
	if stuck_reports < limit:
		target = _Nav.reroute_column(player_xz, home, stuck_reports)
		_start_recover()
		input.set_held(_recover_actions())
		_jump_due = true
		if input.pulse(&"jump"):
			_jump_due = false
		watch.reset()
		return
	_write_failure(player_xz, "no progress toward the goal after a reroute")
	gave_up = true
	input.release_all()


func _actions(plan: Dictionary, step: float) -> PackedStringArray:
	if _recover_left > 0.0:
		_recover_left = maxf(_recover_left - step, 0.0)
		return _recover_actions()
	var out: PackedStringArray = PackedStringArray()
	var rotate := str(plan.get("rotate", ""))
	var move := str(plan.get("move", ""))
	if rotate != "":
		out.append(rotate)
	if move != "":
		out.append(move)
	if move == "move_forward" and watch.should_nudge():
		out.append(_strafe)
	for name in extra_held:
		var extra := String(name)
		if extra == "" or _listed(out, extra):
			continue
		out.append(extra)
	return out


func _recover_actions() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append(_strafe)
	return out


func _start_recover() -> void:
	_strafe = "move_right" if _strafe == "move_left" else "move_left"
	_recover_left = _Nav.RECOVER_SEC


func _listed(names: PackedStringArray, name: String) -> bool:
	for existing in names:
		if existing == name:
			return true
	return false


func fail_closed(pos: Vector2, reason: String, announce: bool = true) -> void:
	if fail_report != "":
		gave_up = true
		return
	_write_failure(pos, reason, announce)
	gave_up = true
	input.release_all()


func _write_failure(pos: Vector2, reason: String, announce: bool = true) -> void:
	var folder := _Capture.run_dir()
	var err := DirAccess.make_dir_recursive_absolute(folder)
	if err != OK:
		push_error("stuck report mkdir %s %s" % [folder, str(err)])
		return
	_fail_seq += 1
	var stamp := "%d-%d" % [Time.get_ticks_msec(), _fail_seq]
	var path := "%s/stuck-%s.txt" % [folder, stamp]
	var names := input.held_names()
	var phase := chapter if chapter != "" else "unknown"
	var text := "phase: %s\nchapter: %s\nobjective: %s\nposition: %.2f,%.2f\ntarget: %.2f,%.2f\ndistance: %.1f\ninputs: %s\nreason: %s\n" % [
		phase,
		phase,
		objective if objective != "" else "nav",
		pos.x, pos.y,
		home.x, home.y,
		pos.distance_to(home),
		",".join(names),
		reason,
	]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("stuck report open %s" % path)
		return
	file.store_string(text)
	file.close()
	fail_report = path
	var shot := _failure_image(pos)
	fail_shot = _Capture.write_step("stuck-%s" % stamp, shot)
	if announce:
		print("FAIL stuck dist %.1f %s" % [pos.distance_to(home), reason])
	print("STUCK REPORT %s" % path)
	if fail_shot != "":
		print("STUCK SHOT %s" % fail_shot)


func _failure_image(pos: Vector2) -> Image:
	if DisplayServer.get_name() != "headless":
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			var tex := tree.root.get_viewport().get_texture()
			if tex != null:
				var live := tex.get_image()
				if live != null and not live.is_empty():
					return live
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.28, 0.04, 0.06))
	img.set_pixel(posmod(int(pos.x), 64), posmod(int(absf(pos.y)), 64), Color(1, 1, 1))
	return img


func _moving() -> bool:
	return input.is_held("move_forward") or input.is_held("move_back") \
		or input.is_held("move_left") or input.is_held("move_right")
