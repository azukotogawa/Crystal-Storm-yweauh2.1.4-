extends SceneTree

const _CombatHitbox = preload("res://systems/combat_hitbox.gd")


class FakeEnemy:
	extends Node3D

	func get_combat_center() -> Vector3:
		return global_position

	func get_combat_radius() -> float:
		return 1.0

	func is_combat_alive() -> bool:
		return true


var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _enemy(at: Vector3) -> FakeEnemy:
	var e := FakeEnemy.new()
	root.add_child(e)
	e.global_position = at
	return e


func _run() -> void:
	var player := Vector3(0, 1, 0)
	var dir := Vector3(-0.5, -0.7, -0.5).normalized()
	var beside := _enemy(Vector3(0, 1, 3))
	var behind := _enemy(Vector3(-3, 1, 0))
	var far := _enemy(Vector3(20, 1, 0))
	var nodes: Array = [beside, behind, far]
	var facing := Vector3(1, 0, 0)

	for target in [beside, behind]:
		var center: Vector3 = target.global_position
		var ray_origin: Vector3 = center - dir * 30.0
		var picked := _CombatHitbox.pick_under_ray(nodes, ray_origin, dir, player, 5.0, 0.4)
		if picked != target:
			_fail("cursor on an enemy outside the facing cone did not pick it")
		var to_target := (center - player).normalized()
		if to_target.dot(facing) > 0.5:
			_fail("fixture enemy is inside the facing cone")

	var empty_origin := Vector3(10, 1, -8) - dir * 30.0
	if _CombatHitbox.pick_under_ray(nodes, empty_origin, dir, player, 5.0, 0.4) != null:
		_fail("cursor on empty ground picked something")
	var far_origin := far.global_position - dir * 30.0
	if _CombatHitbox.pick_under_ray(nodes, far_origin, dir, player, 5.0, 0.4) != null:
		_fail("enemy beyond range was picked")

	if _failed == 0:
		print("All melee cursor checks OK")
		quit(0)
	else:
		quit(1)
