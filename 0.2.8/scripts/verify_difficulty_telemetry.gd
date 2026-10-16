extends SceneTree

var _failed := false


class _PlayerStub extends Node:
	signal damage_taken(amount: float, source: StringName)
	signal died


class _EnemyStub extends Node3D:
	signal combat_damaged(amount: float, remaining_health: float, source: StringName)
	signal killed(enemy_id: StringName, world_pos: Vector2i, player_killed: bool)


class _WildlifeStub extends Node3D:
	signal combat_damaged(amount: float, remaining_health: float, source: StringName)
	signal died(entity: Node, world_pos: Vector2i)
	var entity_kind: StringName = &"rabbit"


class _ProgressStub extends Node:
	signal xp_gained(amount: int, xp: int)
	signal level_up(level: int)
	var level: int = 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("CRYSTALSTORM_EVIDENCE", "D:/csmerge/verify-scratch/telemetry-verify-08")
	OS.set_environment("CRYSTALSTORM_RUN_ID", "")
	_check_rates()
	_check_player_source()
	await _check_signals()
	if _failed:
		quit(1)
		return
	print("All difficulty telemetry tests OK")
	quit(0)


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	_failed = true


func _check_rates() -> void:
	var tele := root.get_node_or_null("DifficultyTelemetry")
	if tele == null:
		_fail("DifficultyTelemetry autoload missing")
		return
	if absf(tele.xp_per_minute(120, 30000) - 240.0) > 0.001:
		_fail("xp per minute math")
	if tele.xp_per_minute(10, 0) != 0.0 or tele.xp_per_minute(0, 30000) != 0.0:
		_fail("xp per minute should be zero without time or xp")
	var math: Dictionary = tele.ttk_summary(2, 1500, 400, 1100)
	if int(math.get("kills", 0)) != 2:
		_fail("ttk summary kills")
	if absf(float(math.get("mean_msec", 0.0)) - 750.0) > 0.001:
		_fail("ttk summary mean")
	if int(math.get("min_msec", 0)) != 400 or int(math.get("max_msec", 0)) != 1100:
		_fail("ttk summary span")


func _check_player_source() -> void:
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	if not body.contains("signal damage_taken(amount: float, source: StringName)"):
		_fail("player is missing damage_taken")
		return
	var at := body.find("func take_damage")
	var next := body.find("\nfunc ", at + 10)
	var fn := body.substr(at, next - at)
	var health_at := fn.find("health = maxf(health - amount, 0.0)")
	var emit_at := fn.find("damage_taken.emit(amount, kind)")
	var iframe_at := fn.find("if burst and _hit_iframes > 0.0:")
	var dash_at := fn.find("if _dash_invuln > 0.0:")
	if health_at < 0 or emit_at < health_at:
		_fail("damage_taken must emit the amount that landed")
	if iframe_at < 0 or dash_at < 0 or iframe_at > emit_at or dash_at > emit_at:
		_fail("a skipped hit must not emit damage_taken")


func _check_signals() -> void:
	var tele := root.get_node_or_null("DifficultyTelemetry")
	if tele == null:
		_fail("DifficultyTelemetry autoload missing")
		return
	tele.begin_session()
	var session_before: String = tele.session_id
	if session_before == "":
		_fail("session id is empty")
	var player := _PlayerStub.new()
	player.add_to_group("player")
	root.add_child(player)
	var foe := _EnemyStub.new()
	foe.add_to_group("crystal_enemy")
	root.add_child(foe)
	var deer := _WildlifeStub.new()
	deer.add_to_group("world_entity")
	root.add_child(deer)
	var prog := _ProgressStub.new()
	prog.add_to_group("progression_service")
	root.add_child(prog)
	await process_frame
	await process_frame
	tele.begin_session()
	if tele.session_id == "" or tele.session_id == session_before:
		_fail("begin_session did not mint a new id")
	player.damage_taken.emit(9.0, &"crystal_mite")
	player.damage_taken.emit(1.5, &"crystal_mite")
	player.damage_taken.emit(4.0, &"")
	player.died.emit()
	foe.combat_damaged.emit(4.0, 20.0, &"sword")
	foe.combat_damaged.emit(6.0, 14.0, &"sword")
	OS.delay_msec(120)
	foe.killed.emit(&"crystal_mite", Vector2i(1, 2), true)
	deer.combat_damaged.emit(2.0, 5.0, &"spear")
	deer.died.emit(deer, Vector2i(3, 4))
	prog.xp_gained.emit(10, 10)
	prog.xp_gained.emit(20, 30)
	prog.level_up.emit(2)
	var snap: Dictionary = tele.snapshot()
	if str(snap.get("session_id", "")) != tele.session_id:
		_fail("snapshot session id drifted")
	if int(snap.get("player_deaths", -1)) != 1:
		_fail("player deaths %s" % str(snap.get("player_deaths")))
	if absf(float(snap.get("damage_taken", 0.0)) - 14.5) > 0.01:
		_fail("damage taken %.3f" % float(snap.get("damage_taken", 0.0)))
	if absf(tele.damage_dealt(&"sword") - 10.0) > 0.01:
		_fail("sword damage %.3f" % tele.damage_dealt(&"sword"))
	if absf(tele.damage_dealt(&"spear") - 2.0) > 0.01:
		_fail("spear damage %.3f" % tele.damage_dealt(&"spear"))
	var dealt: Dictionary = snap.get("damage_dealt_by_source", {})
	if absf(float(dealt.get("sword", 0.0)) - 10.0) > 0.01:
		_fail("dealt map missing sword")
	var rows: Array = snap.get("events", [])
	var taken_rows := 0
	var sword_rows := 0
	var deaths := 0
	var saw_player := false
	var saw_mite := false
	var saw_rabbit := false
	var saw_unknown := false
	for row in rows:
		if str(row.get("session_id", "")) != tele.session_id:
			_fail("event missing session id")
		if float(row.get("t_unix", 0.0)) <= 0.0 or int(row.get("t_msec", 0)) < 0:
			_fail("event missing timestamp")
		var kind := str(row.get("kind", ""))
		if kind == "damage_taken":
			taken_rows += 1
			if str(row.get("source", "")) == "unknown":
				saw_unknown = true
			if str(row.get("source", "")) == "crystal_mite" and absf(float(row.get("amount", 0.0)) - 10.5) > 0.01:
				_fail("mite hits did not merge, amount %s" % str(row.get("amount")))
		elif kind == "damage_dealt" and str(row.get("source", "")) == "sword":
			sword_rows += 1
			if absf(float(row.get("amount", 0.0)) - 10.0) > 0.01:
				_fail("sword hits did not merge")
		elif kind == "death":
			deaths += 1
			var actor := str(row.get("actor", ""))
			if actor == "player":
				saw_player = true
			elif actor == "crystal_mite":
				saw_mite = true
			elif actor == "rabbit":
				saw_rabbit = true
	if taken_rows != 2:
		_fail("expected 2 damage_taken rows, got %d" % taken_rows)
	if sword_rows != 1:
		_fail("expected 1 sword row, got %d" % sword_rows)
	if deaths != 3 or not saw_player or not saw_mite or not saw_rabbit or not saw_unknown:
		_fail("death rows player=%s mite=%s rabbit=%s unknown=%s count=%d" % [saw_player, saw_mite, saw_rabbit, saw_unknown, deaths])
	var mite: Dictionary = tele.time_to_kill("crystal_mite")
	if int(mite.get("kills", 0)) != 1:
		_fail("mite kills %s" % str(mite.get("kills")))
	if int(mite.get("min_msec", 0)) < 40:
		_fail("mite ttk %s" % str(mite.get("min_msec")))
	if absf(float(mite.get("mean_msec", 0.0)) - float(mite.get("total_msec", 0))) > 0.01:
		_fail("mite mean drifted")
	var rabbit: Dictionary = tele.time_to_kill("rabbit")
	if int(rabbit.get("kills", 0)) != 1:
		_fail("rabbit kills %s" % str(rabbit.get("kills")))
	var rate: Dictionary = tele.xp_snapshot()
	if int(rate.get("gained", 0)) != 30:
		_fail("xp gained %s" % str(rate.get("gained")))
	if int(rate.get("level", 0)) != 2:
		_fail("xp level %s" % str(rate.get("level")))
	var ups: Array = rate.get("level_ups", [])
	if ups.size() != 1 or int(ups[0].get("level", 0)) != 2:
		_fail("level ups %s" % str(ups))
	if float(ups[0].get("t_unix", 0.0)) <= 0.0 or int(ups[0].get("elapsed_msec", -1)) < 0:
		_fail("level up missing time")
	var elapsed := int(rate.get("elapsed_msec", 0))
	if absf(float(rate.get("per_minute", -1.0)) - tele.xp_per_minute(30, elapsed)) > 0.001:
		_fail("xp rate %.4f" % float(rate.get("per_minute", -1.0)))
	var written: String = tele.flush()
	var user_body := FileAccess.get_file_as_string(tele.user_json_path())
	var evidence_body := FileAccess.get_file_as_string(tele.evidence_json_path())
	if user_body == "" or user_body != evidence_body:
		_fail("session json missing user=%s evidence=%s" % [tele.user_json_path(), tele.evidence_json_path()])
	var parsed = JSON.parse_string(user_body)
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("session_id", "")) != tele.session_id:
		_fail("session json did not parse")
	var file_xp: Dictionary = parsed.get("xp", {})
	if int(file_xp.get("gained", 0)) != 30:
		_fail("file xp %s" % str(file_xp.get("gained")))
	var file_ups: Array = file_xp.get("level_ups", [])
	if file_ups.size() != 1 or int(file_ups[0].get("level", 0)) != 2:
		_fail("file level ups")
	var file_ttk: Dictionary = parsed.get("time_to_kill", {})
	var file_mite: Dictionary = file_ttk.get("crystal_mite", {})
	if int(file_mite.get("kills", 0)) != 1:
		_fail("file mite ttk")
	if not str(written).ends_with(".json"):
		_fail("flush path %s" % written)
	OS.set_environment("CRYSTALSTORM_EVIDENCE", "")
	OS.set_environment("CRYSTALSTORM_RUN_ID", "telemetry-verify-08")
	tele.flush()
	var run_path: String = tele.evidence_json_path()
	var run_body := FileAccess.get_file_as_string(run_path)
	var run_parsed = JSON.parse_string(run_body)
	if typeof(run_parsed) != TYPE_DICTIONARY or str(run_parsed.get("session_id", "")) != tele.session_id:
		_fail("run id copy %s" % run_path)
	if not run_path.begins_with("D:/ARCHIVE/CrystalStorm/verify-evidence/telemetry-verify-08/telemetry/"):
		_fail("run id path %s" % run_path)
	print("TELEMETRY JSON %s" % run_path)
	player.queue_free()
	foe.queue_free()
	deer.queue_free()
	prog.queue_free()
	await process_frame
