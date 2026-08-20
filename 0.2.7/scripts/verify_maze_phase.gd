extends SceneTree
## MAZE stays while crystal is weak or far; ASSAULT when tiered and near crystal.

const _GameManager = preload("res://game/game_manager.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")


class _PlayerStub extends Node3D:
	var _pos := Vector3(0.5, 2.0, 0.5)

	func get_voxel_position() -> Vector3:
		return _pos

	func take_damage(_amount: float) -> void:
		pass

	func get_stat(_id: StringName) -> float:
		return 0.0


class _CrystalStub extends Node:
	var strength_tier: int = 0
	var expansion_enabled: bool = true
	var _near_dist: float = 10.0
	var strength_tier_public: int = 0

	func get_nearest_crystal_distance(_from: Vector3) -> float:
		return _near_dist

	func get_active_spawns() -> Array:
		return []

	func get_coverage_ratio() -> float:
		return 0.0


func _init() -> void:
	var failed := false
	var gm := _GameManager.new()
	gm.phase = _GameManager.Phase.MAZE
	gm.assault_distance = 48.0
	gm.maze_min_distance = 72.0
	var crystal := _CrystalStub.new()
	crystal.strength_tier = 0
	gm._crystal = crystal
	var stub := _PlayerStub.new()
	gm._player = stub

	gm._update_phase()
	if gm.phase != _GameManager.Phase.MAZE:
		push_error("tier 0 should stay MAZE, got %d" % gm.phase)
		failed = true
	else:
		print("OK tier0 phase MAZE (prep time)")

	# Tiered but still far from crystal → stay MAZE
	crystal.strength_tier = 2
	crystal._near_dist = 120.0
	gm._update_phase()
	if gm.phase != _GameManager.Phase.MAZE:
		push_error("tiered but far should stay MAZE")
		failed = true
	else:
		print("OK tiered+far remains MAZE")

	# Tiered and near → ASSAULT
	crystal._near_dist = 30.0
	gm._update_phase()
	if gm.phase != _GameManager.Phase.ASSAULT:
		push_error("tiered+near should be ASSAULT")
		failed = true
	else:
		print("OK tiered+near phase ASSAULT")

	# Pull back past hysteresis → MAZE again
	crystal._near_dist = 90.0
	gm._update_phase()
	if gm.phase != _GameManager.Phase.MAZE:
		push_error("far retreat should return to MAZE")
		failed = true
	else:
		print("OK retreat past maze_min_distance → MAZE")

	# Hysteresis: once ASSAULT, stay until beyond maze_min
	crystal._near_dist = 30.0
	gm._update_phase()
	crystal._near_dist = 60.0  # between assault 48 and maze 72
	gm._update_phase()
	if gm.phase != _GameManager.Phase.ASSAULT:
		push_error("hysteresis should keep ASSAULT at dist 60")
		failed = true
	else:
		print("OK ASSAULT hysteresis holds at mid distance")

	stub.free()
	crystal.free()
	gm.free()

	if failed:
		quit(1)
	print("All maze phase tests OK")
	quit(0)
