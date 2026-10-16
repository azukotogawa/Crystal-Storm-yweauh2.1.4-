extends RefCounted

const ARRIVE_COLUMNS := 1.25
const ALIGN_DOT := 0.9510565
const STUCK_WINDOW_SEC := 1.25
const STUCK_MIN_COLUMNS := 0.35
const NUDGE_AFTER_SEC := 0.45
const NUDGE_MAX_COLUMNS := 0.18
const RECOVER_SEC := 0.55
const MAX_STUCK_REPORTS := 3
const YAW_SPEED_DEG := 90.0


static func world_delta(input: Vector2, yaw_degrees: float) -> Vector2:
	var rad := deg_to_rad(yaw_degrees)
	var ca := cos(rad)
	var sa := sin(rad)
	return Vector2(input.x * ca + input.y * sa, input.y * ca - input.x * sa)


static func choose(from_xz: Vector2, to_xz: Vector2, yaw_degrees: float) -> Dictionary:
	var offset := to_xz - from_xz
	if offset.length() <= ARRIVE_COLUMNS:
		return {"arrived": true, "rotate": "", "move": ""}
	var facing := world_delta(Vector2(0.0, -1.0), yaw_degrees).normalized()
	var desired := offset.normalized()
	var cross := facing.x * desired.y - facing.y * desired.x
	var dot := facing.dot(desired)
	var rotate := ""
	if absf(cross) < 0.08 and dot < 0.0:
		rotate = "rotate_right"
	elif cross < -0.08:
		rotate = "rotate_right"
	elif cross > 0.08:
		rotate = "rotate_left"
	var move := ""
	if dot >= ALIGN_DOT:
		move = "move_forward"
	return {"arrived": false, "rotate": rotate, "move": move}


static func stuck_line(pos: Vector2, moved: float, span: float, goal: Vector2) -> String:
	return "STUCK nav at %.2f,%.2f moved %.3f in %.2fs toward %.2f,%.2f" % [
		pos.x, pos.y, moved, span, goal.x, goal.y
	]


class StuckWatch extends RefCounted:
	var window_sec := STUCK_WINDOW_SEC
	var min_columns := STUCK_MIN_COLUMNS
	var last_moved := 0.0
	var last_span := 0.0
	var _origin := Vector2.ZERO
	var _age := 0.0
	var _armed := false

	func reset() -> void:
		_armed = false
		_age = 0.0
		last_moved = 0.0
		last_span = 0.0

	func note_idle(pos: Vector2) -> void:
		_origin = pos
		_age = 0.0
		_armed = true
		last_moved = 0.0

	func sample(pos: Vector2, delta: float) -> bool:
		if not _armed:
			_origin = pos
			_armed = true
			_age = 0.0
			return false
		_age += delta
		last_moved = pos.distance_to(_origin)
		if _age < window_sec:
			return false
		last_span = _age
		var blocked := last_moved < min_columns
		_origin = pos
		_age = 0.0
		return blocked

	func should_nudge() -> bool:
		return _armed and _age >= NUDGE_AFTER_SEC and last_moved < NUDGE_MAX_COLUMNS
