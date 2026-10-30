extends RefCounted

const NEAR := 4.2
const FAR := 9.0
const SWEET := 6.5
const BOW_RANGE := 14.0
const STEP := 4.0
const FLIP_LIMIT := 4
const STUCK_LIMIT := 3
const WINDOW := 8
const MOVE_EPS := 0.2

var tactic := "kite"
var breaks := 0
var _radial: Array[int] = []
var _stuck: Array[String] = []
var _prev_dist := -1.0


func reset() -> void:
	tactic = "kite"
	breaks = 0
	_radial = []
	_stuck = []
	_prev_dist = -1.0


func note_place(player: Vector2, foe: Vector2) -> Dictionary:
	var dist := player.distance_to(foe)
	if _prev_dist >= 0.0:
		var delta := dist - _prev_dist
		if absf(delta) >= MOVE_EPS:
			var sign := 1 if delta > 0.0 else -1
			_radial.append(sign)
			if _radial.size() > WINDOW:
				_radial.remove_at(0)
	_prev_dist = dist
	return _maybe_switch("flips", _flip_count())


func note_stuck(line: String) -> Dictionary:
	var key := line.strip_edges()
	if key == "":
		return {}
	_stuck.append(key)
	if _stuck.size() > WINDOW:
		_stuck.remove_at(0)
	return _maybe_switch("stuck", _stuck_count())


func decide(dist: float) -> Dictionary:
	var move := _move_for(tactic, dist)
	var fire := false
	if dist <= BOW_RANGE and dist >= 0.4:
		fire = move != "approach" or dist <= FAR
	return {"move": move, "fire": fire, "tactic": tactic}


func goal(player: Vector2, foe: Vector2, move: String) -> Vector2:
	var away := player - foe
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	var side := Vector2(-away.y, away.x)
	if move == "retreat":
		return player + away * STEP
	if move == "sidestep":
		var out := player + side * STEP
		if player.distance_to(foe) < NEAR:
			out = player + away * 2.0 + side * STEP
		return out
	if move == "approach":
		var stop := SWEET
		if tactic == "close":
			stop = NEAR + 0.8
		var dist := player.distance_to(foe)
		var travel := minf(maxf(dist - stop, 0.0), STEP)
		if travel < 0.2:
			return player
		return player + (-away) * travel
	return player


func _move_for(name: String, dist: float) -> String:
	if name == "sidestep":
		return "sidestep"
	if name == "close":
		if dist < NEAR - 1.0:
			return "retreat"
		if dist > NEAR + 0.8:
			return "approach"
		return "hold"
	if dist < NEAR:
		return "retreat"
	if dist > FAR:
		return "approach"
	return "hold"


func _flip_count() -> int:
	var flips := 0
	var prev := 0
	for sign in _radial:
		if prev != 0 and int(sign) != prev:
			flips += 1
		prev = int(sign)
	return flips


func _stuck_count() -> int:
	if _stuck.is_empty():
		return 0
	var last := _stuck[_stuck.size() - 1]
	var n := 0
	for key in _stuck:
		if key == last:
			n += 1
	return n


func _maybe_switch(reason: String, count: int) -> Dictionary:
	var limit := FLIP_LIMIT if reason == "flips" else STUCK_LIMIT
	if count < limit:
		return {}
	var frm := tactic
	tactic = _next(tactic)
	breaks += 1
	_radial = []
	_stuck = []
	_prev_dist = -1.0
	return {"broke": true, "from": frm, "to": tactic, "reason": reason, "count": count}


func _next(name: String) -> String:
	if name == "kite":
		return "sidestep"
	if name == "sidestep":
		return "close"
	return "kite"
