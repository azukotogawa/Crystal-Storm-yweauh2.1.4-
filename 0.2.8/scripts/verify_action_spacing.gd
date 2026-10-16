extends SceneTree

const _Gate = preload("res://player/action_resolve_gate.gd")
const _Config = preload("res://config/game_feel_config.gd")
const _Items = preload("res://helpers/item_types.gd")

const STEP := 1.0 / 60.0

var _failed: int = 0
var _saved_wind: PackedFloat32Array = PackedFloat32Array()
var _saved_recover: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	var feel := root.get_node_or_null("GameFeel")
	if feel == null or feel.config == null:
		_fail("GameFeel config missing")
		_finish()
		return
	_saved_wind = feel.config.telegraph_sec.duplicate()
	_saved_recover = feel.config.recovery_sec.duplicate()
	var player := _host()
	if player == null:
		_restore(feel)
		_finish()
		return
	_check_reads_config(feel, player)
	_check_same_frame(player)
	_check_floor(feel, player)
	_check_all_eight(player)
	player.free()
	_restore(feel)
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("All action spacing tests OK")
		quit(0)
	else:
		push_error("verify_action_spacing: %d failure(s)" % _failed)
		quit(1)


func _host() -> Player:
	_Gate.reset()
	var player := Player.new()
	player.set_process(false)
	player.set_physics_process(false)
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	player.add_child(body)
	root.add_child(player)
	var weapon := player.get_node_or_null("WeaponController") as WeaponController
	if weapon == null:
		_fail("weapon missing")
		player.free()
		return null
	weapon.set_process(false)
	return player


func _weapon(player: Player) -> WeaponController:
	return player.get_node("WeaponController") as WeaponController


func _pump(player: Player, delta: float) -> void:
	player._tick_skill_feel(delta)


func _until_idle(player: Player) -> bool:
	var guard := 0
	while _busy(player) and guard < 600:
		_pump(player, STEP)
		guard += 1
	return not _busy(player)


func _busy(player: Player) -> bool:
	if player._skill_feel.pacing_blocks():
		return true
	return _weapon(player)._tool_feel.pacing_blocks()


func _start(player: Player, id: String) -> bool:
	if player._skill_feel.known(id):
		return player._skill_feel.begin(player, 0, id, Vector2(0.0, 1.0), Vector2(0.0, -1.0))
	var weapon := _weapon(player)
	if id == "sword_swing":
		weapon._feel_item = "wooden_sword"
		weapon._feel_def = _Items.get_def("wooden_sword")
	elif id == "bow_shot":
		weapon._feel_item = "shortbow"
		weapon._feel_def = _Items.get_def("shortbow")
	elif id == "multi_block_break":
		weapon._feel_item = "stone_pick"
		weapon._feel_def = _Items.get_def("stone_pick")
		weapon._listed_break = true
	return weapon._tool_feel.try_begin(weapon, id)


func _check_reads_config(feel, player: Player) -> void:
	for id in _Config.ACTIONS:
		var row: Dictionary = feel.config.action(id)
		if row.is_empty() or float(row["telegraph_sec"]) <= 0.0 or float(row["linger_sec"]) <= 0.0:
			_fail("%s config telegraph or linger is zero" % id)
			continue
		_Gate.reset()
		if not _start(player, id):
			_fail("%s did not start" % id)
			continue
		var wind := 0.0
		var linger := 0.0
		if player._skill_feel.known(id):
			wind = player._skill_feel.wind_sec
			linger = player._skill_feel.linger_sec
			var marker := player.get_node_or_null("SkillTelegraph")
			if marker == null or not marker.visible:
				_fail("%s telegraph is not visible" % id)
		else:
			wind = _weapon(player)._tool_feel.wind_sec
			linger = _weapon(player)._tool_feel.linger_sec
			var marker := player.get_node_or_null("ToolTelegraph")
			if marker == null or not marker.visible:
				_fail("%s telegraph is not visible" % id)
		if absf(wind - float(row["telegraph_sec"])) > 0.001 or absf(linger - float(row["linger_sec"])) > 0.001:
			_fail("%s wind %.3f linger %.3f, config %.3f %.3f" % [id, wind, linger, float(row["telegraph_sec"]), float(row["linger_sec"])])
		if not _until_idle(player):
			_fail("%s did not finish" % id)
	if _failed == 0:
		print("OK action spacing reads config")


func _check_same_frame(player: Player) -> void:
	_Gate.reset()
	if not _start(player, "dash"):
		_fail("dash did not start for the same-frame check")
		return
	if _start(player, "sword_swing"):
		_fail("sword started in the dash wind-up frame")
	if _Gate.resolves.size() != 0:
		_fail("an action resolved inside the wind-up frame")
	_until_idle(player)
	if _failed == 0:
		print("OK action spacing same frame")


func _check_floor(feel, player: Player) -> void:
	_Gate.reset()
	for id in ["sword_swing", "bow_shot"]:
		var index := int(feel.config.action_ids.find(id))
		if index < 0:
			_fail("%s missing from config" % id)
			return
		feel.config.telegraph_sec[index] = 0.05
		feel.config.recovery_sec[index] = 0.0
	if not _start(player, "sword_swing"):
		_fail("short sword did not start")
		_restore(feel)
		return
	_until_idle(player)
	if not _start(player, "bow_shot"):
		_fail("short bow did not start after the sword")
		_restore(feel)
		return
	_until_idle(player)
	var fault := _Gate.distinct_fault()
	if fault != "":
		_fail("short telegraphs resolved inside 150 ms (%s)" % fault)
	elif _Gate.resolves.size() < 2:
		_fail("short pair did not both resolve")
	elif _failed == 0:
		print("OK action spacing 150 ms floor")
	_restore(feel)


func _check_all_eight(player: Player) -> void:
	_Gate.reset()
	var heard: Array[String] = []
	var feel := root.get_node_or_null("GameFeel")
	if feel != null and feel.has_signal("sound_hook"):
		feel.sound_hook.connect(func(cue: String) -> void:
			heard.append(cue)
		)
	for id in _Config.ACTIONS:
		var guard := 0
		while not _start(player, id) and guard < 600:
			_pump(player, STEP)
			guard += 1
		if guard >= 600:
			_fail("%s never started" % id)
			return
		var before := _Gate.resolves.size()
		guard = 0
		while _Gate.resolves.size() == before and guard < 600:
			_pump(player, STEP)
			guard += 1
		if _Gate.resolves.size() == before:
			_fail("%s did not resolve" % id)
			return
		var row: Dictionary = _Gate.resolves[_Gate.resolves.size() - 1]
		if str(row.get("id", "")) != id:
			_fail("resolved %s while waiting for %s" % [str(row.get("id", "")), id])
		var cast_landed := true
		if player._skill_feel.known(id):
			cast_landed = player._skill_feel.landed
		else:
			cast_landed = _weapon(player)._tool_feel.landed
		if cast_landed and not heard.has(id):
			_fail("%s impact did not emit the sound hook" % id)
		if not _until_idle(player):
			_fail("%s recovery did not end" % id)
			return
	var fault := _Gate.distinct_fault()
	if fault != "":
		_fail("distinct actions resolved inside 150 ms (%s)" % fault)
	elif _Gate.resolves.size() < _Config.ACTIONS.size():
		_fail("expected %d resolves, got %d" % [_Config.ACTIONS.size(), _Gate.resolves.size()])
	elif _failed == 0:
		print("OK action spacing eight actions")


func _restore(feel) -> void:
	if feel == null or feel.config == null:
		return
	if _saved_wind.size() > 0:
		feel.config.telegraph_sec = _saved_wind.duplicate()
	if _saved_recover.size() > 0:
		feel.config.recovery_sec = _saved_recover.duplicate()
