extends SceneTree
## Pitch clamps, legacy iso offset, and the same cell is picked at both pitch limits.

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	var cam: Camera3D = Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	var anchor := Node3D.new()
	root.add_child(anchor)
	root.add_child(cam)
	await process_frame
	cam.target = anchor
	cam.use_smoothing = false
	var iso: float = float(cam.ISO_PITCH_DEG)
	var off: Vector3 = cam.get_offset_from_rotation()
	if absf(off.y - float(cam.height_offset)) > 0.001:
		_fail("default pitch offset y %.3f want height_offset %.3f" % [off.y, float(cam.height_offset)])
	else:
		_ok("default pitch keeps legacy height_offset")
	cam.snap_yaw_degrees(12.0)
	var y_a: float = cam.get_offset_from_rotation().y
	cam.snap_yaw_degrees(140.0)
	var y_b: float = cam.get_offset_from_rotation().y
	if absf(y_a - y_b) > 0.001 or absf(y_a - float(cam.height_offset)) > 0.001:
		_fail("iso pitch offset y drifted across yaw (%.3f vs %.3f)" % [y_a, y_b])
	else:
		_ok("iso pitch offset y stays constant across yaw")

	cam.snap_pitch_degrees(-90.0)
	if absf(float(cam.pitch_degrees) - float(cam.PITCH_MIN_DEG)) > 0.01:
		_fail("pitch -90 clamped to %.3f want %.3f" % [float(cam.pitch_degrees), float(cam.PITCH_MIN_DEG)])
	else:
		_ok("pitch clamps at %.1f" % float(cam.PITCH_MIN_DEG))
	cam.snap_pitch_degrees(10.0)
	if absf(float(cam.pitch_degrees) - float(cam.PITCH_MAX_DEG)) > 0.01:
		_fail("pitch +10 clamped to %.3f want %.3f" % [float(cam.pitch_degrees), float(cam.PITCH_MAX_DEG)])
	else:
		_ok("pitch clamps at %.1f" % float(cam.PITCH_MAX_DEG))
	cam.snap_pitch_degrees(iso)
	if absf(cam.get_offset_from_rotation().y - float(cam.height_offset)) > 0.001:
		_fail("returning to iso pitch did not restore the legacy offset")
	else:
		_ok("iso pitch restores the legacy offset")
	if absf(cam.rotation_degrees.x - iso) > 0.05:
		_fail("rotation.x %.3f after iso snap" % cam.rotation_degrees.x)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	root.add_child(world)
	await process_frame
	var cell := _find_land(world)
	var ws = _WorldSettings.get_active()
	var surf: float = world.get_surface_height(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var top_y: float = surf + ws.layer_height()
	var aim := Vector3(
		ws.column_to_world(float(cell.x) + 0.5),
		top_y - 0.08,
		ws.column_to_world(float(cell.y) + 0.5)
	)
	var player := _Dummy.new()
	player.voxel_position = Vector3(float(cell.x) + 0.5, surf, float(cell.y) + 0.5)
	root.add_child(player)
	var faces: Array[int] = []
	for pitch in [float(cam.PITCH_MIN_DEG), float(cam.PITCH_MAX_DEG)]:
		cam.snap_pitch_degrees(pitch)
		cam.snap_yaw_degrees(45.0)
		var origin: Vector3 = player.global_position + cam.get_offset_from_rotation()
		# Aim through the top face. The orbit position is only the view point.
		origin = aim + Vector3(0.15, 8.0 + absf(pitch) * 0.05, 0.1)
		var dir: Vector3 = (aim - origin).normalized()
		var pick: Dictionary = _ActionTargeting.pick_along_ray(
			origin, dir, player, world, null, _ActionTargeting.INTERACTION_RANGE, true
		)
		if not bool(pick.get("hit", false)):
			_fail("pitch %.1f ray missed the cell" % pitch)
			continue
		var col: Vector3 = pick.get("column", Vector3.ZERO)
		if floori(col.x) != cell.x or floori(col.z) != cell.y:
			_fail("pitch %.1f picked (%s,%s) want (%s,%s)" % [pitch, floori(col.x), floori(col.z), cell.x, cell.y])
		elif int(pick.get("face", -1)) != 0:
			_fail("pitch %.1f face %s want top" % [pitch, int(pick.get("face", -1))])
		else:
			faces.append(int(pick.get("face", -1)))
			_ok("pitch %.1f hits cell %s face top" % [pitch, cell])
	if faces.size() == 2 and faces[0] == faces[1]:
		_ok("min and max pitch pick the same face")

	if _failed > 0:
		quit(1)
		return
	print("All camera pitch tests OK")
	quit(0)


func _find_land(world) -> Vector2i:
	for x in range(4, 36):
		for z in range(4, 36):
			var tile: int = world.get_tile_type(float(x) + 0.5, float(z) + 0.5)
			if _ActionTargeting._is_fluid_tile(tile):
				continue
			if tile == _VoxelTypes.AIR:
				continue
			var surf: float = world.get_surface_height(float(x) + 0.5, float(z) + 0.5)
			if world.get_solid(float(x) + 0.5, surf, float(z) + 0.5):
				return Vector2i(x, z)
	return Vector2i(8, 8)


class _Dummy extends Node3D:
	var voxel_position: Vector3 = Vector3.ZERO

	func get_voxel_position() -> Vector3:
		return voxel_position
