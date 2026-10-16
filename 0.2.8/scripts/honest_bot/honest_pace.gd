extends RefCounted

const GAP := 0.15
const PRE_PAUSE := 1.0
const RESULT_HOLD := 2.5
const SETTLE := 1.0
const MIN_CHAPTER := 4.0


static func short_feature(body: String) -> String:
	for raw in body.split("\n", false):
		var line := raw.strip_edges()
		if line == "":
			continue
		var parts := line.split(" ", false)
		if parts.size() < 3:
			return str(parts[0]) if parts.size() > 0 else "?"
		var span := float(parts[parts.size() - 1]) - float(parts[parts.size() - 2])
		if span < MIN_CHAPTER:
			return str(parts[0])
	return ""


const STRIKE_PAD := 0.02


static func action_span(id: String) -> float:
	var row := _action(id)
	if row.is_empty():
		return 0.4
	return float(row["telegraph_sec"]) + float(row["recovery_sec"])


static func strike_gap(id: String) -> float:
	return action_span(id) + STRIKE_PAD


static func banner_span(id: String) -> float:
	var loaded = _feel()
	if loaded != null and loaded.has_method("beat"):
		var row: Dictionary = loaded.beat(id)
		if not row.is_empty():
			return float(row["banner_sec"])
		return float(loaded.banner_sec)
	return RESULT_HOLD


static func beat_hold(id: String) -> float:
	return maxf(RESULT_HOLD, banner_span(id))


static func enemy_span(id: String) -> float:
	if id == "":
		return 0.0
	var loaded = _feel()
	if loaded != null and loaded.has_method("enemy"):
		var row: Dictionary = loaded.enemy(id)
		if not row.is_empty():
			return float(row["telegraph_sec"])
	return 0.0


static func _feel():
	return load("res://config/default_game_feel.tres")


static func _action(id: String) -> Dictionary:
	var loaded = _feel()
	if loaded != null and loaded.has_method("action"):
		return loaded.action(id)
	return {}


static func gap_fault(hands: RefCounted) -> String:
	if hands == null:
		return "no input"
	hands.pace_presses = true
	hands._since_press = GAP
	if not hands.pulse("attack"):
		return "first press blocked"
	if hands.pulse("jump"):
		return "same-frame chain"
	hands.advance_pace(GAP - 0.02)
	if hands.pulse("jump"):
		return "gap short"
	hands.advance_pace(0.03)
	if not hands.pulse("jump"):
		return "gap not open"
	if hands.pulse("pause"):
		return "second chain"
	hands.begin_tick()
	hands.release_all()
	return ""
