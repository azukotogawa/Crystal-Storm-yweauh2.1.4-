extends SceneTree
## Live arbitrary-yaw validation: snap listed angles, dump F4, optional windowed shots.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

const ANGLES: Array = [0.0, 22.0, 45.0, 67.0, 90.0, 113.0, 135.0, 180.0, 225.0, 248.0, 270.0, 315.0, 359.0]
const ISO_PITCH := -35.264
const SUBJECTS: Array = [
	"flat", "stone_wall", "gate", "bridge", "ramp_east", "dig_one", "water", "crystal",
]


var _failed: int = 0
var _scratch: String = ""
var _windowed: bool = false
var _game: Node = null
var _angles: Dictionary = {}
var _perf: Dictionary = {}


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-b4e8bbc86472/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	_windowed = DisplayServer.get_name() != "headless"
	print("CAMERA_ANGLE_VALIDATION_START windowed=%s" % str(_windowed))

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	_game = packed.instantiate()
	root.add_child(_game)
	var compose = _game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 8:
		await process_frame

	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var player = get_first_node_in_group("player")
	var editor = get_first_node_in_group("terrain_editor")
	if cm == null or world == null or player == null:
		_fail("missing world/player/cm")
		_finish()
		return
	var origin := _find_dry_origin(world, cm)
	var yard: Dictionary = _ValidationYard.apply(self, origin.x, origin.y)
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	_ValidationYard.apply_generated_ramps(self, yard.get("cells", {}))
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	# One live dig through the editor (world-grid, not camera-relative).
	var cells: Dictionary = yard.get("cells", {})
	if editor and cells.has("dig_one"):
		var d: Vector2i = cells.dig_one
		var sy: float = world.get_surface_height(float(d.x), float(d.y))
		editor.try_dig(Vector3(float(d.x) + 0.5, sy, float(d.y) + 0.5))
		if cm.has_method("await_rebuild_idle"):
			await cm.await_rebuild_idle(60)
	for _w2 in 6:
		await process_frame

	var cam: Camera3D = player.get("camera") if "camera" in player else null
	if cam == null:
		cam = get_first_node_in_group("camera")
	if cam == null:
		_fail("no camera")
		_finish()
		return
	cam.set("use_smoothing", false)
	cam.set("_scroll_lead", Vector3.ZERO)

	var insp = _game.get_node_or_null("LiveWorldInspector")
	if insp:
		insp.panel_open = true

	var boundary := Vector2i(
		int(floor(float(origin.x) / 16.0) + 1.0) * 16,
		origin.y + 3
	)

	for ang_v in ANGLES:
		var ang: float = float(ang_v)
		if cam.has_method("snap_yaw_degrees"):
			cam.snap_yaw_degrees(ang)
		else:
			cam.yaw_degrees = ang
			cam.yaw_target_degrees = ang
		cam.set("use_smoothing", false)
		_look(origin.x + 6, origin.y + 2)
		for _s in 4:
			await process_frame
		if absf(cam.rotation_degrees.y - ang) > 0.35 and absf(absf(cam.rotation_degrees.y - ang) - 360.0) > 0.35:
			_fail("yaw %.1f camera at %.3f" % [ang, cam.rotation_degrees.y])
		if absf(cam.rotation_degrees.x - ISO_PITCH) > 0.05:
			_fail("pitch drifted at yaw %.1f" % ang)

		var row := {
			"yaw": ang,
			"pitch": cam.rotation_degrees.x,
			"cam_yaw": cam.rotation_degrees.y,
			"zoom": cam.zoom_level,
			"size": cam.size,
			"cells": {},
		}
		for key in SUBJECTS:
			if not cells.has(key):
				continue
			var c: Vector2i = cells[key]
			row["cells"][key] = _dump_cell(c)
		row["cells"]["boundary"] = _dump_cell(boundary)
		_angles["%.0f" % ang] = row
		_assert_angle_row(ang, row)

		if absf(ang - 45.0) < 0.1 or absf(ang - 22.0) < 0.1:
			await process_frame
			_perf["%.0f" % ang] = _sample_perf()

		if _windowed:
			var pin_cell: Vector2i = cells.get("stone_wall", origin)
			if insp:
				insp.pin_cell = pin_cell
			_look(pin_cell.x, pin_cell.y)
			for _p in 3:
				await process_frame
			_shot("cam_%.0f_yard" % ang)
			if absf(ang - 45.0) < 0.1:
				for sub in ["gate", "bridge", "dig_one"]:
					if not cells.has(sub):
						continue
					var sc: Vector2i = cells[sub]
					if insp:
						insp.pin_cell = sc
					_look(sc.x, sc.y)
					for _q in 3:
						await process_frame
					_shot("cam_45_%s" % sub)

	_write(_scratch.path_join("camera_angle_validation.json"), {
		"origin": [origin.x, origin.y],
		"failed": _failed,
		"angles": _angles,
	})
	_write(_scratch.path_join("camera_angle_perf.json"), _perf)
	print("CAMERA_ANGLE_VALIDATION failed=%d angles=%d" % [_failed, _angles.size()])
	_finish()


func _dump_cell(c: Vector2i) -> Dictionary:
	var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, c.x, c.y)
	var disc: Array = []
	for d in snap.get("discrepancies", []):
		var ds := str(d)
		if ds.begins_with("RAMP_VISUAL"):
			continue
		disc.append(ds)
	return {
		"cell": [c.x, c.y],
		"covered": snap.get("column_mesh_covered", false),
		"faces": snap.get("column_face_codes", []),
		"disc": disc,
		"build_id": snap.get("build_id", ""),
		"visual_id": snap.get("visual_id", ""),
		"yaw": snap.get("orientation_yaw", 0.0),
		"visual_yaw": snap.get("visual_yaw", 0.0),
		"surface": snap.get("surface_height", 0.0),
		"walk": snap.get("walkable_height", 0.0),
		"collision_kind": snap.get("collision_kind", ""),
		"has_ramp": snap.get("has_ramp", false),
		"neighbors_covered": _neigh_ok(snap.get("neighbors", {})),
		"streamed": snap.get("streamed", false),
		"chunk": snap.get("chunk", []),
	}


func _neigh_ok(neigh: Dictionary) -> bool:
	for k in ["n", "e", "s", "w"]:
		var n: Dictionary = neigh.get(k, {})
		if n.is_empty():
			continue
		if not bool(n.get("covered", false)):
			return false
	return true


func _assert_angle_row(ang: float, row: Dictionary) -> void:
	var cells: Dictionary = row.get("cells", {})
	for key in cells.keys():
		var d: Dictionary = cells[key]
		var disc: Array = d.get("disc", [])
		if not bool(d.get("covered", false)) and not bool(d.get("has_ramp", false)):
			_fail("yaw %.0f %s not mesh-covered" % [ang, key])
		for item in disc:
			var ds := str(item)
			if ds.begins_with("MESH_HOLE"):
				_fail("yaw %.0f %s %s" % [ang, key, ds])
			elif key in ["gate", "bridge", "stone_wall", "wood_wall"] \
					and (ds.begins_with("ID:") or ds.begins_with("YAW:") or ds.begins_with("NODE:") or ds.begins_with("VISUAL_COUNT")):
				_fail("yaw %.0f %s %s" % [ang, key, ds])
		if key == "gate" and str(d.get("collision_kind", "")) != "passage":
			_fail("yaw %.0f gate collision_kind=%s" % [ang, d.get("collision_kind")])
		if key in ["stone_wall", "gate", "bridge"] and str(d.get("visual_id", "")) != key and str(d.get("build_id", "")) != key:
			_fail("yaw %.0f %s visual=%s" % [ang, key, d.get("visual_id")])
	_ok("yaw %.0f pitch=%.3f cells=%d" % [ang, float(row.get("pitch", 0.0)), cells.size()])


func _sample_perf() -> Dictionary:
	var fps := Engine.get_frames_per_second()
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var profiler = root.get_node_or_null("/root/PerfProfiler")
	var main_ms := process_ms
	if profiler and "_frame_us" in profiler:
		main_ms = float(profiler._frame_us) / 1000.0
	return {"fps": fps, "process_ms": process_ms, "main_ms": main_ms}


func _look(wx: int, wz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(wx) + 0.5
	player.voxel_position.z = float(wz) - 2.2
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()
	var cam = player.get("camera")
	if cam == null:
		return
	cam.set("use_smoothing", false)
	cam.set("_scroll_lead", Vector3.ZERO)
	if cam.has_method("get_offset_from_rotation"):
		cam.set("follow_target", player.global_position)
		cam.global_position = player.global_position + cam.get_offset_from_rotation()
		if cam.has_method("_update_camera_transform"):
			cam._update_camera_transform()
	if "zoom_level" in cam:
		cam.zoom_level = 14.0
		cam.size = 14.0


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _scratch.path_join("%s.png" % name)
	img.save_png(path)
	print("SHOT %s" % path)


func _find_dry_origin(world, cm) -> Vector2i:
	if world == null:
		return Vector2i(8, 8)
	for oz in range(8, 40, 4):
		for ox in range(8, 40, 4):
			var wet := false
			for dx in range(0, 16):
				for dz in range(0, 8):
					var tile: int = int(world.get_tile_type(float(ox + dx), float(oz + dz)))
					if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3, _VoxelTypes.RIVER, _VoxelTypes.WATER]:
						wet = true
						break
					if cm and not _ActionTargeting._is_solid_column(world, cm, ox + dx, oz + dz):
						wet = true
						break
				if wet:
					break
			if not wet:
				return Vector2i(ox, oz)
	return Vector2i(8, 8)


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		print("WROTE %s" % path)


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All camera angle validation tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "CAMERA ANGLE VALIDATION FAILED")
