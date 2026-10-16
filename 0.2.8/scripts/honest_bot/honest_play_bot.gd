extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")

var input = _Hands.new()
var watch = _Nav.StuckWatch.new()
var target := Vector2.ZERO
var has_target := false
var arrived := false
var gave_up := false
var stuck_lines: PackedStringArray = PackedStringArray()
var _recover_left := 0.0
var _strafe := "move_left"


func set_target(column_xz: Vector2) -> void:
	target = column_xz
	has_target = true
	arrived = false
	gave_up = false
	stuck_lines = PackedStringArray()
	_recover_left = 0.0
	watch.reset()


func release() -> void:
	input.release_all()


func tick(player_xz: Vector2, yaw_degrees: float, delta: float) -> void:
	input.begin_tick()
	if not has_target or arrived or gave_up:
		input.release_all()
		return
	var step := minf(maxf(delta, 0.0), 0.05)
	var plan: Dictionary = _Nav.choose(player_xz, target, yaw_degrees)
	if bool(plan.get("arrived", false)):
		arrived = true
		input.release_all()
		return
	input.set_held(_actions(plan, step))
	if not _moving():
		watch.note_idle(player_xz)
		return
	if not watch.sample(player_xz, step):
		return
	stuck_lines.append(_Nav.stuck_line(player_xz, watch.last_moved, watch.last_span, target))
	if stuck_lines.size() >= _Nav.MAX_STUCK_REPORTS:
		gave_up = true
		input.release_all()
		return
	_start_recover()
	input.set_held(_recover_actions())
	input.pulse(&"jump")


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
	return out


func _recover_actions() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append(_strafe)
	return out


func _start_recover() -> void:
	_strafe = "move_right" if _strafe == "move_left" else "move_left"
	_recover_left = _Nav.RECOVER_SEC


func _moving() -> bool:
	return input.is_held("move_forward") or input.is_held("move_back") \
		or input.is_held("move_left") or input.is_held("move_right")
