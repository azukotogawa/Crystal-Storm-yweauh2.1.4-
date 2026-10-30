extends RefCounted

const _Brain = preload("res://scripts/honest_bot/honest_brain.gd")


func run(fight) -> bool:
	var body := _KiteBody.new()
	var ok := _retreat(fight, body) and _hold(fight, body) and _reengage(fight, body) and _oscillation(fight, body) and _stuck(fight)
	if ok:
		print("HARNESS see kite retreat hold reengage loop")
	body.free()
	return ok


func _retreat(fight, body: Node) -> bool:
	fight.arm_kite()
	_place(body, Vector2.ZERO, Vector2(-1.0, 0.0))
	var foe := Vector2(2.0, 0.0)
	fight._kite_bow(0.05, null, body, fight._xz(body), foe)
	if not fight._kite_armed:
		print("FAIL kite bow not selected")
		return false
	fight._kite_bow(0.05, null, body, fight._xz(body), foe)
	var opened: float = float(fight.bot.home.distance_to(foe)) - float(fight._xz(body).distance_to(foe))
	if fight.kite_move != "retreat" or opened < 1.5 or not fight.kite_fired or not fight.bot.input.is_held("move_forward"):
		print("FAIL kite retreat move %s opened %.2f fire %s" % [fight.kite_move, opened, str(fight.kite_fired)])
		return false
	print("HARNESS kite melee crystal_mite")
	print("HARNESS kite retreat dist %.2f goal %.2f,%.2f fire 1" % [fight._xz(body).distance_to(foe), fight.bot.home.x, fight.bot.home.y])
	return true


func _hold(fight, body: Node) -> bool:
	fight._kite_wait = 0.0
	_place(body, Vector2.ZERO, Vector2(1.0, 0.0))
	var foe := Vector2(6.5, 0.0)
	fight._kite_bow(0.05, null, body, fight._xz(body), foe)
	if fight.kite_move != "hold" or not fight.kite_fired or fight.bot.input.is_held("move_forward") or fight.bot.input.is_held("move_back"):
		print("FAIL kite hold move %s fire %s" % [fight.kite_move, str(fight.kite_fired)])
		return false
	print("HARNESS kite hold dist %.2f fire 1" % fight._xz(body).distance_to(foe))
	return true


func _reengage(fight, body: Node) -> bool:
	fight._kite_wait = 0.0
	_place(body, Vector2.ZERO, Vector2(1.0, 0.0))
	var foe := Vector2(12.0, 0.0)
	var dist: float = float(fight._xz(body).distance_to(foe))
	fight._kite_bow(0.05, null, body, fight._xz(body), foe)
	var left: float = float(fight.bot.home.distance_to(foe))
	if fight.kite_move != "approach" or left >= dist - 0.5 or left < _Brain.NEAR:
		print("FAIL kite reengage move %s dist %.2f left %.2f" % [fight.kite_move, dist, left])
		return false
	print("HARNESS kite reengage dist %.2f goal %.2f,%.2f" % [dist, fight.bot.home.x, fight.bot.home.y])
	return true


func _oscillation(fight, body: Node) -> bool:
	fight.brain.reset()
	fight._kite_armed = true
	var before := int(fight.brain.breaks)
	var seq: Array[float] = [5.0, 8.0, 5.0, 8.0, 5.0, 8.0]
	for x in seq:
		_place(body, Vector2(x, 0.0), Vector2(1.0, 0.0))
		fight._kite_bow(0.05, null, body, fight._xz(body), Vector2.ZERO)
	if int(fight.brain.breaks) != before + 1 or str(fight.brain.tactic) != "sidestep" or str(fight.kite_move) != "sidestep":
		print("FAIL kite loop breaks %d tactic %s move %s" % [int(fight.brain.breaks), str(fight.brain.tactic), str(fight.kite_move)])
		return false
	if absf(fight.bot.home.y) < 1.5:
		print("FAIL kite loop goal %.2f,%.2f" % [fight.bot.home.x, fight.bot.home.y])
		return false
	print("HARNESS kite loop %s" % str(fight.brain.tactic))
	return true


func _stuck(fight) -> bool:
	fight.brain.reset()
	fight.kite_bow = true
	var line := "STUCK nav at 1.00,2.00 moved 0.010 in 1.25s toward 9.00,2.00"
	for _i in 3:
		fight.bot.stuck_lines.append(line)
		fight._flush_stuck()
	if int(fight.brain.breaks) != 1 or str(fight.brain.tactic) != "sidestep":
		print("FAIL kite stuck breaks %d tactic %s" % [int(fight.brain.breaks), str(fight.brain.tactic)])
		return false
	print("HARNESS kite stuck %s" % str(fight.brain.tactic))
	return true


func _place(body: Node, at: Vector2, face: Vector2) -> void:
	body.voxel_position = Vector3(at.x, 1.0, at.y)
	body.camera.yaw_degrees = rad_to_deg(atan2(-face.x, -face.y))


class _KiteCam extends RefCounted:
	var yaw_degrees := 0.0


class _KiteBody extends Node:
	var health := 100.0
	var max_health := 100.0
	var voxel_position := Vector3.ZERO
	var camera = _KiteCam.new()
