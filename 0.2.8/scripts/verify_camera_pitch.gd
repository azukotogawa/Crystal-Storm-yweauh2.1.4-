extends SceneTree

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

const _PITCH_PATH := "user://verify_camera_pitch.json"

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
	var old_path := _PlayerSettings.settings_path
	_PlayerSettings.settings_path = _PITCH_PATH
	_delete_pitch_file()
	_PlayerSettings.load_settings()
	var cam: Camera3D = Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	var anchor := Node3D.new()
	root.add_child(anchor)
	root.add_child(cam)
	await process_frame
	var iso_default: float = float(cam.ISO_PITCH_DEG)
	var defs_now: Dictionary = _PlayerSettings.defaults()
	if absf(float(defs_now.get("camera_pitch_degrees", 0.0)) - iso_default) > 0.001:
		_fail("settings default pitch %.4f does not match iso %.4f" % [float(defs_now.get("camera_pitch_degrees", 0.0)), iso_default])
	elif absf(float(cam.pitch_degrees) - iso_default) > 0.02:
		_fail("fresh camera pitch %.3f is not the iso default" % float(cam.pitch_degrees))
	else:
		_ok("default pitch is unchanged")
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
		origin = aim + Vector3(0.15, 8.0 + absf(pitch) * 0.05, 0.1)
		var dir: Vector3 = (aim - origin).normalized()
		var pick: Dictionary = _ActionTargeting.pick_along_ray(
			origin, dir, player, world, null, 8.0, true
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

	await _check_pitch_persistence(cam, anchor)
	cam._pitch_persist_wait = -1.0
	_PlayerSettings.settings_path = old_path
	_delete_pitch_file()

	if _failed > 0:
		quit(1)
		return
	print("All camera pitch tests OK")
	quit(0)


func _check_pitch_persistence(cam: Camera3D, anchor: Node3D) -> void:
	var iso: float = float(cam.ISO_PITCH_DEG)
	var writes := _PlayerSettings.camera_pitch_save_count
	cam.snap_pitch_degrees(-60.0)
	await process_frame
	if _PlayerSettings.camera_pitch_save_count != writes:
		_fail("snap_pitch_degrees wrote the settings file")
	else:
		_ok("programmatic pitch snap does not write settings")

	cam.pitch_save_delay = 1000.0
	cam.apply_pitch_input(-8.0)
	if not cam.pitch_save_pending():
		_fail("pitch input did not schedule a save")
	await process_frame
	if _PlayerSettings.camera_pitch_save_count != writes:
		_fail("pitch input wrote the settings file on the same frame")
	else:
		_ok("pitch save waits instead of writing every frame")
	cam.flush_pitch_save()
	if cam.pitch_save_pending():
		_fail("flush left a pitch save pending")
	if _PlayerSettings.camera_pitch_save_count != writes + 1:
		_fail("flush did not write the pitch once (count %d)" % _PlayerSettings.camera_pitch_save_count)
	else:
		_ok("pitch flushes once on release")
	var saved := float(cam.pitch_target_degrees)
	await process_frame
	await process_frame
	if _PlayerSettings.camera_pitch_save_count != writes + 1:
		_fail("pitch kept writing after the flush")

	_PlayerSettings.camera_pitch_degrees = iso
	var loaded: Dictionary = _PlayerSettings.load_settings()
	if absf(float(loaded.get("camera_pitch_degrees", 0.0)) - saved) > 0.02:
		_fail("reloaded pitch %.3f want %.3f" % [float(loaded.get("camera_pitch_degrees", 0.0)), saved])
	elif absf(_PlayerSettings.camera_pitch_degrees - saved) > 0.02:
		_fail("static pitch did not reload")
	else:
		_ok("saved pitch reloads from the settings file")

	var cam_saved: Camera3D = Camera3D.new()
	cam_saved.set_script(load("res://player/camera.gd"))
	cam_saved.use_smoothing = false
	root.add_child(cam_saved)
	cam_saved.target = anchor
	await process_frame
	if absf(float(cam_saved.pitch_degrees) - saved) > 0.02:
		_fail("new camera restored %.3f want %.3f" % [float(cam_saved.pitch_degrees), saved])
	else:
		_ok("new camera restores the saved pitch")

	var data := _PlayerSettings.load_settings()
	data["camera_pitch_degrees"] = -120.0
	if not _PlayerSettings.save_settings(data):
		_fail("could not write an out-of-range pitch")
		return
	var cam_low: Camera3D = Camera3D.new()
	cam_low.set_script(load("res://player/camera.gd"))
	root.add_child(cam_low)
	await process_frame
	if absf(float(cam_low.pitch_degrees) - float(cam.PITCH_MIN_DEG)) > 0.01:
		_fail("restored pitch %.3f was not clamped to min %.3f" % [float(cam_low.pitch_degrees), float(cam.PITCH_MIN_DEG)])
	else:
		_ok("restored pitch clamps to the minimum")

	data = _PlayerSettings.load_settings()
	data["camera_pitch_degrees"] = 40.0
	_PlayerSettings.save_settings(data)
	var cam_high: Camera3D = Camera3D.new()
	cam_high.set_script(load("res://player/camera.gd"))
	root.add_child(cam_high)
	await process_frame
	if absf(float(cam_high.pitch_degrees) - float(cam.PITCH_MAX_DEG)) > 0.01:
		_fail("restored pitch %.3f was not clamped to max %.3f" % [float(cam_high.pitch_degrees), float(cam.PITCH_MAX_DEG)])
	else:
		_ok("restored pitch clamps to the maximum")

	_PlayerSettings.set_camera_pitch(-50.0)
	_PlayerSettings.reset_bindings()
	var kept: Dictionary = _PlayerSettings.load_settings()
	if absf(float(kept.get("camera_pitch_degrees", 0.0)) - (-50.0)) > 0.02:
		_fail("binding reset cleared the saved pitch")
	else:
		_ok("binding reset keeps the saved pitch")

	cam_saved._pitch_persist_wait = -1.0
	cam_low._pitch_persist_wait = -1.0
	cam_high._pitch_persist_wait = -1.0


func _delete_pitch_file() -> void:
	var path := ProjectSettings.globalize_path(_PITCH_PATH)
	if FileAccess.file_exists(_PITCH_PATH):
		DirAccess.remove_absolute(path)


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
