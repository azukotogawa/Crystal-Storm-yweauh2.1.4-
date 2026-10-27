extends SceneTree

const _FacePick = preload("res://player/face_pick.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")


class FakeWorld:
	extends RefCounted
	var heights := {}
	var flat := 2

	func get_surface_height(x: float, z: float) -> float:
		var key := Vector2i(int(floor(x)), int(floor(z)))
		return float(heights.get(key, flat)) * _WorldSettings.get_active().voxel_scale


var _failed := 0


func _init() -> void:
	var world := FakeWorld.new()
	var scale: float = _WorldSettings.get_active().voxel_scale
	var reach: float = _GameFeelConfig.active().brush_reach
	if absf(reach - 4.5) > 0.001:
		_fail("reach default %.2f want 4.5" % reach)
	var eye := Vector3(0.5, 3.0 + _FacePick.EYE_HEIGHT, 0.5)
	var dir := Vector3(0.5, -0.7, 0.5).normalized()

	world.heights[Vector2i(3, 0)] = 3
	var aim := Vector3(3.5, 4.0, 0.5)
	var hit: Dictionary = _FacePick.pick(world, (aim - dir * 40.0) * scale, dir, eye, reach)
	if not bool(hit.hit) or hit.cell != Vector3i(3, 3, 0) or hit.normal != Vector3i(0, 1, 0):
		_fail("block 3 away not picked on its top face: %s" % str(hit))
	world.heights[Vector2i(3, 0)] = 2
	var after_aim := Vector3(3.5, 3.0, 0.5)
	var again: Dictionary = _FacePick.pick(world, (after_aim - dir * 40.0) * scale, dir, eye, reach)
	if not bool(again.hit) or again.place != Vector3i(3, 3, 0):
		_fail("after break the face above is not the cell to place into: %s" % str(again))
	world.heights[Vector2i(3, 0)] = 3
	if not _FacePick.exposed(world, Vector3i(3, 3, 0), Vector3i(0, 1, 0)):
		_fail("top face should be exposed")

	var far_world := FakeWorld.new()
	far_world.heights[Vector2i(7, 0)] = 3
	var far_aim := Vector3(7.5, 4.0, 0.5)
	var far: Dictionary = _FacePick.pick(far_world, (far_aim - dir * 40.0) * scale, dir, eye, reach)
	if bool(far.hit):
		_fail("block 7 away selected: %s" % str(far))

	var buried := FakeWorld.new()
	if _FacePick.exposed(buried, Vector3i(3, 1, 0), Vector3i(1, 0, 0)):
		_fail("side face between two solid cells reported exposed")
	if _FacePick.exposed(buried, Vector3i(3, 1, 0), Vector3i(0, -1, 0)):
		_fail("buried bottom face reported exposed")
	var inside: Dictionary = _FacePick.pick(buried, Vector3(3.5, 1.5, 0.5) * scale, dir, eye, reach)
	if bool(inside.hit):
		_fail("ray starting inside solid selected %s" % str(inside))

	var cliff := FakeWorld.new()
	cliff.heights[Vector2i(3, 0)] = 5
	var side: Dictionary = _FacePick.pick(cliff, Vector3(-30.0, 4.5, 0.5) * scale, Vector3.RIGHT, eye, reach)
	if not bool(side.hit) or side.normal != Vector3i(-1, 0, 0) or side.place != Vector3i(2, 4, 0):
		_fail("side face of a cliff: %s" % str(side))

	if _failed == 0:
		print("All placement targeting tests OK")
		quit(0)
	else:
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)
