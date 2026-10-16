extends SceneTree

const _Show = preload("res://scripts/honest_bot/honest_showcase.gd")
const _Route = preload("res://scripts/honest_bot/honest_route.gd")
const _Walk = preload("res://scripts/honest_bot/honest_traversal.gd")
const _Chapters = preload("res://scripts/honest_bot/honest_chapters.gd")
const _Hud = preload("res://scripts/honest_bot/honest_showcase_hud.gd")
const _Roster = preload("res://scripts/honest_bot/honest_roster.gd")
const _Cast = preload("res://scripts/honest_bot/honest_skill_cast.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Capture = preload("res://helpers/probe_capture.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0
const LIVE_FRAMES := 180000

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sources()
	_check_route()
	_check_traversal()
	_check_chapters()
	_check_sprint_hold()
	_check_blueprint_key()
	_check_roster()
	_check_skill_pad()
	var hud_ok: bool = await _check_hud()
	if not hud_ok:
		_fail("timer label missing")
	if _failed == 0:
		await _check_live()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "HONEST BOT SHOWCASE OK")
	else:
		_ProbeExit.finish_tree(self, 1, "HONEST BOT SHOWCASE FAIL")


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
		"dig_cell",
		"health =",
	]
	var paths := [
		"res://scripts/honest_bot/honest_nav.gd",
		"res://scripts/honest_bot/honest_input.gd",
		"res://scripts/honest_bot/honest_play_bot.gd",
		"res://scripts/honest_bot/honest_route.gd",
		"res://scripts/honest_bot/honest_traversal.gd",
		"res://scripts/honest_bot/honest_chapters.gd",
		"res://scripts/honest_bot/honest_showcase_hud.gd",
		"res://scripts/honest_bot/honest_showcase.gd",
		"res://scripts/honest_bot/honest_build.gd",
		"res://scripts/honest_bot/honest_roster.gd",
		"res://scripts/honest_bot/honest_fight.gd",
		"res://scripts/honest_bot/honest_skill_cast.gd",
	]
	var joined := ""
	for path in paths:
		var body := FileAccess.get_file_as_string(path)
		if body.is_empty():
			_fail("missing %s" % path)
			return
		joined += body
	for token in banned:
		if token in joined:
			_fail("showcase source contains %s" % token)
			return
	var hands := FileAccess.get_file_as_string("res://scripts/honest_bot/honest_input.gd")
	if not ("Input.action_press" in hands and "InputEventAction" in hands):
		_fail("input driver must use action_press and InputEventAction")
		return
	_ok("showcase source is input-only")


func _check_route() -> void:
	var show = _Show.new()
	if not show.load_route():
		_fail("route checklist missing")
		return
	var names := _Route.ids(show.route)
	if names.size() < 4:
		_fail("route has %d features" % names.size())
		return
	if names[0] != "boot_tutorial" or names[1] != "movement" or names[2] != "lighting" or names[3] != "day_night":
		_fail("route prefix %s" % [names[0], names[1], names[2], names[3]])
		return
	if show.first_blocked() != "crystal":
		_fail("next segment should be crystal, got %s" % show.first_blocked())
		return
	var want := ["density_poi", "density_treasure", "density_landmark", "combat_crystal_mite", "skill_ground_slam", "skill_dash"]
	for id in want:
		if not names.has(id):
			_fail("route missing %s" % id)
			return
	_ok("route order stops at crystal")


func _check_traversal() -> void:
	var near := {
		Vector2i(10, 0): {"center": Vector2i(10, 0), "poi_kind": "camp", "poi": true},
		Vector2i(80, 0): {"center": Vector2i(80, 0), "poi_kind": "shrine", "poi": true},
		Vector2i(20, 4): {"center": Vector2i(20, 4), "treasure_site": true},
		Vector2i(30, -6): {"center": Vector2i(30, -6), "poi_kind": "rock_spire", "landmark": true},
	}
	var poi: Dictionary = _Walk.poi_choice(Vector2.ZERO, near)
	if str(poi.get("status", "")) != "walk" or float(poi.get("distance", 99.0)) > 10.1:
		_fail("nearest camp should win, got %s" % poi)
		return
	var far_cells := {
		Vector2i(0, 60): {"center": Vector2i(0, 60), "poi_kind": "shrine"},
	}
	var far: Dictionary = _Walk.poi_choice(Vector2.ZERO, far_cells)
	if str(far.get("status", "")) != "too-far":
		_fail("poi past 48 should be too-far")
		return
	if str(_Walk.poi_choice(Vector2.ZERO, {}).get("status", "")) != "too-far":
		_fail("missing poi should be too-far")
		return
	var treasure: Dictionary = _Walk.treasure_choice(Vector2.ZERO, near)
	if str(treasure.get("status", "")) != "walk":
		_fail("treasure inside 48 should walk")
		return
	var landmark: Dictionary = _Walk.landmark_choice(Vector2.ZERO, near)
	if str(landmark.get("poi_kind", "")) != "rock_spire" or str(landmark.get("status", "")) != "walk":
		_fail("landmark should be the spire, got %s" % landmark)
		return
	var goal: Vector2 = _Walk.stand_off(Vector2.ZERO, Vector2(0.0, -40.0), 9.0)
	if goal.distance_to(Vector2(0.0, -31.0)) > 0.01:
		_fail("stand_off landed on %s" % goal)
		return
	var here: Dictionary = _Walk.approach(Vector2(0.0, -8.0), Vector2(0.0, -10.0), 9.0)
	if bool(here.get("walk", true)):
		_fail("inside the treasure radius should only turn")
		return
	var chain: Array = _Walk.exploration_chain(Vector2.ZERO, near)
	if chain.size() != 3:
		_fail("chain should be poi, treasure, landmark")
		return
	if str(chain[0].get("poi_kind", "")) != "camp" or str(chain[0].get("status", "")) != "walk":
		_fail("chain should start at the camp, got %s" % chain[0])
		return
	if str(chain[1].get("tag", "")) != "treasure" or str(chain[2].get("poi_kind", "")) != "rock_spire":
		_fail("chain order %s" % chain)
		return
	var far_only := {
		Vector2i(0, 2000): {"center": Vector2i(0, 2000), "poi_kind": "shrine", "poi": true},
	}
	var skipped: Array = _Walk.exploration_chain(Vector2.ZERO, far_only)
	if skipped.is_empty() or str(skipped[0].get("status", "")) != "too-far":
		_fail("a far-side poi should stay too-far, got %s" % skipped)
		return
	if absf(_Walk.leg_limit(80.0) - 22.0) > 0.01:
		_fail("leg limit for 80 columns should be 22s, got %.2f" % _Walk.leg_limit(80.0))
		return
	_ok("traversal cap and stand-off")


func _check_chapters() -> void:
	var log = _Chapters.new()
	log.begin()
	log.open("movement")
	log.close()
	var body: String = log.text_body()
	if not body.begins_with("movement "):
		_fail("chapter text %s" % body)
		return
	var parts := body.split(" ", false)
	if parts.size() < 3:
		_fail("chapter text needs feature start end")
		return
	var payload: Dictionary = log.payload()
	var rows: Array = payload.get("chapters", [])
	if rows.is_empty() or str(rows[0].get("feature", "")) != "movement":
		_fail("chapter json missing movement")
		return
	if not rows[0].has("start") or not rows[0].has("end"):
		_fail("chapter json missing times")
		return
	if not log.format_clock().contains(":"):
		_fail("clock %s" % log.format_clock())
		return
	_ok("chapters list feature start end")


func _check_sprint_hold() -> void:
	var bot = _Bot.new()
	bot.extra_held = PackedStringArray(["sprint"])
	bot.set_target(Vector2(0.0, -10.0))
	bot.tick(Vector2.ZERO, 0.0, STEP)
	var held: bool = bot.input.is_held("sprint") and bot.input.is_held("move_forward")
	bot.release()
	if not held:
		_fail("sprint did not ride with move_forward")
		return
	if _Nav.face_action(Vector2.ZERO, Vector2(0.0, -4.0), 0.0) != "":
		_fail("already facing north should not rotate")
		return
	_ok("sprint holds with the walk")


func _check_blueprint_key() -> void:
	var hands = _Hands.new()
	hands.pulse_key(KEY_X)
	var down := Input.is_physical_key_pressed(KEY_X)
	hands.begin_tick()
	var up := not Input.is_physical_key_pressed(KEY_X)
	if not down or not up:
		_fail("X key pulse down=%s up=%s" % [down, up])
		return
	_ok("blueprint key is a press and a release")


func _check_roster() -> void:
	var rows: Array = [
		{"id": "a", "kind": "crystal_mite", "xz": Vector2(0.0, 4.0)},
		{"id": "b", "kind": "crystal_stag", "xz": Vector2(10.0, 0.0)},
		{"id": "c", "kind": "crystal_mite", "xz": Vector2(0.0, 40.0)},
	]
	var first: Dictionary = _Roster.pick(rows, Vector2.ZERO, _Roster.SCAN_COLUMNS, {}, true)
	if str(first.get("id", "")) != "a":
		_fail("nearest fresh foe should be the mite, got %s" % first)
		return
	var killed := {"crystal_mite": 1}
	var next: Dictionary = _Roster.pick(rows, Vector2.ZERO, _Roster.SCAN_COLUMNS, killed, true)
	if str(next.get("kind", "")) != "crystal_stag":
		_fail("unkilled stag should beat a repeat mite, got %s" % next)
		return
	var nearer_stag: Array = [
		{"id": "stag", "kind": "crystal_stag", "xz": Vector2(3.0, 0.0)},
		{"id": "mite", "kind": "crystal_mite", "xz": Vector2(0.0, 18.0)},
	]
	var mite_first: Dictionary = _Roster.pick(nearer_stag, Vector2.ZERO, _Roster.SCAN_COLUMNS, {}, true)
	if str(mite_first.get("kind", "")) != "crystal_mite":
		_fail("the first mite comes before a closer stag, got %s" % mite_first)
		return
	var far: Dictionary = _Roster.pick(rows, Vector2.ZERO, _Roster.SCAN_COLUMNS, {"crystal_mite": 1, "crystal_stag": 1}, false)
	if str(far.get("id", "")) != "":
		_fail("mite outside the scan should be ignored, got %s" % far)
		return
	if _Roster.kind_status("crystal_wisp", {}, {}) != "absent":
		_fail("unseen kind should be absent")
		return
	if _Roster.kind_status("crystal_stag", killed, {"crystal_stag": true}) != "fail":
		_fail("a seen stag that is still up should fail")
		return
	if _Roster.kind_status("crystal_mite", killed, {"crystal_mite": true}) != "pass":
		_fail("a killed mite should pass")
		return
	var goal := _Roster.pool_goal(Vector2(0.0, 20.0), Vector2.ZERO, _Roster.POOL_STAND)
	if goal.distance_to(Vector2(0.0, _Roster.POOL_STAND)) > 0.01:
		_fail("pool stand landed on %s" % goal)
		return
	if not _Roster.keep_hunting(2, 3, 1.0, 40.0, 10.0, 165.0, false, false):
		_fail("level 2 should keep hunting mites")
		return
	if _Roster.keep_hunting(3, 3, 2.0, 40.0, 10.0, 165.0, false, false):
		_fail("level 3 with nothing new should stop")
		return
	_ok("combat roster pick and chapter status")


func _check_skill_pad() -> void:
	var dash := _Cast.presses("dash")
	if dash != PackedStringArray(["skill_tree", "ui_down", "ui_accept", "skill_tree"]):
		_fail("dash pad %s" % [dash])
		return
	var slam := _Cast.presses("ground_slam")
	if slam != PackedStringArray(["skill_tree", "ui_right", "ui_accept", "skill_tree"]):
		_fail("ground slam pad %s" % [slam])
		return
	var pulse := _Cast.presses("crystal_pulse")
	if pulse != PackedStringArray(["skill_tree", "ui_accept", "skill_tree"]):
		_fail("pulse pad %s" % [pulse])
		return
	_ok("skill pad matches the tree")


func _check_hud() -> bool:
	var layer = _Hud.new()
	root.add_child(layer)
	await process_frame
	layer.set_readout("0:01.25", "movement")
	await process_frame
	if layer.clock_text != "0:01.25" or layer.chapter_text != "movement":
		layer.queue_free()
		return false
	if layer.get_child_count() < 2:
		layer.queue_free()
		return false
	layer.queue_free()
	_ok("timer and chapter label")
	return true


func _check_live() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		return
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
		_fail("start region not ready")
		return
	for _w in 120:
		await process_frame
		if not _GI.blocks_actions():
			break
	if _GI.blocks_actions():
		_fail("actions still blocked after stream ready")
		return
	var player = get_first_node_in_group("player")
	if player == null or not bool(player.get("world_ready")):
		_fail("player not world_ready")
		return
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		_fail("no crystal origin")
		return
	var heart: Vector2i = crystal.get_origin_cell()
	var show = _Show.new()
	if not show.load_route():
		_fail("route missing at live boot")
		return
	var log = _Chapters.new()
	log.begin()
	var layer = _Hud.new()
	root.add_child(layer)
	show.bind(self, player, Vector2(float(heart.x), float(heart.y)), layer, log)
	var saw_movement := false
	var guard := 0
	while not show.finished and guard < LIVE_FRAMES:
		var delta := root.get_process_delta_time()
		if delta <= 0.0:
			delta = STEP
		show.tick(delta)
		if layer.chapter_text == "movement" and layer.clock_text.contains(":"):
			saw_movement = true
		await process_frame
		guard += 1
	if not show.finished:
		_fail("showcase timed out")
	if show.failed:
		_fail("showcase segment failed")
	if not saw_movement:
		_fail("chapter label never showed movement")
	if not log.write_dir(_Capture.run_dir()):
		_fail("chapters sidecar was not written")
		return
	var text := FileAccess.get_file_as_string("%s/chapters.txt" % _Capture.run_dir())
	if not text.contains("movement ") or not text.contains("day_night "):
		_fail("sidecar missing movement or day_night")
		return
	if not text.contains("density_poi") or not text.contains("density_treasure") or not text.contains("density_landmark"):
		_fail("sidecar missing a density visit")
		return
	if not text.contains("dig_tool ") or not text.contains("structure_place "):
		_fail("sidecar missing dig or structure")
		return
	if not text.contains("structure_wall_segment ") or not text.contains("structure_small_tower "):
		_fail("sidecar missing a structure type")
		return
	if not text.contains("combat_crystal_mite ") or not text.contains("combat_spawn_elite "):
		_fail("sidecar missing an enemy chapter")
		return
	if not text.contains("skill_dash ") or not text.contains("skill_ground_slam "):
		_fail("sidecar missing a skill chapter")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/chapters.json" % _Capture.run_dir()))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("chapters json did not parse")
		return
	if _failed == 0:
		_ok("live movement slice")
