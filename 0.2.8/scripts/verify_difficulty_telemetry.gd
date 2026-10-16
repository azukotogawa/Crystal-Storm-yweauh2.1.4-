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


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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
	foe.killed.emit(&"crystal_mite", Vector2i(1, 2), true)
	deer.combat_damaged.emit(2.0, 5.0, &"spear")
	deer.died.emit(deer, Vector2i(3, 4))
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
	player.queue_free()
	foe.queue_free()
	deer.queue_free()
	await process_frame
