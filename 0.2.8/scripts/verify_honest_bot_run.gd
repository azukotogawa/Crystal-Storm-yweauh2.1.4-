extends SceneTree

const _Run = preload("res://scripts/honest_bot/honest_crystal.gd")
const _Fight = preload("res://scripts/honest_bot/honest_combat.gd")
const _Prog = preload("res://scripts/honest_bot/honest_progress.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Capture = preload("res://helpers/probe_capture.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0
const NAV_MSEC := 5000
const COMBAT_MSEC := 8000
const PROGRESS_MSEC := 1500
const CRYSTAL_MSEC := 14000
const ENGAGE_HOLD_MSEC := 5000
const SENSE_COLUMNS := 32.0
const NAV_GAIN := 1.0

var _phases: Array[Dictionary] = []
var _failed_at := ""
var _mode := ""
var _live_player: Node = null
var _live_crystal: Node = null
var _crystal_run = null
var _fight = null
var _progress = null
var _combat_ids: Dictionary = {}
var _origin := Vector2.ZERO
var _nav_start := Vector2.ZERO


class _Pace extends Node:
	var host = null

	func _process(delta: float) -> void:
		if host != null:
			host._on_live_frame(delta)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tele := ""
	var booted: bool = await _boot()
	if booted:
		await _play()
	else:
		_skip_after_boot()
	tele = _flush_telemetry()
	var report := _write_report(tele)
	if report != "":
		print("REPORT %s" % report)
		_ProbeExit.finish_tree(self, 0, "HONEST BOT RUN DONE")
		return
	_ProbeExit.finish_tree(self, 1, "HONEST BOT RUN FAIL")


func _boot() -> bool:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_mark("boot", "failed", "main scene missing")
		return false
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 2400:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_mark("boot", "failed", "start region not ready")
		return false
	for _w in 120:
		await process_frame
		if not _GI.blocks_actions():
			break
	if _GI.blocks_actions():
		_mark("boot", "failed", "actions still blocked")
		return false
	var player = get_first_node_in_group("player")
	if player == null or not bool(player.get("world_ready")):
		_mark("boot", "failed", "player not world_ready")
		return false
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		_mark("boot", "failed", "no crystal origin")
		return false
	_live_player = player
	_live_crystal = crystal
	var origin: Vector2i = crystal.get_origin_cell()
	_origin = Vector2(float(origin.x), float(origin.y))
	_nav_start = _xz(player)
	_crystal_run = _Run.new()
	_fight = _Fight.new()
	_progress = _Prog.new()
	var pace := _Pace.new()
	pace.host = self
	pace.process_priority = -128
	root.add_child(pace)
	_mark("boot", "reached", "stream ready at %.2f,%.2f origin %.2f,%.2f" % [
		_nav_start.x, _nav_start.y, _origin.x, _origin.y
	])
	await _Capture.capture_step("honest-bot-boot")
	return true


func _skip_after_boot() -> void:
	for name in ["nav", "combat", "progress", "crystal"]:
		_mark(name, "not-reached", "boot failed")


func _play() -> void:
	_mode = "nav"
	var started := Time.get_ticks_msec()
	while true:
		await process_frame
		var moved := _xz(_live_player).distance_to(_nav_start)
		if Time.get_ticks_msec() - started >= NAV_MSEC or moved >= NAV_GAIN:
			break
	await _finish_nav()
	if _lock_combat():
		_mode = "combat"
		started = Time.get_ticks_msec()
		while true:
			await process_frame
			if Time.get_ticks_msec() - started >= COMBAT_MSEC or _fight.deaths > 0:
				break
		await _finish_combat()
	else:
		_fight.release()
		_mark("combat", "failed", "no enemy within %.0f columns" % SENSE_COLUMNS)
		await _Capture.capture_step("honest-bot-combat")
	var points_before := _spare_points()
	if points_before <= 0:
		_mark("progress", "failed", "no skill point")
		await _Capture.capture_step("honest-bot-progress")
	else:
		_progress.skill_points = points_before
		_mode = "progress"
		started = Time.get_ticks_msec()
		while true:
			await process_frame
			if Time.get_ticks_msec() - started >= PROGRESS_MSEC:
				break
		await _finish_progress(points_before)
	var swings_at_start := int(_crystal_run.fight.swings)
	var hp_at_start := _crystal_hp(_live_crystal)
	_mode = "crystal"
	started = Time.get_ticks_msec()
	var close_ms := 0
	while true:
		await process_frame
		var now := Time.get_ticks_msec()
		var remaining := _xz(_live_player).distance_to(_origin)
		if remaining <= _Run.ENGAGE_COLUMNS and close_ms == 0:
			close_ms = now
		var held: bool = close_ms > 0 and now - close_ms >= ENGAGE_HOLD_MSEC
		var expired: bool = now - started >= CRYSTAL_MSEC
		var gave_up: bool = _crystal_run.fight.bot.gave_up and close_ms == 0
		if _crystal_run.destroyed or _crystal_run.fight.deaths > 0 or held or expired or gave_up:
			await _finish_crystal(swings_at_start, hp_at_start)
			break
	_release_all()


func _finish_nav() -> void:
	var end := _xz(_live_player)
	var gained := end.distance_to(_nav_start)
	_crystal_run.release()
	if gained >= NAV_GAIN:
		_mark("nav", "reached", "moved %.2f columns to %.2f,%.2f" % [gained, end.x, end.y])
	else:
		_mark("nav", "failed", "moved %.2f columns at %.2f,%.2f" % [gained, end.x, end.y])
	await _Capture.capture_step("honest-bot-nav")


func _lock_combat() -> bool:
	_combat_ids.clear()
	var origin := _xz(_live_player)
	for node in get_nodes_in_group("crystal_enemy"):
		if not _enemy_alive(node):
			continue
		var body := node as Node3D
		var xz := _Coords.column_from_node(body)
		if origin.distance_to(xz) > SENSE_COLUMNS:
			continue
		_combat_ids["enemy-%d" % node.get_instance_id()] = node
	return not _combat_ids.is_empty()


func _finish_combat() -> void:
	_fight.release()
	var kills := int(_fight.kills)
	var swings := int(_fight.swings)
	if kills > 0 or swings > 0:
		_mark("combat", "reached", "swings %d kills %d" % [swings, kills])
	else:
		_mark("combat", "failed", "enemy in range but no swing")
	for line in _fight.lines:
		print(line)
	await _Capture.capture_step("honest-bot-combat")


func _finish_progress(points_before: int) -> void:
	_progress.release()
	var spent: bool = _spare_points() < points_before
	var announced := ""
	for line in _progress.lines:
		print(line)
		if line.begins_with("SKILL "):
			announced = line
	if spent:
		_mark("progress", "reached", announced if announced != "" else "point spent")
	elif announced != "":
		_mark("progress", "failed", "accept did not spend a point")
	else:
		_mark("progress", "failed", "tree did not accept")
	await _Capture.capture_step("honest-bot-progress")


func _finish_crystal(swings_at_start: int, hp_at_start: Vector2) -> void:
	var end := _xz(_live_player)
	var hp := _crystal_hp(_live_crystal)
	var swings := int(_crystal_run.fight.swings) - swings_at_start
	var remaining := end.distance_to(_origin)
	for line in _crystal_run.lines:
		print(line)
	var detail := "remaining %.2f at %.2f,%.2f hp %.1f/%.1f swings %d" % [
		remaining, end.x, end.y, hp.x, hp.y, swings
	]
	print("STOP live %s" % detail)
	if _crystal_run.destroyed:
		_mark("crystal", "reached", detail)
	elif swings > 0 and hp.x >= hp_at_start.x - 0.01:
		_mark("crystal", "failed", "attacks did not chip; %s" % detail)
	elif remaining > _Run.ENGAGE_COLUMNS:
		_mark("crystal", "failed", "did not reach engage range; %s" % detail)
	else:
		_mark("crystal", "failed", detail)
	_crystal_run.release()
	await _Capture.capture_step("honest-bot-crystal-run")


func _on_live_frame(delta: float) -> void:
	if _live_player == null:
		return
	var step := delta
	if step <= 0.0:
		step = STEP
	var pos := _xz(_live_player)
	var yaw := _yaw(_live_player)
	if _mode == "combat":
		_fight.set_vitals(float(_live_player.health), float(_live_player.max_health))
		if _fight.deaths > 0:
			return
		_fight.observe(_combat_seen())
		_fight.tick(pos, yaw, step)
		return
	if _mode == "progress":
		_progress.tick(step)
		return
	if _mode != "nav" and _mode != "crystal":
		return
	if _crystal_run == null or _live_crystal == null:
		return
	_crystal_run.set_vitals(float(_live_player.health), float(_live_player.max_health))
	if _crystal_run.fight.deaths > 0:
		return
	var hp := _crystal_hp(_live_crystal)
	_crystal_run.observe_crystal(_origin, hp.x, hp.y)
	_crystal_run.observe_foes(_bosses_now())
	_crystal_run.tick(pos, yaw, step)


func _combat_seen() -> Array:
	var out: Array = []
	for id in _combat_ids.keys():
		var node: Object = _combat_ids[id]
		if not _enemy_alive(node):
			continue
		var body := node as Node3D
		out.append({"id": str(id), "xz": _Coords.column_from_node(body)})
	return out


func _bosses_now() -> Array:
	var out: Array = []
	for node in get_nodes_in_group("origin_boss"):
		if not is_instance_valid(node):
			continue
		if float(node.get("health")) <= 0.0:
			continue
		var body := node as Node3D
		if body == null:
			continue
		out.append({
			"id": "boss-%d" % node.get_instance_id(),
			"xz": _Coords.column_from_node(body),
		})
	return out


func _enemy_alive(node: Object) -> bool:
	if not is_instance_valid(node):
		return false
	if not (node is Node3D):
		return false
	return float(node.get("health")) > 0.0


func _spare_points() -> int:
	var node := get_first_node_in_group("progression_service")
	if node == null or not ("skill_points" in node):
		return 0
	return maxi(int(node.skill_points), 0)


func _release_all() -> void:
	if _crystal_run != null:
		_crystal_run.release()
	if _fight != null:
		_fight.release()
	if _progress != null:
		_progress.release()
	_mode = ""


func _mark(phase_name: String, status: String, detail: String) -> void:
	_phases.append({"name": phase_name, "status": status, "detail": detail})
	print("PHASE %s %s %s" % [phase_name, status, detail])
	if status != "reached" and _failed_at == "":
		_failed_at = "%s: %s" % [phase_name, detail]


func _flush_telemetry() -> String:
	var node := root.get_node_or_null("DifficultyTelemetry")
	if node == null or not node.has_method("flush"):
		return ""
	return str(node.flush())


func _write_report(tele_path: String) -> String:
	var folder := _evidence_dir()
	if folder == "":
		push_error("honest bot run missing CRYSTALSTORM_EVIDENCE")
		return ""
	var body := "# Honest bot run\n\n"
	body += "Run: %s\n\n" % OS.get_environment("CRYSTALSTORM_RUN_ID").strip_edges()
	if _failed_at == "":
		body += "Result: all phases reached\n\n"
	else:
		body += "Result: failed at %s\n\n" % _failed_at
	body += "## Phases\n\n"
	for phase in _phases:
		body += "- %s: %s - %s\n" % [str(phase.get("name", "")), str(phase.get("status", "")), str(phase.get("detail", ""))]
	body += "\n## Telemetry\n\n"
	if tele_path == "":
		body += "No telemetry JSON was written.\n"
	else:
		body += "%s\n" % tele_path
	var path := "%s/bot-report.md" % folder
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("honest bot run could not write %s" % path)
		return ""
	file.store_string(body)
	file.close()
	return path


func _evidence_dir() -> String:
	var explicit := OS.get_environment("CRYSTALSTORM_EVIDENCE").strip_edges().replace("\\", "/")
	while explicit.ends_with("/"):
		explicit = explicit.substr(0, explicit.length() - 1)
	return explicit


func _crystal_hp(crystal: Node) -> Vector2:
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return Vector2.ZERO
	var prog: Dictionary = crystal.get_spawn_progress()
	return Vector2(float(prog.get("crystal_health", 0.0)), float(prog.get("crystal_max_health", 0.0)))


func _xz(player: Node) -> Vector2:
	var placed: Vector3 = player.voxel_position
	return Vector2(placed.x, placed.z)


func _yaw(player: Node) -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	return 0.0
