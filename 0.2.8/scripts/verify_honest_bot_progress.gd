extends SceneTree

const _Prog = preload("res://scripts/honest_bot/honest_progress.gd")
const _Progress = preload("res://systems/progression_service.gd")
const _Skills = preload("res://systems/skill_service.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Capture = preload("res://helpers/probe_capture.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const STEP := 1.0 / 60.0

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sources()
	_check_kills_only()
	if _failed == 0:
		await _check_choice_lands()
	await _Capture.capture_step("honest-bot-progress")
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "HONEST BOT PROGRESS OK")
	else:
		_ProbeExit.finish_tree(self, 1, "HONEST BOT PROGRESS FAIL")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _check_sources() -> void:
	var banned := [
		"voxel_position =",
		"global_position =",
		".position =",
		"take_damage",
		"add_xp",
		"grant_xp",
		"unlock(",
		"equip(",
		"dig_cell",
		"health =",
		"60000",
	]
	var paths := [
		"res://scripts/honest_bot/honest_nav.gd",
		"res://scripts/honest_bot/honest_input.gd",
		"res://scripts/honest_bot/honest_play_bot.gd",
		"res://scripts/honest_bot/honest_combat.gd",
		"res://scripts/honest_bot/honest_progress.gd",
	]
	var joined := ""
	for path in paths:
		joined += FileAccess.get_file_as_string(path)
	for token in banned:
		if token in joined:
			_fail("bot source contains %s" % token)
			return
	var hands := FileAccess.get_file_as_string("res://scripts/honest_bot/honest_input.gd")
	if not ("Input.action_press" in hands and "InputEventAction" in hands):
		_fail("input driver must use action_press and InputEventAction")
		return
	var progress := FileAccess.get_file_as_string("res://scripts/honest_bot/honest_progress.gd")
	if not ("skill_tree" in progress and "ui_accept" in progress and "xp_snapshot" in progress):
		_fail("progress must open the tree, accept a skill, and read telemetry")
		return
	if not ("note_kill" in progress and "note_other" in progress and "xp_for_kill" in progress):
		_fail("progress must level from kill tiers only")
		return
	_ok("progress source is input-only")


func _check_kills_only() -> void:
	var bot = _Prog.new()
	bot.note_other("mine")
	bot.note_other("place")
	bot.note_other("ruin")
	bot.note_other("crystal")
	bot.note_kill(-1)
	if bot.level != 1 or bot.skill_points != 0 or bot.xp != 0:
		_fail("non-kill sources changed level to %d xp %d" % [bot.level, bot.xp])
		bot.release()
		return
	for _i in 4:
		bot.tick(STEP)
	if _has_prefix(bot.lines, "SKILL"):
		_fail("no kill points should still pick a skill")
		bot.release()
		return
	bot.note_kill(0)
	if bot.level != 1 or bot.xp != _Progress.xp_for_kill(0):
		_fail("one weak kill should not level, xp %d" % bot.xp)
		bot.release()
		return
	for _n in 4:
		bot.note_kill(1)
	var expect := _Progress.xp_for_kill(0) + 4 * _Progress.xp_for_kill(1)
	var need := _Progress.xp_to_advance(1)
	if bot.level != 2 or bot.skill_points != 1 or bot.xp != expect - need:
		_fail("kill xp want level 2 remainder %d got level %d xp %d points %d" % [
			expect - need, bot.level, bot.xp, bot.skill_points
		])
		bot.release()
		return
	var saw_skill := false
	for _i in 8:
		bot.tick(STEP)
	for line in bot.lines:
		print(line)
		if line == "SKILL dash":
			saw_skill = true
	print(bot.summary_line())
	bot.release()
	if not saw_skill:
		_fail("a kill level did not choose dash")
		return
	_ok("levels only from kills and chooses dash")


func _check_choice_lands() -> void:
	_GI.skill_tree_open = false
	_GI.pause_open = false
	_GI.map_open = false
	_GI.dev_chat_open = false
	_GI.world_loading = false
	paused = false
	var prog := _Progress.new()
	var skills := _Skills.new()
	root.add_child(prog)
	root.add_child(skills)
	for _i in 3:
		await process_frame
	var gain := _Progress.xp_for_kill(1)
	for _n in 4:
		prog.add_xp(gain)
	var tele := root.get_node_or_null("DifficultyTelemetry")
	if tele == null or not tele.has_method("xp_snapshot"):
		_fail("telemetry autoload missing")
		_drop_choice(prog, skills, null)
		return
	var snap: Dictionary = tele.xp_snapshot()
	if int(snap.get("gained", 0)) != gain * 4 or int(snap.get("level", 0)) != 2:
		_fail("telemetry want gained %d level 2 got %s" % [gain * 4, snap])
		_drop_choice(prog, skills, null)
		return
	if float(snap.get("per_minute", 0.0)) <= 0.0:
		_fail("telemetry xp rate was zero")
		_drop_choice(prog, skills, null)
		return
	var panel = load("res://ui/skill_tree_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var bot = _Prog.new()
	for _n in 4:
		bot.note_kill(1)
	for _i in 8:
		bot.tick(STEP)
		await process_frame
	var before: Dictionary = tele.xp_snapshot()
	var rate_line := bot.read_telemetry(self)
	var after: Dictionary = tele.xp_snapshot()
	print(rate_line)
	var landed: bool = skills.is_unlocked(&"dash") and skills.slot_skill(0) == &"dash"
	var missed: bool = skills.is_unlocked(&"crystal_pulse")
	var rate_ok: bool = _rate_matches(rate_line, before) or _rate_matches(rate_line, after)
	bot.release()
	_drop_choice(prog, skills, panel)
	if not landed or missed:
		_fail("input choice want dash equipped, crystal pulse locked")
		return
	if not rate_ok:
		_fail("xp rate line did not match telemetry (%s)" % rate_line)
		return
	_ok("skill choice landed through input and xp rate matches telemetry")


func _drop_choice(prog, skills, panel) -> void:
	if panel != null and is_instance_valid(panel):
		if panel.has_method("close"):
			panel.close()
		panel.free()
	if skills != null and is_instance_valid(skills):
		skills.free()
	if prog != null and is_instance_valid(prog):
		prog.free()
	_GI.skill_tree_open = false
	_GI.pause_open = false
	paused = false


func _rate_matches(line: String, snap: Dictionary) -> bool:
	var expect := "XP_RATE %.4f gained %d" % [float(snap.get("per_minute", 0.0)), int(snap.get("gained", 0))]
	return line == expect


func _has_prefix(rows: PackedStringArray, prefix: String) -> bool:
	for line in rows:
		if line.begins_with(prefix):
			return true
	return false
