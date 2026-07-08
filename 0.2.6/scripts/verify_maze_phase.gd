extends SceneTree
## Ensures origin spawn stays in MAZE phase without crystal damage at tier 0.

const _GameManager = preload("res://game/game_manager.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")


class _PlayerStub extends Node3D:
	func get_voxel_position() -> Vector3:
		return Vector3(0.5, 2.0, 0.5)

	func take_damage(_amount: float) -> void:
		pass

	func get_stat(_id: StringName) -> float:
		return 0.0


func _init() -> void:
	var failed := false
	var gm := _GameManager.new()
	gm.phase = _GameManager.Phase.MAZE
	var crystal := _CrystalManager.new()
	crystal.strength_tier = 0
	gm._crystal = crystal
	var stub := _PlayerStub.new()
	gm._player = stub

	gm._update_phase()
	if gm.phase != _GameManager.Phase.MAZE:
		push_error("tier 0 at origin should stay MAZE, got %d" % gm.phase)
		failed = true
	else:
		print("OK origin tier0 phase MAZE")

	crystal.strength_tier = 2
	gm._update_phase()
	if gm.phase != _GameManager.Phase.ASSAULT:
		push_error("tier 2 near origin should be ASSAULT")
		failed = true
	else:
		print("OK tier2 near origin phase ASSAULT")

	stub.free()
	crystal.free()
	gm.free()

	if failed:
		quit(1)
	print("All maze phase tests OK")
	quit(0)