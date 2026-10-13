extends SceneTree
## Cutaway uniforms and the camera→player cone. Foot-level water stays.

const _Cutaway = preload("res://helpers/camera_cutaway.gd")
const _Settings = preload("res://systems/player_settings.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

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
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	root.add_child(world)
	var feet_node := Node3D.new()
	feet_node.name = "Feet"
	root.add_child(feet_node)
	var cam: Camera3D = Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	root.add_child(cam)
	await process_frame

	var cell := _find_land(world)
	var ws = _WorldSettings.get_active()
	var surf: float = world.get_surface_height(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var layer: float = ws.layer_height()
	# Dug pocket: feet under the rendered slab, camera above it on the same column.
	var wx: float = ws.column_to_world(float(cell.x) + 0.5)
	var wz: float = ws.column_to_world(float(cell.y) + 0.5)
	var feet := Vector3(wx, surf - 4.0, wz)
	var cam_pos := Vector3(wx, surf + layer + 28.0, wz)
	feet_node.global_position = feet
	cam.target = feet_node
	cam.global_position = cam_pos
	_Settings.camera_cutaway_enabled = true
	cam.update_cutaway_uniforms()

	_assert_project_globals()
	if _Cutaway.submit_count < 1:
		_fail("camera did not submit cutaway uniforms")
	elif absf(_Cutaway.submitted_enabled - 1.0) > 0.01:
		_fail("submitted cutaway_enabled want 1 got %s" % _Cutaway.submitted_enabled)
	elif _Cutaway.submitted_player.distance_to(feet) > 0.05:
		_fail("submitted player %s want %s" % [_Cutaway.submitted_player, feet])
	elif _Cutaway.submitted_camera.distance_to(cam.global_position) > 0.05:
		_fail("submitted camera %s want %s" % [_Cutaway.submitted_camera, cam.global_position])
	elif absf(_Cutaway.submitted_radius - _Cutaway.RADIUS_AT_PLAYER) > 0.01 \
			or absf(_Cutaway.submitted_radius_near - _Cutaway.RADIUS_AT_CAMERA) > 0.01 \
			or absf(_Cutaway.submitted_feet_clear - _Cutaway.FEET_CLEAR) > 0.01 \
			or absf(_Cutaway.submitted_past - _Cutaway.PAST_DISTANCE) > 0.01:
		_fail("submitted cutaway radii do not match the shader contract")
	else:
		_ok("cutaway uniforms submitted for the player, camera, and radii")
	_assert_server_echo(feet, cam.global_position, 1.0)

	var occluders := 0
	var dir: Vector3 = (feet - cam_pos).normalized()
	var travel: float = cam_pos.distance_to(feet)
	var t := 0.5
	while t < travel - 0.5:
		var p: Vector3 = cam_pos + dir * t
		var cx: float = ws.world_to_column(p.x)
		var cz: float = ws.world_to_column(p.z)
		var column_surf: float = world.get_surface_height(cx, cz)
		var in_slab: bool = p.y >= column_surf and p.y <= column_surf + layer
		if in_slab and p.y > feet.y + _Cutaway.FEET_CLEAR:
			occluders += 1
			if not _Cutaway.contains(p, feet, cam_pos):
				_fail("occluding slab point %s is outside the cutaway" % p)
				break
		t += 0.75
	if occluders == 0:
		_fail("camera→player ray crossed no rendered slab")
	else:
		_ok("%d occluding slab samples sit in the cutaway" % occluders)

	var lid := Vector3(wx, feet.y + 0.35, wz)
	if _Cutaway.contains(lid, feet, cam_pos):
		_fail("foot-level point was cut away")
	else:
		_ok("foot-level water stays")
	var side := Vector3(wx + 18.0, surf + layer * 0.5, wz)
	if _Cutaway.contains(side, feet, cam_pos):
		_fail("a point far off the ray was cut away")
	else:
		_ok("cutaway ignores terrain off the camera ray")
	# Off the vertical camera ray and beyond the player radius. Raising Y on the
	# axis would still sit inside the cone.
	var past := Vector3(wx + _Cutaway.PAST_DISTANCE + 12.0, feet.y + _Cutaway.FEET_CLEAR + 4.0, wz)
	if _Cutaway.contains(past, feet, cam_pos):
		_fail("terrain past the player was cut away")
	else:
		_ok("cutaway stops just past the player")

	_Settings.camera_cutaway_enabled = false
	cam.update_cutaway_uniforms()
	if absf(_Cutaway.submitted_enabled) > 0.01:
		_fail("settings toggle did not clear cutaway_enabled")
	else:
		_ok("camera cutaway toggle turns the uniform off")
	_assert_server_echo(feet, cam.global_position, 0.0)
	_Settings.camera_cutaway_enabled = true

	if _failed > 0:
		quit(1)
		return
	print("All camera cutaway tests OK")
	quit(0)


func _assert_project_globals() -> void:
	var names := {
		"cutaway_enabled": "float",
		"cutaway_player": "vec3",
		"cutaway_camera": "vec3",
		"cutaway_radius": "float",
		"cutaway_radius_near": "float",
		"cutaway_feet_clear": "float",
		"cutaway_past": "float",
	}
	for param in names.keys():
		var key := "shader_globals/%s" % param
		if not ProjectSettings.has_setting(key):
			_fail("project is missing %s" % key)
			continue
		var spec: Dictionary = ProjectSettings.get_setting(key)
		if str(spec.get("type", "")) != str(names[param]):
			_fail("%s type %s want %s" % [param, spec.get("type"), names[param]])
	if _failed == 0:
		_ok("project shader globals declare the cutaway uniforms")


func _assert_server_echo(feet: Vector3, cam_pos: Vector3, enabled: float) -> void:
	var got = RenderingServer.global_shader_parameter_get("cutaway_enabled")
	if typeof(got) == TYPE_NIL:
		print("NOTE headless RenderingServer does not echo shader globals")
		return
	if absf(_as_float(got) - enabled) > 0.01:
		_fail("server cutaway_enabled %s want %s" % [got, enabled])
		return
	var player_v: Vector3 = _as_vec(RenderingServer.global_shader_parameter_get("cutaway_player"))
	var cam_v: Vector3 = _as_vec(RenderingServer.global_shader_parameter_get("cutaway_camera"))
	if player_v.distance_to(feet) > 0.05 or cam_v.distance_to(cam_pos) > 0.05:
		_fail("server uniforms player %s camera %s" % [player_v, cam_v])
	else:
		_ok("RenderingServer cutaway uniforms match the rig")


func _as_float(v) -> float:
	var t: int = typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(v)
	_fail("shader global was not a number (type %s)" % t)
	return -1.0


func _as_vec(v) -> Vector3:
	if typeof(v) == TYPE_VECTOR3:
		return v
	_fail("shader global was not a vector (type %s)" % typeof(v))
	return Vector3(9999, 9999, 9999)


func _find_land(world) -> Vector2i:
	var targeting = load("res://player/action_targeting.gd")
	for x in range(4, 36):
		for z in range(4, 36):
			var tile: int = world.get_tile_type(float(x) + 0.5, float(z) + 0.5)
			if targeting._is_fluid_tile(tile):
				continue
			return Vector2i(x, z)
	return Vector2i(8, 8)
